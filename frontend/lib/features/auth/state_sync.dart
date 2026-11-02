import 'dart:convert';
import 'dart:math' show max;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/mallangtalk_api.dart';
import '../../core/network/server_info.dart';
import '../../core/storage/local_store.dart';
import 'auth_state.dart';

/// [초보자 노트] 같은 계정이면 PC와 폰이 같은 내 프로필·친구 목록·진행도·앨범을 보게 맞추는 곳이에요.
/// 로그인하면(앱을 열 때마다) 한 번 서버와 비교해서, 키마다 더 나중에 바뀐 쪽(또는 같은 회차에서 더 많이 진행된 쪽) 값을 남겨요.
/// 그 뒤로는 값이 바뀔 때마다 잠깐 모았다가 서버로 올려요 (SyncOutbox).
/// 서버 값이 이 기기 값보다 비었거나 크게 줄었으면 바로 덮지 않고 [SyncConflict]로 돌려줘서
/// 사용자가 '이 기기 데이터 지키기'를 고를 수 있게 해요 (2026-11-02, PC 접속 뒤 폰 데이터가 사라진 일).
final stateSyncProvider = FutureProvider<List<SyncConflict>>((ref) async {
  final server = ref.watch(serverInfoProvider).valueOrNull;
  final token = ref.watch(authProvider.select((a) => a.token));
  final username = ref.watch(authProvider.select((a) => a.user?.username));
  final outbox = ref.watch(syncOutboxProvider);
  if (server == null || !server.accounts || token == null || username == null) return const [];

  final store = ref.read(localStoreProvider);
  if (store.syncUser != null && store.syncUser != username) {
    // 다른 계정으로 바뀐 경우 이전 계정의 미전송 대기열을 먼저 비움
    outbox.clear();
  }

  final api = ref.read(apiFactoryProvider)(server.baseUrl, token);
  final result = await syncState(api, store, username);
  final changed = result.changed;
  // 물어볼 항목은 사용자가 고를 때까지 서버로 올리지 않음
  outbox.forget({for (final c in result.conflicts) c.key});

  Future<void> sender(Set<String> keys) => pushState(api, ref.read(localStoreProvider), keys);
  outbox.sender = sender;
  ref.onDispose(() {
    if (outbox.sender == sender) outbox.stop();
  });
  // 서버 값으로 바뀐 게 있으면 저장소를 읽는 화면·상태를 새로 읽게
  if (changed) {
    ref.invalidate(localStoreProvider);
    invalidateUserStateProviders(ref);
  }
  await outbox.flush();
  return result.conflicts;
});

/// 한쪽 값으로 덮으면 다른 쪽 데이터가 많이 사라지는 항목 (자동으로 덮지 않고 사용자에게 물어봄)
class SyncConflict {
  final String key;
  final SyncedValue remote;

  /// 이 기기 쪽이 더 많음 (서버 값이 비었거나 크게 줄어 있음)
  final bool localBigger;

  /// 시각으로만 보면 서버 쪽이 더 최근
  final bool remoteNewer;
  const SyncConflict(this.key, this.remote, {required this.localBigger, required this.remoteNewer});

  /// 화면에 보여줄 이름
  String get label {
    if (key == 'library_v1') return '캐릭터 목록';
    if (key == 'chat_rooms_v1') return '채팅방 목록';
    if (key == 'my_profile') return '내 프로필';
    if (key == 'favorites_v1') return '즐겨찾기';
    if (key.startsWith('run_')) return '대화 기록';
    if (key.startsWith('scene_')) return '현실 장면 기록';
    if (key.startsWith('album_') || key.startsWith('photos_')) return '앨범';
    if (key.startsWith('persona_') || key.startsWith('userinfo_')) return '내 설정';
    return '진행 기록';
  }
}

class SyncResult {
  final bool changed;
  final List<SyncConflict> conflicts;
  const SyncResult(this.changed, this.conflicts);
}

