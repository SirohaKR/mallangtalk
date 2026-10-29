import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/ai_provider.dart';
import '../../core/network/server_info.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/utils/file_io.dart';
import '../home/friends_screen.dart';
import '../auth/auth_state.dart';
import '../chat/chat_ai_sheet.dart';
import 'byok_settings.dart';
import 'user_profile.dart';

/// [초보자 노트] 설정 첫 화면: 맨 위 계정 카드, 그 아래 '계정 · 프로필'과 'AI 연결' 두 칸으로 나눠요.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final user = ref.watch(authProvider).user;
    final ai = ref.watch(byokSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: Center(
        child: ConstrainedBox(
          constraints: AppSpacing.pageConstraints(context, maxDesktop: 760),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Material(
                  color: AppColors.surfaceWhite,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                    side: const BorderSide(color: AppColors.borderLight),
                  ),
                  child: ListTile(
                    key: const ValueKey('settings_account_card'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                    leading: MyProfileAvatar(url: profile.avatarUrl, radius: 26),
                    title: Text(
                      profile.hasNickname ? profile.nickname : (user?.nickname ?? '내 프로필'),
                      style: AppTextStyles.appBarTitle.copyWith(fontSize: 17),
                    ),
                    subtitle: Text(
                      user != null ? '${user.username} 계정으로 로그인' : '이 기기에 저장된 프로필',
                      style: AppTextStyles.systemNotice,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/settings/account'),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('계정 · 프로필'),
                subtitle: const Text('별명, 한줄 소개, 사진, 기본 페르소나', style: AppTextStyles.systemNotice),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/settings/account'),
              ),
              ListTile(
                key: const ValueKey('settings_ai'),
                leading: const Icon(Icons.vpn_key_outlined),
                title: const Text('AI 연결'),
                subtitle: Text(
                  ai.canUseAi ? '${ai.provider.label} 연결됨' : '키를 넣으면 자유대화와 AI로 만들기를 쓸 수 있어요',
                  style: AppTextStyles.systemNotice,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/settings/ai'),
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                child: Text(
                  '대화 속도와 이 대화에서 쓸 별명은 캐릭터마다 대화방 오른쪽 위 메뉴에서 바꿔요.',
                  style: AppTextStyles.messageTime,
                ),
              ),
              // 새로 빌드한 앱이 떴는지 확인용 (나스 Docker 빌드 때 정해짐)
              if (appBuild.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Text('앱 빌드: $appBuild', style: AppTextStyles.messageTime),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [초보자 노트] 계정 · 프로필 (/settings/account): 내 사진·별명·한줄 소개·기본 페르소나, 로그아웃
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  late final _profile = ref.read(userProfileProvider);
  late final _nickname = TextEditingController(text: _profile.nickname);
  late final _intro = TextEditingController(text: _profile.intro);
  late final _persona = TextEditingController(text: _profile.persona);
  late String _avatar = _profile.avatarUrl;

  @override
  void dispose() {
    _nickname.dispose();
    _intro.dispose();
    _persona.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    return Scaffold(
      appBar: AppBar(title: const Text('계정 · 프로필')),
      body: Center(
        child: ConstrainedBox(
          constraints: AppSpacing.pageConstraints(context, maxDesktop: 760),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Center(
                child: GestureDetector(
                  onTap: () async {
                    final image = await pickProfileImage(context);
                    if (image != null) setState(() => _avatar = image);
                  },
                  child: Stack(
                    children: [
                      MyProfileAvatar(url: _avatar, radius: 44),
                      const Positioned(
                        right: 0,
                        bottom: 0,
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.primaryPink,
                          child: Icon(Icons.photo_camera_rounded, size: 16, color: AppColors.surfaceWhite),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                '캐릭터와 대화를 처음 시작할 때 이 별명이 기본으로 들어가요. 로그인한 상태면 이 사진·별명·소개가 '
                '말랑이 찾기에 보이는 제작자 프로필로도 쓰여요.',
                style: AppTextStyles.systemNotice,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _nickname,
                maxLength: 12,
                decoration: const InputDecoration(labelText: '기본 별명', hintText: '캐릭터가 나를 부를 이름'),
              ),
              TextField(
                controller: _intro,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: '나에 대한 한줄 소개',
                  hintText: '예: 디자인과 3학년, 고양이 좋아함 (AI 자유대화에서 참고해요)',
                ),
              ),
              TextField(
                controller: _persona,
                minLines: 2,
                maxLines: 5,
                maxLength: 400,
                decoration: const InputDecoration(
                  labelText: '기본 페르소나',
                  alignLabelWithHint: true,
                  hintText: '대화 속 나의 설정 (나이·성격·외모·상황). 캐릭터와 대화를 시작할 때 기본으로 들어가요',
                  hintMaxLines: 2,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ElevatedButton(
                onPressed: () async {
                  await ref.read(userProfileProvider.notifier).save(
                        nickname: _nickname.text,
                        intro: _intro.text,
                        avatarUrl: _avatar,
                        persona: _persona.text,
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('내 프로필을 저장했어요')));
                  }
                },
                child: const Text('프로필 저장'),
              ),
              if (user != null) ...[
                const SizedBox(height: AppSpacing.xl),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_circle_rounded, color: AppColors.primaryPink),
                  title: Text('${user.nickname} (${user.username})'),
                  subtitle: const Text('PC와 폰에서 같은 계정으로 이어서 대화해요', style: AppTextStyles.systemNotice),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await ref.read(authProvider.notifier).logout();
                    if (context.mounted && context.canPop()) context.pop();
                  },
                  child: const Text('로그아웃'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// [초보자 노트] AI 연결 (/settings/ai): 쓸 AI 회사(Claude·ChatGPT·Gemini)를 고르고, 그 회사 키를 넣고 모델을 고르는 화면입니다.
class AiConnectScreen extends ConsumerStatefulWidget {
  const AiConnectScreen({super.key});

  @override
  ConsumerState<AiConnectScreen> createState() => _AiConnectScreenState();
}

class _AiConnectScreenState extends ConsumerState<AiConnectScreen> {
  /// 회사마다 키 칸 (와이어프레임 4-3: 여기선 키만, 쓸 AI·모델은 대화방 위에서 고름)
  final _keys = {for (final p in AiProvider.values) p: TextEditingController()};
  final _accessCode = TextEditingController();

  @override
  void initState() {
    super.initState();
    _accessCode.text = ref.read(byokSettingsProvider).accessCode ?? '';
  }

  @override
  void dispose() {
    for (final c in _keys.values) {
      c.dispose();
    }
    _accessCode.dispose();
    super.dispose();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _saveKeys() async {
    final notifier = ref.read(byokSettingsProvider.notifier);
    final typed = [
      for (final e in _keys.entries)
        if (e.value.text.trim().isNotEmpty) e.key
    ];
    if (typed.isEmpty) {
      _toast('넣을 키를 적어 주세요');
      return;
    }
    for (final p in typed) {
      await notifier.saveKey(p, _keys[p]!.text);
      _keys[p]!.clear();
    }
    // 기본 AI 회사에 키가 없으면 방금 키를 넣은 회사를 기본으로 (모델은 그 회사 기본)
    if (!ref.read(byokSettingsProvider).canUseAi) {
      final p = typed.first;
      await notifier.save(provider: p, apiKey: '', model: notifier.peek(p).model);
    }
    if (!mounted) return;
    setState(() {});
    _toast('키를 저장했어요');
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(byokSettingsProvider);
    final notifier = ref.read(byokSettingsProvider.notifier);
    final server = current.server;

    return Scaffold(
      appBar: AppBar(title: const Text('AI 연결')),
      body: Center(
        child: ConstrainedBox(
          constraints: AppSpacing.pageConstraints(context, maxDesktop: 760),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const Text(
                "AI 자유대화와 'AI로 만들기'에 쓰는 내 키예요. 키는 이 기기에만 저장되고 다른 기기로 넘어가지 않아요. "
                '요금은 그 키의 계정에 청구돼요.',
                style: AppTextStyles.systemNotice,
              ),
              if (server != null && server.providers.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _ServerCard(server: server),
                if (server.needsAccessCode)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('고급 · 서버 접속 코드', style: AppTextStyles.speakerName),
                    childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _accessCode,
                              obscureText: true,
                              autocorrect: false,
                              decoration: const InputDecoration(hintText: '서버 .env의 ACCESS_CODE'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () async {
                              await notifier.saveAccessCode(_accessCode.text);
                              _toast('접속 코드를 저장했어요');
                            },
                            child: const Text('저장'),
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
              for (final p in AiProvider.values) ...[
                const SizedBox(height: AppSpacing.lg),
                _keyCard(p, notifier.peek(p), notifier),
              ],
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                key: const ValueKey('ai_keys_save'),
                onPressed: _saveKeys,
                child: const Text('저장'),
              ),
              const SizedBox(height: AppSpacing.lg),
              // 지금 모든 대화에 쓰는 AI (바꾸기는 대화방과 같은 고르기 창)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.aiActivePurple.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.forum_outlined, size: 20, color: AppColors.aiActivePurple),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '모든 대화 기본: ${current.modelOption?.label ?? '${current.provider.label.split(' ').first} · ${current.model}'}',
                            style: AppTextStyles.chatBubbleBody,
                          ),
                          const Text('쓸 AI와 모델은 대화방 위쪽에서 바로 골라요', style: AppTextStyles.messageTime),
                        ],
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('ai_default_change'),
                      onPressed: () => showChatAiSheet(context, accent: AppColors.primaryPink),
                      child: const Text('바꾸기'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 회사 하나: 이름 · 키 받으러 가기 · 저장된 키(지우기) · 새 키 칸
  Widget _keyCard(AiProvider p, ByokSettings saved, ByokSettingsNotifier notifier) {
    final name = p.label.split(' ').first;
    final viaServer = saved.server?.providers.contains(p) ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('$name 키', style: AppTextStyles.speakerName)),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => launchUrl(Uri.parse(aiKeyPage(p)), webOnlyWindowName: '_blank'),
              child: Text(p == AiProvider.gemini ? '무료로 키 받으러 가기 ›' : '키 받으러 가기 ›'),
            ),
          ],
        ),
        if (viaServer)
          const Text('서버 키로 불러서 내 키는 안 넣어도 돼요', style: AppTextStyles.messageTime),
        if (saved.hasKey)
          Row(
            children: [
              const Icon(Icons.vpn_key_rounded, size: 16, color: AppColors.aiActivePurple),
              const SizedBox(width: 6),
              Expanded(child: Text('저장된 키: ${saved.maskedKey}', style: AppTextStyles.messageTime)),
              TextButton(
                key: ValueKey('ai_key_remove_${p.name}'),
                onPressed: () async {
                  await notifier.removeKey(p);
                  setState(() {});
                  _toast('$name 키를 지웠어요');
                },
                child: const Text('지우기'),
              ),
            ],
          ),
        TextField(
          key: ValueKey('ai_key_${p.name}'),
          controller: _keys[p],
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            isDense: true,
            hintText: saved.hasKey ? '새 키로 바꾸려면 입력' : p.keyHint,
          ),
        ),
      ],
    );
  }
}

/// 말랑톡 서버에서 열었을 때 보이는 안내 (어느 회사 키가 서버에 있는지)
class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.server});

  final ServerInfo server;

  @override
  Widget build(BuildContext context) {
    final names = [
      for (final p in AiProvider.values)
        if (server.providers.contains(p)) p.label
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.aiActivePurple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.dns_rounded, size: 20, color: AppColors.aiActivePurple),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              names.isEmpty
                  ? '말랑톡 서버에서 열었어요. 서버 .env에 AI 키가 없어서 내 키를 써야 해요.'
                  : '말랑톡 서버에서 열었어요. ${names.join(', ')}는 서버 .env 키로 불러서 내 키가 없어도 돼요.',
              style: AppTextStyles.chatBubbleBody,
            ),
          ),
        ],
      ),
    );
  }
}

/// 앱을 빌드한 시각 (Dockerfile에서 --dart-define=BUILD_TIME으로 넣음, 개발 중에는 비어 있음)
const appBuild = String.fromEnvironment('BUILD_TIME');
