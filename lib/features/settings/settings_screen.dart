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
          constraints: const BoxConstraints(maxWidth: AppSpacing.mobileMaxWidth),
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
          constraints: const BoxConstraints(maxWidth: AppSpacing.mobileMaxWidth),
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
                '캐릭터와 대화를 처음 시작할 때 이 별명이 기본으로 들어가요. 말랑이를 공개하면 만든 사람 이름으로도 보여요.',
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
  static const _custom = '__custom__';
  final _keyController = TextEditingController();
  late AiProvider _provider = ref.read(byokSettingsProvider).provider;
  late String _model = _modelChoiceOf(ref.read(byokSettingsProvider));
  late final _customModel = TextEditingController(
    text: _model == _custom ? ref.read(byokSettingsProvider).model : '',
  );

  /// 드롭다운에 보일 값: 목록에 있는 모델이면 그 id, 직접 입력한 모델이면 '직접 입력'
  String _modelChoiceOf(ByokSettings s) => s.modelOption != null ? s.model : _custom;

  void _pickProvider(AiProvider provider) {
    final saved = ref.read(byokSettingsProvider.notifier).peek(provider);
    setState(() {
      _provider = provider;
      _model = _modelChoiceOf(saved);
      _customModel.text = _model == _custom ? saved.model : '';
      _keyController.clear();
    });
  }

  final _accessCode = TextEditingController();

  @override
  void initState() {
    super.initState();
    _accessCode.text = ref.read(byokSettingsProvider).accessCode ?? '';
  }

  @override
  void dispose() {
    _keyController.dispose();
    _customModel.dispose();
    _accessCode.dispose();
    super.dispose();
  }

  /// AI 회사별 API 키 발급 페이지
  static String _keyPage(AiProvider provider) => switch (provider) {
        AiProvider.gemini => 'https://aistudio.google.com/apikey',
        AiProvider.claude => 'https://console.anthropic.com/settings/keys',
        AiProvider.openai => 'https://platform.openai.com/api-keys',
      };

  static String _usd(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(byokSettingsProvider);
    final notifier = ref.read(byokSettingsProvider.notifier);
    // 지금 드롭다운에서 고른 회사에 저장해 둔 키 (아직 저장 전이면 다른 회사 키일 수 있음)
    final settings = notifier.peek(_provider);
    final server = settings.server;

    return Scaffold(
      appBar: AppBar(title: const Text('AI 연결')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.mobileMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(server != null && server.providers.isNotEmpty ? 'AI 설정' : '내 AI 키',
                  style: AppTextStyles.appBarTitle),
              const SizedBox(height: 6),
              const Text(
                '대화방 자유대화와 말랑이 만들기의 AI로 만들기에서 여기서 고른 AI를 불러요. '
                '요금은 그 키의 계정에 청구돼요. 내 키는 이 브라우저에만 저장돼요.',
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
              const SizedBox(height: AppSpacing.lg),
              const Text('AI 회사', style: AppTextStyles.speakerName),
              const SizedBox(height: 4),
              DropdownButtonFormField<AiProvider>(
                key: ValueKey('provider_${_provider.name}'),
                initialValue: _provider,
                isExpanded: true,
                items: [
                  for (final p in AiProvider.values) DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                onChanged: (p) {
                  if (p != null && p != _provider) _pickProvider(p);
                },
              ),
              const SizedBox(height: 4),
              Text(
                settings.usesServer ? '서버 키로 불러요. 내 키는 넣지 않아도 돼요.' : _provider.keyNote,
                style: AppTextStyles.messageTime,
              ),
              if (!settings.usesServer)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: Text('${_provider.label.split(' ').first} 키 받으러 가기'),
                    onPressed: () => launchUrl(Uri.parse(_keyPage(_provider)), webOnlyWindowName: '_blank'),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              Text(settings.usesServer ? 'API 키 (안 넣어도 됨)' : 'API 키', style: AppTextStyles.speakerName),
              const SizedBox(height: 4),
              if (settings.hasKey) ...[
                Row(
                  children: [
                    const Icon(Icons.vpn_key_rounded, size: 18, color: AppColors.aiActivePurple),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('저장된 키: ${settings.maskedKey}', style: AppTextStyles.chatBubbleBody),
                    ),
                    TextButton(
                      onPressed: () async {
                        await notifier.removeKey(_provider);
                        setState(() {});
                        _toast('키를 지웠어요');
                      },
                      child: const Text('지우기'),
                    ),
                  ],
                ),
              ],
              TextField(
                controller: _keyController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: settings.hasKey ? '새 키로 바꾸려면 입력' : _provider.keyHint,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('모델', style: AppTextStyles.speakerName),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                key: ValueKey('model_${_provider.name}'),
                initialValue: _model,
                isExpanded: true,
                items: [
                  for (final m in _provider.models)
                    DropdownMenuItem(
                      value: m.id,
                      child: Text('${m.label} · ${m.note}', overflow: TextOverflow.ellipsis),
                    ),
                  const DropdownMenuItem(value: _custom, child: Text('직접 입력')),
                ],
                onChanged: (id) {
                  if (id != null) setState(() => _model = id);
                },
              ),
              if (_model == _custom) ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _customModel,
                  autocorrect: false,
                  decoration: const InputDecoration(hintText: '모델 이름 그대로 (예: 새로 나온 모델)'),
                ),
              ],
              if (_provider.option(_model) case final m?) ...[
                const SizedBox(height: 4),
                Text(
                  '요금: 입력 100만 토큰당 \$${_usd(m.inputUsdPerMTok)}, 출력 \$${_usd(m.outputUsdPerMTok)} (2026년 10월 기준)',
                  style: AppTextStyles.messageTime,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: () async {
                  final key = _keyController.text.trim().isNotEmpty ? _keyController.text.trim() : settings.apiKey;
                  if ((key == null || key.isEmpty) && !settings.usesServer) {
                    _toast('API 키를 입력해 주세요');
                    return;
                  }
                  final model = _model == _custom ? _customModel.text.trim() : _model;
                  if (model.isEmpty) {
                    _toast('모델 이름을 적어 주세요');
                    return;
                  }
                  await notifier.save(provider: _provider, apiKey: key ?? '', model: model);
                  _keyController.clear();
                  _toast('${_provider.label}로 저장했어요');
                },
                child: const Text('저장'),
              ),
            ],
          ),
        ),
      ),
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
