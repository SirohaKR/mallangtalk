import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/mallangtalk_api.dart';
import '../../core/storage/local_store.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../auth/auth_state.dart';
import '../auth/state_sync.dart';
import '../chat/chat_notifier.dart' show characterIdOfRoom;

/// 앱에 기본으로 들어 있는 캐릭터 시나리오 파일 목록.
/// 샘플 캐릭터(윤도하·서이준)는 2026-10 화면 개편 때 앱에서 뺐어요 (테스트용 파일은 test/fixtures에 있음)
const builtinScenarioAssets = <String>[];

/// [초보자 노트] 앱 안에 들어 있는 기본 캐릭터들을 읽어오는 FutureProvider입니다. 지금은 비어 있어요.
/// '말랑이 찾기'에는 이것과 서버에 올라온 유저 캐릭터(galleryProvider)가 같이 보여요.
final builtinBundlesProvider = FutureProvider<List<ScenarioBundle>>((ref) async {
  return [
    for (final path in builtinScenarioAssets)
      ScenarioBundle.fromJson(
        jsonDecode(await rootBundle.loadString(path)) as Map<String, dynamic>,
      ),
  ];
});

/// 캐릭터를 어디서 가져왔는지
enum CharacterSource {
  builtin, // 앱 기본 캐릭터
  imported, // 파일로 받아온 캐릭터
  created, // 내가 만든 캐릭터 (엑셀 대본 또는 AI 생성)
}

/// 친구창에서 즐겨찾기한 캐릭터 ID (이 브라우저에 저장)
class FavoritesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.watch(localStoreProvider).favorites.toSet();

  bool isFavorite(String id) => state.contains(id);

  Future<void> toggle(String id) async {
    state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};
    await ref.read(localStoreProvider).saveFavorites(state.toList());
  }
}

final favoritesProvider = NotifierProvider<FavoritesNotifier, Set<String>>(FavoritesNotifier.new);

class LibraryEntry {
  final ScenarioBundle bundle;
  final CharacterSource source;
  final DateTime addedAt;

  const LibraryEntry({required this.bundle, required this.source, required this.addedAt});

  String get id => bundle.character.id;

  String get sourceLabel => switch (source) {
        CharacterSource.builtin => '기본 캐릭터',
        CharacterSource.imported => '받아온 캐릭터',
        CharacterSource.created => '내가 만든 캐릭터',
      };
}

/// [초보자 노트] '내 캐릭터' 목록입니다. 받아오거나 만든 캐릭터의 시나리오 전체를 브라우저에 저장합니다.
/// 처음 실행하면 기본 캐릭터(윤도하)를 하나 넣어 둡니다.
class CharacterLibraryNotifier extends Notifier<List<LibraryEntry>> {
  late LocalStore _store;
  late List<ScenarioBundle> _builtins;

