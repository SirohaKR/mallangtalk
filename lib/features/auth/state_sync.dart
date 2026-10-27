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
final stateSyncProvider = FutureProvider<void>((ref) async {
  final server = ref.watch(serverInfoProvider).valueOrNull;
  final token = ref.watch(authProvider.select((a) => a.token));
  final username = ref.watch(authProvider.select((a) => a.user?.username));
  final outbox = ref.watch(syncOutboxProvider);
  if (server == null || !server.accounts || token == null || username == null) return;

  final api = ref.read(apiFactoryProvider)(server.baseUrl, token);
  // 먼저 아직 안 올라간 이 기기의 변경분을 보낸 뒤 서버와 비교
  Future<void> sender(Set<String> keys) => pushState(api, ref.read(localStoreProvider), keys);
  outbox.sender = sender;
  ref.onDispose(() {
    if (outbox.sender == sender) outbox.stop();
  });
  await outbox.flush();

  final changed = await syncState(api, ref.read(localStoreProvider), username);

  // 서버 값으로 바뀐 게 있으면 저장소를 읽는 화면·상태를 새로 읽게
  if (changed) ref.invalidate(localStoreProvider);
  await outbox.flush();
});

/// 누적되는 목록 키(앨범·사진·본 이벤트·선택지·특별 이벤트): 지운 게 아니라면 두 기기 목록을 합쳐 유실 방지
const _additivePrefixes = ['album_', 'photos_', 'chosen_', 'seen_', 'specials_'];

bool _isAdditiveKey(String key) => _additivePrefixes.any(key.startsWith);

/// 서버와 이 기기의 연동 값을 맞춤. 이 기기 값이 바뀌었으면 true
Future<bool> syncState(MallangtalkApi api, LocalStore store, String username) async {
  final remote = await api.myState();
  var changed = false;
  if (store.syncUser != null && store.syncUser != username) {
    // 다른 계정으로 로그인함: 이전 계정의 진행도가 섞이지 않게 이 기기 값을 비움
    await store.clearSynced();
    changed = true;
  }

  Future<void> take(String key, SyncedValue r) async {
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
        await take(key, SyncedValue(r.value, takeTs));
        continue;
      }
    }

    if (localAt == null) {
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
      push[key] = SyncedValue(local, localAt);
    }
  }
  await store.saveSyncUser(username);
  await _sendInChunks(api, push);
  return changed;
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

/// 앱 맨 위 문지기가 기다리는 연동 (서버가 꺼져 있어도 앱은 이 기기 값으로 열림)
final bootSyncProvider = FutureProvider<void>((ref) async {
  try {
    await ref.watch(stateSyncProvider.future);
  } catch (e) {
    debugPrint('기기 연동 실패 (이 기기 값으로 계속): $e');
  }
});
