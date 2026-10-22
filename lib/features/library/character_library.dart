import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/local_store.dart';
import '../../shared/models/mallangtalk_models.dart';

/// 앱에 기본으로 들어 있는 캐릭터 시나리오 파일 목록 ('캐릭터 추가 > 받아오기'에 보임)
const builtinScenarioAssets = ['assets/scenarios/sample_character.json'];

/// [초보자 노트] 앱 안에 들어 있는 기본 캐릭터들을 읽어오는 FutureProvider입니다.
/// 4단계에서 서버가 생기면 '받아오기' 목록은 서버의 공개 캐릭터 목록으로 바뀝니다.
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
      return [
        for (final bundle in _builtins)
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

  /// 캐릭터 추가 (같은 ID가 있으면 새 내용으로 교체하고, 그 캐릭터 대화방은 새 내용으로 다시 열림)
  Future<void> add(ScenarioBundle bundle, CharacterSource source) async {
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

  /// 캐릭터 삭제 (대화 기록·앨범도 같이 지움)
  Future<void> remove(String id) async {
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
    // 처음 실행하면 기본 캐릭터와의 대화방을 하나 열어 둠
    final rooms = ref.watch(localStoreProvider).loadChatRooms() ??
        [for (final e in entries) if (e.source == CharacterSource.builtin) e.id];
    return [for (final id in rooms) if (ids.contains(id)) id];
  }

  /// 대화방을 열면 맨 위로 올림
  void open(String id) {
    if (state.isNotEmpty && state.first == id) return;
    state = [id, for (final r in state) if (r != id) r];
    ref.read(localStoreProvider).saveChatRooms(state);
  }

  void leave(String id) {
    state = [for (final r in state) if (r != id) r];
    ref.read(localStoreProvider).saveChatRooms(state);
  }
}

final chatRoomsProvider =
    NotifierProvider<ChatRoomsNotifier, List<String>>(ChatRoomsNotifier.new);