/// 물어본 항목 정리. keepBigger면 항목마다 데이터가 더 많은 쪽을, 아니면 더 최근에 바뀐 쪽을 남김.
/// 남기는 쪽 값은 지금 시각으로 서버와 이 기기에 같이 기록해서 다른 기기도 그 값을 받게 함
Future<void> resolveConflicts(MallangtalkApi api, LocalStore store, List<SyncConflict> conflicts,
    {required bool keepBigger}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final push = <String, SyncedValue>{};
  for (final c in conflicts) {
    final keepLocal = keepBigger ? c.localBigger : !c.remoteNewer;
    final ts = max(now, max(c.remote.updatedAt, store.syncedAt(c.key) ?? 0) + 1);
    if (keepLocal) {
      await store.markSynced(c.key, ts);
      push[c.key] = SyncedValue(store.rawValue(c.key), ts);
    } else {
      await store.applyRemote(c.key, SyncedValue(c.remote.value, ts));
      push[c.key] = SyncedValue(c.remote.value, ts);
    }
  }
  await _sendInChunks(api, push);
}

bool _isEmptyValue(Object? v) {
  if (v == null) return true;
  if (v is List) return v.isEmpty;
  if (v is String) {
    final t = v.trim();
    return t.isEmpty || t == '[]' || t == '{}' || t == 'null' || t == '""';
  }
  return false;
}

/// 서버 값을 받으면 이 기기 데이터가 크게 사라지는지 (비었거나 절반 아래로 줄어듦)
bool _wouldLoseData(Object? local, Object? remote) {
  if (_isEmptyValue(local)) return false;
  if (_isEmptyValue(remote)) return true;
  final l = _size(local);
  return l >= 2000 && _size(remote) * 2 < l;
}

/// 누적되는 목록 키(앨범·사진·본 이벤트·선택지·특별 이벤트): 지운 게 아니라면 두 기기 목록을 합쳐 유실 방지
const _additivePrefixes = ['album_', 'photos_', 'chosen_', 'seen_', 'specials_'];

bool _isAdditiveKey(String key) => _additivePrefixes.any(key.startsWith);

