import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/mallangtalk_api.dart';
import '../../core/network/server_info.dart';
import '../../core/storage/local_store.dart';
import 'auth_state.dart';

/// [초보자 노트] 같은 계정이면 PC와 폰이 같은 내 프로필·친구 목록·진행도·앨범을 보게 맞추는 곳이에요.
/// 로그인하면(앱을 열 때마다) 한 번 서버와 비교해서, 키마다 더 나중에 바뀐 쪽 값을 남겨요.
/// 그 뒤로는 값이 바뀔 때마다 잠깐 모았다가 서버로 올려요 (SyncOutbox).
final stateSyncProvider = FutureProvider<void>((ref) async {
  final server = ref.watch(serverInfoProvider).valueOrNull;
  final token = ref.watch(authProvider.select((a) => a.token));
  final username = ref.watch(authProvider.select((a) => a.user?.username));
  final outbox = ref.watch(syncOutboxProvider);
  if (server == null || !server.accounts || token == null || username == null) return;

  final api = ref.read(apiFactoryProvider)(server.baseUrl, token);
  final changed = await syncState(api, ref.read(localStoreProvider), username);

  Future<void> sender(Set<String> keys) => pushState(api, ref.read(localStoreProvider), keys);
  outbox.sender = sender;
  ref.onDispose(() {
    if (outbox.sender == sender) outbox.stop();
  });
  // 서버 값으로 바뀐 게 있으면 저장소를 읽는 화면·상태를 새로 읽게
  if (changed) ref.invalidate(localStoreProvider);
  await outbox.flush();
});

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
      push[key] = SyncedValue(local, localAt);
    }
  }
  await store.saveSyncUser(username);
  await _sendInChunks(api, push);
  return changed;
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
