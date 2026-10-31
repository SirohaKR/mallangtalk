import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/widgets/character_avatar.dart';

/// 채팅창에 쳐서 쓰는 명령어 (자유대화·서비스 방)
class ChatCommand {
  const ChatCommand(this.name, this.label);

  /// '/' 빼고 (예: 구분선)
  final String name;
  final String label;

  static const divider = ChatCommand('구분선', '대화 끝 구분선 넣기');
  static const clear = ChatCommand('비우기', '대화 비우기');

  /// 이 방에서 쓸 수 있는 명령어
  static List<ChatCommand> forRoom({required bool free, required bool service}) => [
        if (free) divider,
        if (free || service) clear,
      ];

  /// 입력 글이 명령어면 그 명령어, '/'로 시작하지만 모르는 말이면 [unknown], 명령어가 아니면 null
  static ChatCommand? parse(String text, List<ChatCommand> commands) {
    final t = text.trim();
    if (!t.startsWith('/')) return null;
    final name = t.substring(1).trim();
    return commands.where((c) => c.name == name).firstOrNull ?? unknown;
  }

  static const unknown = ChatCommand('', '');
}

/// 대화방 오른쪽 위 메뉴를 누르면 옆에서 나오는 사이드바.
/// 내 정보 / 대화 설정 / 로어북을 고르면 팝업으로 설정 화면이 뜸
class ChatSideMenu extends StatelessWidget {
  const ChatSideMenu({
    super.key,
    required this.character,
    required this.accent,
    required this.nickname,
    required this.memoryCount,
    required this.showLorebook,
    required this.commands,
    required this.storyRoom,
    required this.onSelected,
  });

  final CharacterModel character;
  final Color accent;
  final String nickname;
  final int memoryCount;

  /// AI가 답하는 방에서만 로어북(기억)이 쌓임
  final bool showLorebook;
  final List<ChatCommand> commands;

  /// 스토리 방: 입력칸이 잠겨 있어서 명령어 대신 메뉴에 둠
  final bool storyRoom;

  /// 'profile' / 'settings' / 'lorebook' / 'switch' / 'restart'
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    Widget item(String value, IconData icon, String title, String subtitle) => ListTile(
          key: ValueKey('side_$value'),
          leading: Icon(icon, color: accent),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle, style: AppTextStyles.messageTime, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          onTap: () {
            Navigator.pop(context);
            onSelected(value);
          },
        );
    return Drawer(
      // 화면 반쯤 (폰에선 너무 좁지 않게)
      width: (width * 0.5).clamp(280.0, 420.0).clamp(0.0, width * 0.88),
      backgroundColor: AppColors.surfaceWhite,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  CharacterAvatar(character: character, radius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(character.name,
                        style: AppTextStyles.appBarTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderLight),
            item('profile', Icons.person_outline_rounded, '내 정보',
                '${character.isService ? '별명·정보' : '별명·설정'}: $nickname'),
            item('settings', Icons.tune_rounded, '대화 설정',
                [
                  '대화 속도',
                  if (!storyRoom && !character.isService) '로맨스 분위기',
                  'AI 모델',
                ].join(' · ')),
            if (showLorebook)
              item('lorebook', Icons.auto_stories_outlined, '로어북', '대화 요약 $memoryCount개 · 보고 고치기'),
            if (storyRoom) ...[
              const Divider(height: 24, color: AppColors.borderLight),
              item('switch', Icons.forum_outlined, '자유대화 방 열기', '정해진 이야기 없이 AI와 자유롭게'),
              item('restart', Icons.restart_alt_rounded, '처음부터 다시', '이 이야기를 처음부터'),
            ],
            if (commands.isNotEmpty) ...[
              const Divider(height: 24, color: AppColors.borderLight),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text('채팅창 명령어', style: AppTextStyles.speakerName),
              ),
              for (final c in commands)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '/${c.name}  ', style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
                    TextSpan(text: c.label, style: AppTextStyles.messageTime),
                  ])),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 사이드바 '대화 설정' 팝업: 고른 항목 ('tempo' / 'romance' / 'ai')을 돌려줌
Future<String?> showChatSettingsDialog(
  BuildContext context, {
  required Color accent,
  required bool romance,
  required bool ai,
}) =>
    showDialog<String>(
      context: context,
      builder: (context) {
        Widget row(String value, IconData icon, String title, String subtitle) => ListTile(
              key: ValueKey('settings_$value'),
              leading: Icon(icon, color: accent),
              title: Text(title),
              subtitle: Text(subtitle, style: AppTextStyles.messageTime),
              onTap: () => Navigator.pop(context, value),
            );
        return SimpleDialog(
          title: const Text('대화 설정'),
          children: [
            row('tempo', Icons.speed_rounded, '대화 속도', '답장이 오는 빠르기'),
            if (romance) row('romance', Icons.favorite_border_rounded, '로맨스 분위기', '기본 · 진한 로맨스 · 집착 서사'),
            if (ai) row('ai', Icons.smart_toy_outlined, 'AI 모델', '이 대화에 쓰는 AI 고르기'),
          ],
        );
      },
    );