  @override
  List<LibraryEntry> build() {
    _store = ref.watch(localStoreProvider);
    _builtins = ref.watch(builtinBundlesProvider).requireValue;
    final saved = _store.loadLibrary();
    if (saved == null) {
      // 처음 실행하면 대표 기본 캐릭터 하나만 친구로 넣어 둠 (나머지는 받아오기 갤러리에서)
      return [
        for (final bundle in _builtins.take(1))
          LibraryEntry(bundle: bundle, source: CharacterSource.builtin, addedAt: DateTime.now()),
      ];
    }
    final entries = <LibraryEntry>[];
    for (final raw in saved) {
      final entry = _entryFromJson(raw);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  LibraryEntry? _entryFromJson(Map<String, dynamic> raw) {
    try {
      final source = CharacterSource.values.byName(raw['source'] as String);
      final addedAt = DateTime.tryParse(raw['added_at'] as String? ?? '') ?? DateTime.now();
      final ScenarioBundle bundle;
      if (source == CharacterSource.builtin) {
        // 기본 캐릭터는 ID만 저장하고 내용은 앱 안의 최신 파일을 씀
        final match = _builtins.where((b) => b.character.id == raw['id']).firstOrNull;
        if (match == null) return null;
        bundle = match;
      } else {
        bundle = ScenarioBundle.fromJson(raw['bundle'] as Map<String, dynamic>);
      }
      return LibraryEntry(bundle: bundle, source: source, addedAt: addedAt);
    } catch (_) {
      return null; // 깨진 항목은 건너뜀
    }
  }

  Future<void> _persist() => _store.saveLibrary([
        for (final entry in state)
          {
            'id': entry.id,
            'source': entry.source.name,
            'added_at': entry.addedAt.toIso8601String(),
            if (entry.source != CharacterSource.builtin) 'bundle': entry.bundle.toJson(),
          },
      ]);

  LibraryEntry? byId(String id) => state.where((e) => e.id == id).firstOrNull;

  /// 캐릭터 정보만 바꾸기 (프로필 사진·한줄 소개 등)
  Future<void> updateCharacter(CharacterModel character) async {
    final entry = byId(character.id);
    if (entry == null) return;
    await add(
      entry.bundle.copyWithCharacter(character),
      entry.source == CharacterSource.builtin ? CharacterSource.imported : entry.source,
    );
  }

  /// 캐릭터 추가 (같은 ID가 있으면 새 내용으로 교체하고, 그 캐릭터 대화방은 새 내용으로 다시 열림)
  /// 로그인했으면 내가 만든 캐릭터는 서버 DB에도 저장해요 (사진은 서버로 옮겨지고 주소만 남음)
  Future<void> add(ScenarioBundle bundle, CharacterSource source) async {
    await _putLocal(bundle, source);
    if (source == CharacterSource.created) await _upload(bundle);
  }

  Future<void> _upload(ScenarioBundle bundle) async {
    final api = ref.read(accountApiProvider);
    if (api == null) return;
    try {
      final saved = await api.saveCharacter(bundle, published: !bundle.character.unlisted);
      // 서버가 사진을 주소로 바꾼 파일로 교체 → 브라우저 저장소에는 사진이 안 남음
      if (byId(saved.character.id) != null) await _putLocal(saved, CharacterSource.created);
    } catch (e) {
      debugPrint('캐릭터 서버 저장 실패 (다음 로그인 때 다시 올림): $e');
    }
  }

  /// 로그인하면 한 번: 서버의 내 캐릭터를 받아오고, 이 브라우저에만 있던 내 캐릭터는 서버에 올림
  Future<void> syncWithServer(MallangtalkApi api) async {
    final mine = await api.myCharacters();
    final onServer = {for (final c in mine) c.bundle.character.id};
    for (final entry in [...state]) {
      if (entry.source == CharacterSource.created && !onServer.contains(entry.id)) await _upload(entry.bundle);
    }
    for (final c in mine) {
      await _putLocal(c.bundle, CharacterSource.created);
    }
  }

  Future<void> _putLocal(ScenarioBundle bundle, CharacterSource source) async {
    final existing = byId(bundle.character.id);
    final entry = LibraryEntry(
      bundle: bundle,
      source: source,
      addedAt: existing?.addedAt ?? DateTime.now(),
    );
    state = existing == null
        ? [...state, entry]
        : [for (final e in state) e.id == entry.id ? entry : e];
    await _persist();
  }

  /// 말랑이 찾기에서 친구 추가 (서버에 친구 수도 올림. 실패해도 친구 추가는 됨)
  Future<void> addFriend(ScenarioBundle bundle, CharacterSource source) async {
    await add(bundle, source);
    if (source != CharacterSource.imported) return;
    try {
      await ref.read(accountApiProvider)?.addFriend(bundle.character.id);
    } catch (e) {
      debugPrint('친구 수 올리기 실패: $e');
    }
  }

  /// 캐릭터 삭제 (대화 기록·앨범도 같이 지움). 내가 만든 캐릭터면 서버에서도 지움
  Future<void> remove(String id) async {
    final source = byId(id)?.source;
    try {
      if (source == CharacterSource.created) {
        await ref.read(accountApiProvider)?.deleteCharacter(id);
      } else if (source == CharacterSource.imported) {
        await ref.read(accountApiProvider)?.removeFriend(id);
      }
    } catch (e) {
      debugPrint('캐릭터 서버 삭제 실패: $e');
    }
    state = [for (final e in state) if (e.id != id) e];
    await _persist();
    await _store.forgetCharacter(id);
  }
}

final characterLibraryProvider =
    NotifierProvider<CharacterLibraryNotifier, List<LibraryEntry>>(CharacterLibraryNotifier.new);

/// ID로 내 캐릭터의 시나리오 찾기 (없으면 null)
final characterBundleProvider = Provider.family<ScenarioBundle?, String>((ref, id) {
  final entries = ref.watch(characterLibraryProvider);
  return entries.where((e) => e.id == id).firstOrNull?.bundle;
});

/// [초보자 노트] 채팅방 목록 (최근에 대화한 순서). 캐릭터 프로필에서 '1:1 채팅'을 누르면 여기에 생깁니다.
class ChatRoomsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    final entries = ref.watch(characterLibraryProvider);
    final ids = entries.map((e) => e.id).toSet();
    final rooms = ref.watch(localStoreProvider).loadChatRooms() ?? const <String>[];
    return [for (final id in rooms) if (ids.contains(characterIdOfRoom(id))) id];
  }

