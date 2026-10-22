import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/models/mallangtalk_models.dart';

/// [초보자 노트] 브라우저 저장소(웹에서는 localStorage)를 여는 FutureProvider입니다.
/// 앱이 뜰 때 한 번만 열고, 아래 LocalStore가 이걸 감싸서 씁니다.
/// 시크릿 창이나 저장소가 막힌 환경에서는 null이 되고, 그때는 메모리에만 저장합니다(새로고침하면 사라짐).
final sharedPreferencesProvider = FutureProvider<SharedPreferences?>((ref) async {
  try {
    return await SharedPreferences.getInstance();
  } catch (_) {
    return null;
  }
});

final localStoreProvider = Provider<LocalStore>(
  (ref) => LocalStore(ref.watch(sharedPreferencesProvider).requireValue),
);

/// 이벤트가 끝날 때마다 저장해 두는 진행 기록 (이벤트 중간에 새로고침하면 그 이벤트는 처음부터)
class SavedRun {
  final int affection;
  final List<String> flags;
  final List<String> completedEventIds;
  final List<ChatMessageLog> messages;
  final bool cleared;

  const SavedRun({
    required this.affection,
    required this.flags,
    required this.completedEventIds,
    required this.messages,
    this.cleared = false,
  });

  Map<String, dynamic> toJson() => {
        'affection': affection,
        'flags': flags,
        'completed_event_ids': completedEventIds,
        'messages': [for (final m in messages) m.toJson()],
        'cleared': cleared,
      };

  factory SavedRun.fromJson(Map<String, dynamic> json) {
    return SavedRun(
      affection: json['affection'] as int? ?? 0,
      flags: [for (final f in json['flags'] as List? ?? const []) f as String],
      completedEventIds: [
        for (final id in json['completed_event_ids'] as List? ?? const []) id as String,
      ],
      messages: [
        for (final m in json['messages'] as List? ?? const [])
          ChatMessageLog.fromJson(m as Map<String, dynamic>),
      ],
      cleared: json['cleared'] as bool? ?? false,
    );
  }
}

