import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/local_store.dart';

/// 설정에서 정하는 내 기본 프로필
class UserProfile {
  final String nickname;
  final String intro; // 나에 대한 한줄 소개 (AI 자유대화에서 캐릭터가 참고)

  const UserProfile({this.nickname = '', this.intro = ''});

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
    );
  }

  Future<void> save({required String nickname, required String intro}) async {
    state = UserProfile(nickname: nickname.trim(), intro: intro.trim());
    await ref.read(localStoreProvider).saveMyProfile({
      'nickname': state.nickname,
      'intro': state.intro,
    });
  }
}

final userProfileProvider =
    NotifierProvider<UserProfileNotifier, UserProfile>(UserProfileNotifier.new);

/// 캐릭터별 대화 설정: 이 대화에서 쓰는 내 별명, 대화 속도
class ChatPrefs {
  final String? nickname; // null이면 아직 이 캐릭터와 대화를 시작하기 전
  final double tempo;

  const ChatPrefs({this.nickname, this.tempo = 1.0});
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
      tempo: store.chatTempo(characterId) ?? 1.0,
    );
  }

  Future<void> setNickname(String nickname) async {
    state = ChatPrefs(nickname: nickname.trim(), tempo: state.tempo);
    await ref.read(localStoreProvider).saveChatNickname(arg, nickname.trim());
  }

  Future<void> setTempo(double tempo) async {
    state = ChatPrefs(nickname: state.nickname, tempo: tempo);
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