/// 서버와 이 기기의 연동 값을 맞춤.
/// - 이 계정으로 맞춘 적 없는 기기(새 기기·로그아웃 뒤 다시 로그인)는 서버에 있는 값을 덮지 않고 받기만 함
/// - 서버 값을 받으면 이 기기 데이터가 크게 사라지는 항목은 덮지 않고 conflicts로 돌려줌
Future<SyncResult> syncState(MallangtalkApi api, LocalStore store, String username) async {
  final remote = await api.myState();
  var changed = false;
  final conflicts = <SyncConflict>[];
  if (store.syncUser != null && store.syncUser != username) {
    // 다른 계정으로 로그인함: 이전 계정의 진행도가 섞이지 않게 이 기기 값을 비움
    await store.clearSynced();
    changed = true;
  }
  // 새로 들어온 기기: 로그인 전에 쓴 기본값(빈 목록·처음 프로필)이 더 최근 시각이라도 서버 값을 이기면 안 됨
  final joining = !store.hasSyncedWith(username);

  Future<void> take(String key, SyncedValue r, {bool guard = true}) async {
    if (guard && _wouldLoseData(store.rawValue(key), r.value)) {
      conflicts.add(SyncConflict(key, r, localBigger: true, remoteNewer: true));
      return;
    }
    if (jsonEncode(store.rawValue(key)) != jsonEncode(r.value)) changed = true;
    await store.applyRemote(key, r);
  }

  final push = <String, SyncedValue>{};
  for (final key in {...store.syncedKeys(), ...remote.keys}) {
    if (!LocalStore.isSyncedKey(key)) continue;
    final r = remote[key];
    final localAt = store.syncedAt(key);
    final local = store.rawValue(key);
    if (r == null) {
      if (local != null || localAt != null) push[key] = SyncedValue(local, localAt ?? 0);
      continue;
    }

    // 1. 누적형 목록(앨범·사진·본 대화·고른 선택지)은 둘 다 목록이면 합집합으로 병합
    if (_isAdditiveKey(key) && local is List && r.value is List) {
      final localList = [for (final v in local) '$v'];
      final remoteList = [for (final v in r.value as List) '$v'];
      final merged = <String>{...remoteList, ...localList}.toList();
      final nextTs = max(localAt ?? 0, r.updatedAt);
      if (jsonEncode(localList) != jsonEncode(merged)) {
        await take(key, SyncedValue(merged, nextTs));
      } else {
        await store.markSynced(key, nextTs);
      }
      if (jsonEncode(remoteList) != jsonEncode(merged)) {
        final pushTs = nextTs + 1;
        await store.markSynced(key, pushTs);
        push[key] = SyncedValue(merged, pushTs);
      }
      continue;
    }

    // 2. 스토리/대화 진행 기록(run_*): 같은 회차 안에서 다른 기기가 초기 상태로 덮어쓰지 못하게 진행도 우선 비교
    if (key.startsWith('run_') && local is String && r.value is String) {
      final cmp = _compareRunProgress(local, r.value as String);
      if (cmp > 0) {
        final pushTs = max(localAt ?? 0, r.updatedAt) + 1;
        await store.markSynced(key, pushTs);
        push[key] = SyncedValue(local, pushTs);
        continue;
      } else if (cmp < 0) {
        final takeTs = max(localAt ?? 0, r.updatedAt);
        // 진행도 비교로 정한 것('처음부터 다시' 포함)이라 크기로 막지 않음
        await take(key, SyncedValue(r.value, takeTs), guard: false);
        continue;
      }
    }

    if (joining) {
      // 서버에 이미 값이 있으면 서버 것을 받음 (비어 있는 서버 값이 이 기기 데이터를 지우려 하면 위 take가 물어봄)
      if (jsonEncode(local) != jsonEncode(r.value)) {
        await take(key, r);
      } else {
        await store.markSynced(key, r.updatedAt);
      }
    } else if (localAt == null) {
      // 연동 기능이 생기기 전부터 이 기기에 있던 값. 서버 값도 그런 옛 값(시각 0)이면
      // 대화·앨범이 더 많이 쌓인(더 긴) 쪽을 남김
      if (local != null && r.updatedAt == 0 && _size(local) > _size(r.value)) {
        await store.markSynced(key, 0);
        push[key] = SyncedValue(local, 0);
      } else {
        await take(key, r);
      }
    } else if (r.updatedAt > localAt) {
      await take(key, r);
    } else if (localAt > r.updatedAt) {
      if (_wouldLoseData(r.value, local)) {
        // 이 기기의 빈(또는 크게 줄어든) 값이 서버의 많은 데이터를 덮으려 함 → 물어봄
        conflicts.add(SyncConflict(key, r, localBigger: false, remoteNewer: false));
      } else {
        push[key] = SyncedValue(local, localAt);
      }
    }
  }
  await store.saveSyncUser(username);
  await _sendInChunks(api, push);
  await store.saveSyncBase(username);
  return SyncResult(changed, conflicts);
}