/// [초보자 노트] 진행 기록, 앨범(모은 컷씬), 내 AI 키 설정을 브라우저에 저장하고 꺼내는 곳입니다.
/// 4단계에서 서버가 생기면 진행 기록과 앨범은 서버 DB(user_play_sessions, user_unlocked_gallery)로 옮기고,
/// AI 키는 기획대로 계속 브라우저에만 둡니다.
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences? _prefs;
  final Map<String, Object> _memory = {};

  String? _getString(String key) {
    try {
      return _prefs?.getString(key) ?? _memory[key] as String?;
    } catch (_) {
      return _memory[key] as String?;
    }
  }

  List<String>? _getStringList(String key) {
    try {
      return _prefs?.getStringList(key) ?? _memory[key] as List<String>?;
    } catch (_) {
      return _memory[key] as List<String>?;
    }
  }

  Future<void> _write(String key, Object? value) async {
    if (value == null) {
      _memory.remove(key);
    } else {
      _memory[key] = value;
    }
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      if (value == null) {
        await prefs.remove(key);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is List<String>) {
        await prefs.setStringList(key, value);
      }
    } catch (_) {
      // 저장소가 가득 찼거나 막혀도 메모리 값으로 계속 진행
    }
  }

  static const _apiKeyKey = 'byok_claude_api_key';
  static const _libraryKey = 'library_v1';
  static const _chatRoomsKey = 'chat_rooms_v1';
  static const _profileKey = 'my_profile';
  static const _modelKey = 'byok_claude_model';

  String _runKey(String characterId) => 'run_$characterId';
  String _albumKey(String characterId) => 'album_$characterId';

  SavedRun? loadRun(String characterId) {
    final raw = _getString(_runKey(characterId));
    if (raw == null) return null;
    try {
      return SavedRun.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // 형식이 바뀐 옛 기록은 무시하고 처음부터
    }
  }

  Future<void> saveRun(String characterId, SavedRun run) =>
      _write(_runKey(characterId), jsonEncode(run.toJson()));

  Future<void> clearRun(String characterId) => _write(_runKey(characterId), null);

  List<String> loadAlbum(String characterId) =>
      _getStringList(_albumKey(characterId)) ?? const [];

  Future<void> saveAlbum(String characterId, List<String> eventIds) =>
      _write(_albumKey(characterId), List<String>.of(eventIds));

  /// 이미 본 특별 이벤트 (실제 시간 1회성, '다시 하기'를 해도 다시 안 옴)
  List<String> loadSeenSpecials(String characterId) =>
      _getStringList('specials_$characterId') ?? const [];

  Future<void> saveSeenSpecials(String characterId, List<String> eventIds) =>
      _write('specials_$characterId', List<String>.of(eventIds));

  /// 내 AI 키는 회사마다 따로 저장 (Claude는 예전 키 이름 그대로)
  String _keyKey(String provider) => provider == 'claude' ? _apiKeyKey : 'byok_key_$provider';
  String _providerModelKey(String provider) => provider == 'claude' ? _modelKey : 'byok_model_$provider';

  String? get provider => _getString('byok_provider');
  String? apiKeyOf(String provider) => _getString(_keyKey(provider));
  String? modelOf(String provider) => _getString(_providerModelKey(provider));

  Future<void> saveByok({required String provider, required String apiKey, required String model}) async {
    await _write('byok_provider', provider);
    await _write(_keyKey(provider), apiKey);
    await _write(_providerModelKey(provider), model);
  }

  Future<void> saveProvider(String provider) => _write('byok_provider', provider);

  Future<void> clearApiKey(String provider) => _write(_keyKey(provider), null);

  /// 말랑톡 서버 로그인 (토큰과 아이디·닉네임). 로그아웃하면 지움
  String? get authToken => _getString('auth_token');
  String? get authUserJson => _getString('auth_user');
  Future<void> saveAuth(String? token, String? userJson) async {
    await _write('auth_token', token);
    await _write('auth_user', userJson);
  }

  /// 말랑톡 서버의 접속 코드 (서버 .env에 ACCESS_CODE가 있을 때만 필요)
  String? get serverAccessCode => _getString('server_access_code');
  Future<void> saveServerAccessCode(String? code) =>
      _write('server_access_code', code == null || code.isEmpty ? null : code);

  /// 만들기 화면에서 쓰던 새 캐릭터 초안 (새로고침·새 버전이 떠도 이어 쓰게)
  String? loadStudioDraft() => _getString('studio_draft_v1');
  Future<void> saveStudioDraft(String json) => _write('studio_draft_v1', json);

  /// 내 캐릭터 목록 (받아온·만든 캐릭터의 시나리오 전체를 JSON으로). 처음 실행이면 null
  List<Map<String, dynamic>>? loadLibrary() {
    final raw = _getString(_libraryKey);
    if (raw == null) return null;
    try {
      return [for (final e in jsonDecode(raw) as List) e as Map<String, dynamic>];
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLibrary(List<Map<String, dynamic>> entries) =>
      _write(_libraryKey, jsonEncode(entries));

  /// 채팅방 목록 (최근 대화한 순서대로 캐릭터 ID). 처음 실행이면 null
  List<String>? loadChatRooms() => _getStringList(_chatRoomsKey);

  Future<void> saveChatRooms(List<String> characterIds) =>
      _write(_chatRoomsKey, List<String>.of(characterIds));

  /// 캐릭터를 지울 때 진행 기록과 앨범도 같이 지움
  Future<void> forgetCharacter(String characterId) async {
    await clearRun(characterId);
    await _write(_albumKey(characterId), null);
    await _write('tempo_$characterId', null);
    await _write('nickname_$characterId', null);
    await _write('specials_$characterId', null);
  }

  /// 캐릭터별 대화 속도 배율 (1.0 = 리얼하게, 작을수록 빠름)
  double? chatTempo(String characterId) =>
      double.tryParse(_getString('tempo_$characterId') ?? '');

  Future<void> saveChatTempo(String characterId, double tempo) =>
      _write('tempo_$characterId', tempo.toString());

  /// 설정의 내 기본 프로필 {nickname, intro}
  Map<String, dynamic>? get myProfile {
    final raw = _getString(_profileKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveMyProfile(Map<String, dynamic> profile) =>
      _write(_profileKey, jsonEncode(profile));

  /// 이 캐릭터와의 대화에서 쓰는 내 별명 (없으면 기본 프로필 별명)
  String? chatNickname(String characterId) => _getString('nickname_$characterId');

  Future<void> saveChatNickname(String characterId, String nickname) =>
      _write('nickname_$characterId', nickname);
}