  /// 대화방을 열면 맨 위로 올림 (스토리 방은 캐릭터 ID, 자유대화 방은 ID#free)
  void open(String roomId) {
    if (state.isNotEmpty && state.first == roomId) return;
    state = [roomId, for (final r in state) if (r != roomId) r];
    ref.read(localStoreProvider).saveChatRooms(state);
  }

  /// 이 캐릭터와 가장 최근에 연 대화방 (없으면 null)
  String? latestOf(String characterId) {
    for (final r in state) {
      if (characterIdOfRoom(r) == characterId) return r;
    }
    return null;
  }

  /// 캐릭터와의 대화방을 모두 나감 (스토리·자유대화 둘 다)
  void leave(String characterId) {
    state = [for (final r in state) if (characterIdOfRoom(r) != characterId) r];
    ref.read(localStoreProvider).saveChatRooms(state);
  }
}

final chatRoomsProvider =
    NotifierProvider<ChatRoomsNotifier, List<String>>(ChatRoomsNotifier.new);

/// 로그인하면 내 캐릭터를 서버와 맞춤 (앱 맨 위 문지기가 지켜봄)
final librarySyncProvider = FutureProvider<void>((ref) async {
  final api = ref.watch(accountApiProvider);
  if (api == null) return;
  await ref.watch(bootSyncProvider.future); // 기기 연동으로 캐릭터 목록을 먼저 받아 둠
  await ref.read(characterLibraryProvider.notifier).syncWithServer(api);
});

/// '말랑이 찾기' 갤러리의 캐릭터 하나
class GalleryItem {
  final ScenarioBundle bundle;
  /// 만든 사람 닉네임 (앱 기본 캐릭터면 null)
  final String? creator;
  final bool mine;
  final DateTime? createdAt;
  final int friends;
  const GalleryItem(this.bundle, {this.creator, this.mine = false, this.createdAt, this.friends = 0});

  bool get isBuiltin => creator == null;

  CharacterModel get character => bundle.character;

  /// 검색: 이름·한줄 소개·태그·만든 사람 중 하나라도 들어 있으면
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final c = character;
    return [c.name, c.tagline, c.statusMessage, creator ?? '', ...c.tags].any((s) => s.toLowerCase().contains(q.replaceFirst('#', '')));
  }
}

/// [초보자 노트] '말랑이 찾기' 목록: 앱 기본 캐릭터 + 서버에 올라온 유저들의 캐릭터 (최근에 고친 순)
final galleryProvider = FutureProvider<List<GalleryItem>>((ref) async {
  final builtins = await ref.watch(builtinBundlesProvider.future);
  final items = [for (final b in builtins) GalleryItem(b)];
  final api = ref.watch(accountApiProvider);
  if (api != null) {
    try {
      final ids = {for (final b in builtins) b.character.id};
      for (final c in await api.publishedCharacters()) {
        if (!ids.contains(c.bundle.character.id)) {
          items.add(GalleryItem(c.bundle, creator: c.creator, mine: c.mine, createdAt: c.createdAt, friends: c.friends));
        }
      }
    } catch (e) {
      debugPrint('받아오기 목록을 못 불러옴: $e');
    }
  }
  return items;
});