/// 두 진행 기록(SavedRun JSON)을 비교해 어느 쪽이 더 진행된 상태인지 판정.
/// > 0 이면 local이 더 진행됨, < 0 이면 remote가 더 진행됨, 0 이면 시각(updatedAt)으로 비교.
int _compareRunProgress(String localJson, String remoteJson) {
  try {
    final l = jsonDecode(localJson) as Map<String, dynamic>;
    final r = jsonDecode(remoteJson) as Map<String, dynamic>;

    // '처음부터 다시'를 명시적으로 누른 시각이 다르면 더 최근에 초기화한 회차가 우선
    final lReset = (l['reset_at'] as num?)?.toInt() ?? 0;
    final rReset = (r['reset_at'] as num?)?.toInt() ?? 0;
    if (lReset != rReset) return lReset.compareTo(rReset);

    final lDone = (l['completed_event_ids'] as List? ?? const []).length;
    final rDone = (r['completed_event_ids'] as List? ?? const []).length;
    final lMsgs = l['messages'] as List? ?? const [];
    final rMsgs = r['messages'] as List? ?? const [];

    if (lMsgs.isNotEmpty && rMsgs.isNotEmpty) {
      final lFirst = (lMsgs.first as Map?)?['id'];
      final rFirst = (rMsgs.first as Map?)?['id'];
      if (lFirst != null && rFirst != null && lFirst != rFirst) {
        // 다른 기기에서 자동 시작된 초기 상태(완료 이벤트 0개, 메시지 6개 이하)가
        // 이미 스토리를 진행한 상태를 덮어쓰지 않도록 진행된 쪽 보호
        if (lDone > 0 && rDone == 0 && rMsgs.length <= 6) return 1;
        if (rDone > 0 && lDone == 0 && lMsgs.length <= 6) return -1;
        if (lDone != rDone) return lDone.compareTo(rDone);
        // 서로 다른 대화(예: 한쪽에서 비우고 새로 시작): 길이보다 마지막 톡이 더 최근인 쪽
        final lLast = _lastMessageAt(lMsgs);
        final rLast = _lastMessageAt(rMsgs);
        if (lLast != null && rLast != null && lLast != rLast) return lLast.compareTo(rLast);
        if ((lMsgs.length - rMsgs.length).abs() >= 4) return lMsgs.length.compareTo(rMsgs.length);
        return 0;
      }
    }

    final lCleared = l['cleared'] == true ? 1 : 0;
    final rCleared = r['cleared'] == true ? 1 : 0;
    if (lCleared != rCleared) return lCleared.compareTo(rCleared);
    if (lDone != rDone) return lDone.compareTo(rDone);
    if (lMsgs.length != rMsgs.length) return lMsgs.length.compareTo(rMsgs.length);

    final lBubble = (l['next_bubble'] as num?)?.toInt() ?? 0;
    final rBubble = (r['next_bubble'] as num?)?.toInt() ?? 0;
    if (l['node_id'] == r['node_id'] && lBubble != rBubble) {
      return lBubble.compareTo(rBubble);
    }
    return 0;
  } catch (_) {
    return 0;
  }
}

DateTime? _lastMessageAt(List msgs) {
  final last = msgs.isEmpty ? null : msgs.last;
  return last is Map ? DateTime.tryParse('${last['timestamp'] ?? ''}') : null;
}

/// 바뀐 키들의 지금 값을 서버로
Future<void> pushState(MallangtalkApi api, LocalStore store, Set<String> keys) => _sendInChunks(api, {
      for (final key in keys)
        key: SyncedValue(store.rawValue(key), store.syncedAt(key) ?? DateTime.now().millisecondsSinceEpoch),
    });

int _size(Object? value) => jsonEncode(value).length;

/// 캐릭터 목록처럼 큰 값이 있어도 서버 한도를 넘지 않게 나눠서 보냄
Future<void> _sendInChunks(MallangtalkApi api, Map<String, SyncedValue> items) async {
  const limit = 8 * 1024 * 1024;
  var chunk = <String, SyncedValue>{};
  var size = 0;
  for (final MapEntry(:key, :value) in items.entries) {
    final itemSize = _size(value.value);
    if (chunk.isNotEmpty && size + itemSize > limit) {
      await api.saveMyState(chunk);
      chunk = {};
      size = 0;
    }
    chunk[key] = value;
    size += itemSize;
  }
  if (chunk.isNotEmpty) await api.saveMyState(chunk);
}

/// 물어본 항목을 정리하고(데이터 많은 쪽 / 최근 쪽) 화면·상태를 새로 읽게 함
final resolveSyncConflictsProvider =
    Provider<Future<void> Function(List<SyncConflict> conflicts, {required bool keepBigger})>(
        (ref) => (conflicts, {required keepBigger}) async {
              final server = ref.read(serverInfoProvider).valueOrNull;
              final token = ref.read(authProvider).token;
              if (server == null || token == null) return;
              final api = ref.read(apiFactoryProvider)(server.baseUrl, token);
              await resolveConflicts(api, ref.read(localStoreProvider), conflicts, keepBigger: keepBigger);
              ref.invalidate(localStoreProvider);
              invalidateUserStateProviders(ref);
              ref.invalidate(stateSyncProvider);
            });

/// 앱 맨 위 문지기가 기다리는 연동 (서버가 꺼져 있어도 앱은 이 기기 값으로 열림)
final bootSyncProvider = FutureProvider<void>((ref) async {
  try {
    await ref.watch(stateSyncProvider.future);
  } catch (e) {
    debugPrint('기기 연동 실패 (이 기기 값으로 계속): $e');
  }
});
