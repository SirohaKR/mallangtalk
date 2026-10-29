import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'create_help.dart';
import 'help_guide.dart';

/// 설정 › 도움말 다시 보기: 어떤 안내를 다시 볼지 고르는 창
Future<void> showHelpAgain(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  final seen = container.read(helpSeenProvider.notifier);
  final picked = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surfaceWhite,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (c) {
      Widget pick(String value, IconData icon, String title, String note) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: AppColors.surfaceWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFEEE3E7)),
              ),
              child: InkWell(
                key: ValueKey('help_again_$value'),
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.pop(c, value),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration:
                          BoxDecoration(color: const Color(0xFFF6E3EA), borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, color: const Color(0xFFB83B66), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(note, style: AppTextStyles.messageTime),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('어떤 안내를 다시 볼까?', style: AppTextStyles.appBarTitle),
              const SizedBox(height: 12),
              pick('tour', Icons.waving_hand_outlined, '처음 안내', '프로필 · AI 키 · 말랑이 찾기 · 대화 시작 · 대화방'),
              pick('room', Icons.chat_bubble_outline_rounded, '대화방 안내', '호감도 말랑이 · 사진 · 선택지 · 메뉴'),
              pick('create', Icons.auto_awesome_rounded, '말랑이 만들기 안내', 'AI로 만들기 · 대화·대사 쓰기 · 사진 등록 · 서비스 말랑이'),
              pick('reset', Icons.restart_alt_rounded, '화면 안내 다시 켜기', '각 화면에 처음 들어갈 때처럼 다시 떠요'),
            ],
          ),
        ),
      );
    },
  );
  if (picked == null || !context.mounted) return;
  void toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  switch (picked) {
    case 'tour':
      await seen.unmark(HelpGuide.tour);
      await seen.unmark(HelpGuide.rooms);
      if (context.mounted) context.push('/welcome');
    case 'room':
      await seen.unmark(HelpGuide.rooms);
      toast('다음에 대화방에 들어가면 안내가 다시 떠요');
    case 'create':
      await showCreateHelp(context);
    case 'reset':
      await seen.reset();
      toast('화면 안내를 다시 켰어요. 화면에 처음 들어갈 때처럼 떠요');
  }
}
