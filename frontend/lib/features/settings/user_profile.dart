import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/local_store.dart';
import '../auth/auth_state.dart';
import '../library/character_library.dart';

/// 설정에서 정하는 내 기본 프로필
class UserProfile {
  final String nickname;
  final String intro; // 나에 대한 한줄 소개 (AI 자유대화에서 캐릭터가 참고)
  final String avatarUrl; // 친구창 맨 위 내 프로필 사진 (비우면 기본 아이콘)
  /// 기본 페르소나: 대화 속 나의 설정 (나이·성격·외모·상황 등). 캐릭터와 대화를 시작할 때 기본으로 들어감
  final String persona;

  const UserProfile({this.nickname = '', this.intro = '', this.avatarUrl = '', this.persona = ''});

  bool get hasNickname => nickname.trim().isNotEmpty;
}

/// [초보자 노트] 내 기본 프로필. 캐릭터와 대화를 처음 시작할 때 이 별명이 기본값으로 들어가요.
class UserProfileNotifier extends Notifier<UserProfile> {
  @override
  UserProfile build() {
    final raw = ref.watch(localStoreProvider).myProfile ?? const {};
    return UserProfile(
      nickname: raw['nickname'] as String? ?? '',
      intro: raw['intro'] as String? ?? '',
      avatarUrl: raw['avatar_url'] as String? ?? '',
      persona: raw['persona'] as String? ?? '',
    );
  }

  /// [avatarUrl]·[persona]를 안 주면 그대로
  Future<void> save({required String nickname, required String intro, String? avatarUrl, String? persona}) async {
    state = UserProfile(
      nickname: nickname.trim(),
      intro: intro.trim(),
      avatarUrl: avatarUrl ?? state.avatarUrl,
      persona: (persona ?? state.persona).trim(),
    );
    await ref.read(localStoreProvider).saveMyProfile({
      'nickname': state.nickname,
      'intro': state.intro,
      if (state.avatarUrl.isNotEmpty) 'avatar_url': state.avatarUrl,
      if (state.persona.isNotEmpty) 'persona': state.persona,
    });
    // 로그인했다면 다른 사람이 보는 제작자 프로필도 같은 사진·별명·소개로 맞춰요.
    // (서버가 꺼져 있어도 이 기기 프로필은 저장된 채로 둬요)
    try {
      await ref.read(authProvider.notifier).pushProfile(
            nickname: state.nickname.isEmpty ? null : state.nickname,
            avatarUrl: state.avatarUrl,
            intro: state.intro,
          );
      ref.invalidate(galleryProvider);
    } catch (_) {}
  }

  /// 기본 페르소나만 바꾸기
  Future<void> savePersona(String persona) =>
      save(nickname: state.nickname, intro: state.intro, persona: persona);
}

final userProfileProvider =
    NotifierProvider<UserProfileNotifier, UserProfile>(UserProfileNotifier.new);

/// 캐릭터별 대화 설정: 이 대화에서 쓰는 내 별명·페르소나, 대화 속도
class ChatPrefs {
  final String? nickname; // null이면 아직 이 캐릭터와 대화를 시작하기 전
  final String? persona; // null이면 기본 페르소나
  final double tempo;

  const ChatPrefs({this.nickname, this.persona, this.tempo = 1.0});
}

class ChatTempoOption {
  final String label;
  final String note;
  final double tempo;

  const ChatTempoOption(this.label, this.note, this.tempo);

  static const all = [
    ChatTempoOption('리얼하게', '실제로 사람이 치는 것처럼 기다려요', 1.0),
    ChatTempoOption('조금 빠르게', '입력 중 시간을 절반 정도로', 0.55),
    ChatTempoOption('빠르게', '이야기만 빨리 보고 싶을 때', 0.25),
  ];
}

/// [초보자 노트] 캐릭터마다 따로 저장되는 내 별명과 대화 속도입니다.
class ChatPrefsNotifier extends FamilyNotifier<ChatPrefs, String> {
  @override
  ChatPrefs build(String characterId) {
    final store = ref.watch(localStoreProvider);
    return ChatPrefs(
      nickname: store.chatNickname(characterId),
      persona: store.chatPersona(characterId),
      tempo: store.chatTempo(characterId) ?? 1.0,
    );
  }

  Future<void> setNickname(String nickname) async {
    state = ChatPrefs(nickname: nickname.trim(), persona: state.persona, tempo: state.tempo);
    await ref.read(localStoreProvider).saveChatNickname(arg, nickname.trim());
  }

  Future<void> setPersona(String persona) async {
    state = ChatPrefs(nickname: state.nickname, persona: persona.trim(), tempo: state.tempo);
    await ref.read(localStoreProvider).saveChatPersona(arg, persona.trim());
  }

  Future<void> setTempo(double tempo) async {
    state = ChatPrefs(nickname: state.nickname, persona: state.persona, tempo: tempo);
    await ref.read(localStoreProvider).saveChatTempo(arg, tempo);
  }
}

final chatPrefsProvider =
    NotifierProvider.family<ChatPrefsNotifier, ChatPrefs, String>(ChatPrefsNotifier.new);

/// 이 캐릭터와의 대화에서 실제로 불리는 내 이름 (대화별 별명 → 기본 별명 → '너')
final chatNicknameProvider = Provider.family<String, String>((ref, characterId) {
  final own = ref.watch(chatPrefsProvider(characterId)).nickname;
  if (own != null && own.isNotEmpty) return own;
  final base = ref.watch(userProfileProvider).nickname;
  return base.isNotEmpty ? base : '너';
});

/// 이 캐릭터와의 대화에서 쓰는 내 페르소나 (대화별 → 기본 페르소나, 없으면 빈 글자)
final chatPersonaProvider = Provider.family<String, String>((ref, characterId) {
  return ref.watch(chatPrefsProvider(characterId)).persona ?? ref.watch(userProfileProvider).persona;
});

/// 서비스 말랑이에게 알려 준 내 정보 (띠·생일 등, 캐릭터마다 따로·연동). 페르소나 대신 씀
class ServiceUserInfoNotifier extends FamilyNotifier<Map<String, String>, String> {
  @override
  Map<String, String> build(String characterId) => ref.watch(localStoreProvider).serviceUserInfo(characterId);

  Future<void> save(Map<String, String> info) async {
    final clean = {
      for (final e in info.entries)
        if (e.value.trim().isNotEmpty) e.key.trim(): e.value.trim()
    };
    state = clean;
    await ref.read(localStoreProvider).saveServiceUserInfo(arg, clean);
  }
}

final serviceUserInfoProvider =
    NotifierProvider.family<ServiceUserInfoNotifier, Map<String, String>, String>(ServiceUserInfoNotifier.new);
