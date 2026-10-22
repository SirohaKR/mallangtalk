import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/claude_chat_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import 'byok_settings.dart';
import 'chat_tempo.dart';

/// [초보자 노트] 내 Claude API 키(BYOK)를 넣고 자유대화에 쓸 모델을 고르는 설정 화면입니다.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _keyController = TextEditingController();
  late String _model = ref.read(byokSettingsProvider).model;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(byokSettingsProvider);
    final notifier = ref.read(byokSettingsProvider.notifier);
    final tempo = ref.watch(chatTempoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.mobileMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const Text('내 AI 키', style: AppTextStyles.appBarTitle),
              const SizedBox(height: 6),
              const Text(
                '채팅방 자유대화와 캐릭터 추가 > 만들기 > AI로 만들기에서 이 키로 Claude를 불러요. '
                '요금은 이 키의 계정에 청구돼요. 키는 이 브라우저에만 저장돼요.',
                style: AppTextStyles.systemNotice,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (settings.hasKey) ...[
                Row(
                  children: [
                    const Icon(Icons.vpn_key_rounded, size: 18, color: AppColors.aiActivePurple),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('저장된 키: ${settings.maskedKey}',
                          style: AppTextStyles.chatBubbleBody),
                    ),
                    TextButton(
                      onPressed: () async {
                        await notifier.removeKey();
                        _toast('키를 지웠어요');
                      },
                      child: const Text('지우기'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              TextField(
                controller: _keyController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: settings.hasKey ? '새 키로 바꾸려면 입력' : 'sk-ant-로 시작하는 Claude API 키',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('모델', style: AppTextStyles.speakerName),
              const SizedBox(height: 4),
              // 구버전 Flutter에서도 돌도록 Radio 대신 체크 아이콘 목록으로 고름
              for (final option in ClaudeModelOption.all)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => setState(() => _model = option.id),
                  leading: Icon(
                    _model == option.id
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: _model == option.id
                        ? AppColors.aiActivePurple
                        : AppColors.textMuted,
                  ),
                  title: Text(option.label),
                  subtitle: Text(option.note, style: AppTextStyles.systemNotice),
                ),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: () async {
                  final key = _keyController.text.trim().isNotEmpty
                      ? _keyController.text.trim()
                      : settings.apiKey;
                  if (key == null || key.isEmpty) {
                    _toast('API 키를 입력해 주세요');
                    return;
                  }
                  await notifier.save(apiKey: key, model: _model);
                  _keyController.clear();
                  _toast('저장했어요');
                },
                child: const Text('저장'),
              ),
              const SizedBox(height: AppSpacing.xl),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              const Text('대화 속도', style: AppTextStyles.appBarTitle),
              const SizedBox(height: 6),
              const Text(
                '캐릭터의 "입력 중" 시간에 곱해져요. 캐릭터마다 성격에 맞는 타자 속도는 따로 있어요.',
                style: AppTextStyles.systemNotice,
              ),
              for (final option in ChatTempoOption.all)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => ref.read(chatTempoProvider.notifier).set(option.tempo),
                  leading: Icon(
                    tempo == option.tempo
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: tempo == option.tempo ? AppColors.primaryPink : AppColors.textMuted,
                  ),
                  title: Text(option.label),
                  subtitle: Text(option.note, style: AppTextStyles.systemNotice),
                ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                '대화를 처음부터 다시 하려면 내 캐릭터 → 프로필 → 처음부터',
                style: AppTextStyles.messageTime,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
