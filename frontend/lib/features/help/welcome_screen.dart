import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/ai_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/utils/file_io.dart';
import '../home/friends_screen.dart';
import '../library/character_library.dart';
import '../settings/byok_settings.dart';
import '../settings/user_profile.dart';
import 'help_guide.dart';

/// 처음 켠 사람인지 (본 안내도, 별명도, 친구도 없음). 이미 쓰던 사람에겐 인사·프로필·키 화면을 안 띄워요.
bool isFirstVisit(WidgetRef ref) =>
    shouldShowHelp(ref, HelpGuide.welcome) &&
    ref.read(helpSeenProvider).isEmpty &&
    !ref.read(userProfileProvider).hasNickname &&
    ref.read(characterLibraryProvider).isEmpty;

/// [초보자 노트] 처음 사용자 안내 앞부분 (/welcome): 인사 → 내 프로필 → AI 키 연결.
/// 다 보면 말랑이 찾기로 돌아가고, 거기서 화면 안내(3단계)가 이어져요.
/// '혼자 둘러볼게요'·'건너뛰기'를 누르면 처음 안내 전체를 본 걸로 쳐요.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  int _page = 0;
  late final UserProfile _profile;
  late final TextEditingController _nickname;
  late final TextEditingController _intro;
  late String _avatar;
  AiProvider _provider = AiProvider.gemini;
  final _key = TextEditingController();

  @override
  void initState() {
    super.initState();
    _profile = ref.read(userProfileProvider);
    _nickname = TextEditingController(text: _profile.nickname);
    _intro = TextEditingController(text: _profile.intro);
    _avatar = _profile.avatarUrl;
  }

  @override
  void dispose() {
    _nickname.dispose();
    _intro.dispose();
    _key.dispose();
    super.dispose();
  }

  void _close({bool skipTour = false}) {
    ref.read(helpSeenProvider.notifier).mark(skipTour ? HelpGuide.tour : const [HelpGuide.welcome]);
    final request = ref.read(helpRequestProvider.notifier);
    context.go('/discover');
    // 이어서 말랑이 찾기 화면 안내 (이 화면이 닫힌 다음 그림에서)
    if (!skipTour) WidgetsBinding.instance.addPostFrameCallback((_) => request.state = HelpGuide.discover);
  }

  Future<void> _saveProfile() async {
    final nick = _nickname.text.trim();
    if (nick.isNotEmpty || _intro.text.trim().isNotEmpty || _avatar != _profile.avatarUrl) {
      await ref.read(userProfileProvider.notifier).save(nickname: nick, intro: _intro.text, avatarUrl: _avatar);
    }
    if (mounted) setState(() => _page = 2);
  }

  Future<void> _saveKey() async {
    final key = _key.text.trim();
    if (key.isNotEmpty) {
      final notifier = ref.read(byokSettingsProvider.notifier);
      await notifier.saveKey(_provider, key);
      if (!ref.read(byokSettingsProvider).canUseAi || ref.read(byokSettingsProvider).provider != _provider) {
        await notifier.save(provider: _provider, apiKey: '', model: notifier.peek(_provider).model);
      }
    }
    if (mounted) _close();
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_page) {
      0 => _hello(),
      1 => _profilePage(),
      _ => _keyPage(),
    };
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: body),
        ),
      ),
    );
  }

  Widget _head(int index) => SizedBox(
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: 20),
            HelpDots(index),
            const Spacer(),
            TextButton(
              key: const ValueKey('welcome_skip'),
              onPressed: () => _close(skipTour: true),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF5E4E54)),
              child: const Text('건너뛰기'),
            ),
            const SizedBox(width: 8),
          ],
        ),
      );

  Widget _buttons({required String later, required VoidCallback onLater, required VoidCallback onNext}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Row(
          children: [
            OutlinedButton(
              key: const ValueKey('welcome_later'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52), foregroundColor: const Color(0xFF4A3D42)),
              onPressed: onLater,
              child: Text(later),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: const ValueKey('welcome_next'),
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB83B66),
                    minimumSize: const Size.fromHeight(52),
                    textStyle: AppTextStyles.choiceButton),
                onPressed: onNext,
                child: const Text('다음'),
              ),
            ),
          ],
        ),
      );

  /// 1. 인사
  Widget _hello() {
    const steps = ['내 프로필 정하기', 'AI 키 연결하기', '말랑이 찾기', '대화 시작하기', '대화방 둘러보기'];
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
            children: [
              const Center(child: MallangFace(size: 132)),
              const SizedBox(height: 16),
              const Text('안녕! 나는 말랑이야',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('말랑톡은 마음에 드는 말랑이와 톡으로 이야기하는 곳이야.\n처음 한 번만 짧게 알려 줄게.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF5E4E54))),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceWhite,
                  border: Border.all(color: const Color(0xFFEEE3E7)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < steps.length; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border:
                              i == steps.length - 1 ? null : const Border(bottom: BorderSide(color: Color(0xFFF1E7EB))),
                        ),
                        child: Row(children: [
                          HelpPin(i + 1, size: 22),
                          const SizedBox(width: 10),
                          Expanded(child: Text(steps[i], style: const TextStyle(fontSize: 14))),
                          if (i == 1) const Text('건너뛰어도 돼요', style: AppTextStyles.messageTime),
                        ]),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text('1분이면 끝나요', textAlign: TextAlign.center, style: AppTextStyles.messageTime),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                key: const ValueKey('welcome_start'),
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB83B66),
                    minimumSize: const Size.fromHeight(52),
                    textStyle: AppTextStyles.choiceButton),
                onPressed: () => setState(() => _page = 1),
                child: const Text('좋아, 알려 줘'),
              ),
              TextButton(
                key: const ValueKey('welcome_alone'),
                onPressed: () => _close(skipTour: true),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF5E4E54), minimumSize: const Size(0, 44)),
                child: const Text('혼자 둘러볼게요'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 2. 내 프로필 (설정 › 계정 · 프로필과 같은 값)
  Widget _profilePage() => Column(
        children: [
          _head(0),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              children: [
                const MallangSays('먼저, 너를 뭐라고 부르면 좋을까? 말랑이들이 톡에서 이 이름으로 불러 줄 거야.', size: 56),
                const SizedBox(height: 20),
                Center(
                  child: InkWell(
                    key: const ValueKey('welcome_avatar'),
                    customBorder: const CircleBorder(),
                    onTap: () async {
                      final image = await pickProfileImage(context);
                      if (image != null) setState(() => _avatar = image);
                    },
                    child: _avatar.isEmpty
                        ? Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.surfaceWhite,
                              border: Border.all(color: const Color(0xFFD9C2CB), width: 2),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.photo_camera_outlined, color: Color(0xFF6E5C63)),
                                SizedBox(height: 4),
                                Text('사진 고르기', style: AppTextStyles.messageTime),
                              ],
                            ),
                          )
                        : MyProfileAvatar(url: _avatar, radius: 52),
                  ),
                ),
                const SizedBox(height: 6),
                const Text('고르면 동그라미 자르기 화면이 떠요', textAlign: TextAlign.center, style: AppTextStyles.messageTime),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('welcome_nickname'),
                  controller: _nickname,
                  maxLength: 12,
                  decoration: const InputDecoration(labelText: '별명'),
                ),
                const Text('대본 속 {이름} 자리에 들어가고, 내가 만든 말랑이의 제작자 이름으로도 보여요', style: AppTextStyles.messageTime),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('welcome_intro'),
                  controller: _intro,
                  minLines: 1,
                  maxLines: null,
                  decoration: const InputDecoration(labelText: '한줄 소개 (선택)', hintText: '예: 로판 좋아하는 대학생'),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFF7EEF2), borderRadius: BorderRadius.circular(12)),
                  child: const Text(
                    '설정 › 계정 · 프로필에서 언제든 바꿀 수 있어요. 로그인은 나중에 해도 돼요 (내 말랑이를 공개하거나 PC·폰을 연동할 때 필요해요)',
                    style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF6E5C63)),
                  ),
                ),
              ],
            ),
          ),
          _buttons(later: '나중에', onLater: () => setState(() => _page = 2), onNext: _saveProfile),
        ],
      );

  /// 3. AI 키 (설정 › AI 연결과 같은 곳에 저장)
  Widget _keyPage() {
    String note(AiProvider p) => switch (p) {
          AiProvider.gemini => '무료로 시작',
          AiProvider.claude => '유료 · 대본이 자연스러워요',
          AiProvider.openai => '유료',
        };
    return Column(
      children: [
        _head(1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            children: [
              const MallangSays('자유대화랑 AI로 만들기에는 **AI 키**가 필요해. 스토리만 볼 거면 지금은 건너뛰어도 괜찮아!', size: 56),
              const SizedBox(height: 16),
              const Text('어느 AI를 쓸까요?', style: AppTextStyles.speakerName),
              const SizedBox(height: 8),
              // 무료로 시작할 수 있는 Gemini를 맨 위에
              for (final p in [AiProvider.gemini, ...AiProvider.values.where((p) => p != AiProvider.gemini)])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: _provider == p ? const Color(0xFFFDF3F7) : AppColors.surfaceWhite,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                          color: _provider == p ? const Color(0xFFB83B66) : const Color(0xFFEEE3E7),
                          width: _provider == p ? 2 : 1),
                    ),
                    child: InkWell(
                      key: ValueKey('welcome_ai_${p.name}'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _provider = p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(children: [
                          Icon(_provider == p ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                              size: 20, color: _provider == p ? const Color(0xFFB83B66) : AppColors.textMuted),
                          const SizedBox(width: 10),
                          Text(aiShortName(p), style: const TextStyle(fontSize: 14)),
                          const Spacer(),
                          Text(note(p), style: AppTextStyles.messageTime),
                        ]),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceWhite,
                  border: Border.all(color: const Color(0xFFEEE3E7)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const HelpPin(1, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextButton(
                          key: const ValueKey('welcome_key_page'),
                          style: TextButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              padding: EdgeInsets.zero,
                              foregroundColor: const Color(0xFFB83B66)),
                          onPressed: () => launchUrl(Uri.parse(aiKeyPage(_provider)), webOnlyWindowName: '_blank'),
                          child: Text('${aiShortName(_provider)} 키 받는 페이지 열기 ↗',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Padding(padding: EdgeInsets.only(top: 12), child: HelpPin(2, size: 22)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('welcome_key'),
                          controller: _key,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: '복사한 키 붙여 넣기'),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text('키는 이 기기에만 저장되고 서버에 남지 않아요. 다른 AI 키는 설정 › AI 연결에서 더 넣을 수 있어요',
                  style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF6E5C63))),
            ],
          ),
        ),
        _buttons(later: '나중에 할게요', onLater: _close, onNext: _saveKey),
      ],
    );
  }
}
