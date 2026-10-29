import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../settings/byok_settings.dart';
import 'help_guide.dart';

/// 만들기 안내 하나: 고르기 창의 줄 + 열었을 때 보여 줄 번호 줄
class _CreateGuide {
  const _CreateGuide(this.id, this.icon, this.title, this.note, this.say, this.lines);

  final String id;
  final IconData icon;
  final String title;
  final String note;
  final String say;
  final List<String> lines;
}

/// 지금 만들기 화면 기준 안내 (이야기 말랑이 9단계, 서비스 말랑이 4단계)
const _guides = [
  _CreateGuide(
    HelpGuide.createAi,
    Icons.auto_awesome_rounded,
    'AI로 한 번에 만들기',
    '설정만 쓰면 대화·대사를 AI가 써 줘요',
    '설정만 잘 써 두면 대화랑 대사는 AI가 써 줘. 순서는 이래!',
    [
      '**1~6단계**에서 이름·대표색·프로필·성격·말투·이야기·주변 인물을 써. 막히면 단계 위 **빈 칸 AI로 채우기**가 비어 있는 칸만 채워 줘',
      "**7단계 호감도·대본**에서 **AI로 생성하기**를 누르고 빈 대화만 / 전부 새로 / 골라서, 쓸 AI를 골라. 시작 전에 예상 비용도 보여 줘",
      "다 써지면 대화를 눌러 **대사 편집**에서 마음에 안 드는 대사만 고쳐. **AI로 대사 쓰기**는 그 대화만 다시 써",
      '**8단계 사진함**에 사진을 올리고, **9단계 공개**에서 작가 코멘트와 말랑이 찾기에 올릴지 정한 뒤 저장해',
    ],
  ),
  _CreateGuide(
    HelpGuide.createScript,
    Icons.edit_note_rounded,
    '대화·대사 직접 쓰기',
    '대화 종류, 말풍선, 선택지와 호감도',
    '대본은 대화 하나씩 써. 대화 하나가 톡 한 번이야!',
    [
      '**7단계**에서 대화를 더하고 종류를 골라. **호감도 이벤트**는 단계마다 순서대로 오고 다 끝내면 **엔딩**, **일상 대화**는 그 단계에서 랜덤, **특별 이벤트**는 정한 실제 시간에, **공략 후 이야기**는 엔딩 뒤에 와',
      "**대사 편집**에서 장면마다 **말풍선 추가**로 캐릭터 대사를 써. 대사에 {이름}이라고 쓰면 유저 별명으로 바뀌어",
      '**선택지 추가**로 내 답을 넣고, 답마다 호감도와 이어질 장면을 정해. 선택지가 없으면 그 장면에서 대화가 끝나',
      "**장면 추가**로 다음 장면을 이어 붙여. 대화 위 **장면 전환 문구**에 '다음 날'처럼 쓰면 잠깐 쉬었다가 넘어가",
    ],
  ),
  _CreateGuide(
    HelpGuide.createPhoto,
    Icons.photo_library_outlined,
    '사진 등록하기',
    '사진함에 올리고 대본에 붙이기',
    '사진은 **사진함**에 모아 두고 대본에서 골라 써!',
    [
      '**8단계 사진함**에서 **새로 올리기**를 누르고 자르기 화면에서 비율을 맞춰. 셀카나 누가 찍어 준 사진 느낌이 좋아',
      '사진마다 **설명**을 써 둬. 대본의 사진 말풍선·컷씬 설명이 같으면 저장할 때 알아서 붙고, 못 붙인 곳은 저장할 때 알려 줘',
      "자유대화에서도 보내려면 **자유대화에도**로 바꾸고 보낼 때(감정·상황·키워드)를 골라. 대화가 맞을 때만 AI가 보내",
      '유저가 받은 사진은 전부 **앨범**에 모여',
    ],
  ),
  _CreateGuide(
    HelpGuide.createService,
    Icons.notifications_active_outlined,
    '서비스 말랑이 만들기',
    '운세·알림처럼 정해진 때 먼저 톡 보내기',
    '서비스 말랑이는 정해진 때마다 **먼저 톡**을 보내. 호감도 없이 처음부터 친한 사이야!',
    [
      "만들기 첫 화면에서 **서비스 말랑이**를 골라. 기본 · 대표색 · 보내기 · 공개 4단계야",
      '**보내기** 단계에서 요일·시간과 문구 만드는 법(목록 / 데이터 표 / AI)을 정해. 표는 CSV 파일로도 불러와',
      '**물어볼 내 정보**(띠·생일 등)를 고르면 대화를 시작할 때 유저가 적고, 문구의 {칸}에 들어가',
      '유저가 답장하면 **읽씹 / 정해 둔 답 / AI** 중 정한 대로 답해',
    ],
  ),
];

/// 만들기 안내 고르기 창 (만들기 화면 '?' 버튼, 처음 만들기 화면에 들어갈 때 한 번)
Future<void> showCreateHelp(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  container.read(helpSeenProvider.notifier).mark(const [HelpGuide.create]);
  while (context.mounted) {
    final picked = await showModalBottomSheet<_CreateGuide>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceWhite,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => const _CreateHelpSheet(),
    );
    if (picked == null || !context.mounted) return;
    container.read(helpSeenProvider.notifier).mark([picked.id]);
    final noKey = picked.id == HelpGuide.createAi && !container.read(byokSettingsProvider).canUseAi;
    final result = await showDialog<String>(
      context: context,
      builder: (c) => _GuideDialog(guide: picked, offerKey: noKey),
    );
    if (result == 'key' && context.mounted) {
      await context.push('/settings/ai');
      return;
    }
    if (result != 'back') return;
  }
}

class _CreateHelpSheet extends ConsumerWidget {
  const _CreateHelpSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(helpSeenProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          key: const ValueKey('create_help_sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            const MallangSays('내 말랑이를 만들어 볼 거야? 궁금한 것만 골라 봐, 짧게 알려 줄게!'),
            const SizedBox(height: 14),
            for (final g in _guides)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: AppColors.surfaceWhite,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFEEE3E7)),
                  ),
                  child: InkWell(
                    key: ValueKey('help_pick_${g.id}'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(context, g),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration:
                              BoxDecoration(color: const Color(0xFFF6E3EA), borderRadius: BorderRadius.circular(12)),
                          child: Icon(g.icon, color: const Color(0xFFB83B66), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(g.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(g.note, style: AppTextStyles.messageTime),
                          ]),
                        ),
                        if (seen.contains(g.id))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration:
                                BoxDecoration(color: const Color(0xFFE3F1E7), borderRadius: BorderRadius.circular(999)),
                            child: const Text('봤어요',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF22603A))),
                          ),
                      ]),
                    ),
                  ),
                ),
              ),
            TextButton(
              key: const ValueKey('create_help_close'),
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF5E4E54), minimumSize: const Size(0, 44)),
              child: const Text('괜찮아요, 바로 만들게요'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideDialog extends StatelessWidget {
  const _GuideDialog({required this.guide, required this.offerKey});

  final _CreateGuide guide;
  final bool offerKey;

  @override
  Widget build(BuildContext context) => Dialog(
        key: ValueKey('help_guide_${guide.id}'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.surfaceWhite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const MallangFace(size: 48),
                  const SizedBox(width: 10),
                  Expanded(child: HelpText(guide.say)),
                ]),
                for (var i = 0; i < guide.lines.length; i++) HelpLine(i + 1, guide.lines[i]),
                if (offerKey) ...[
                  const SizedBox(height: 10),
                  const Text('AI는 내 AI 키로 써요. 키가 없으면 여기서 바로 연결할 수 있어요', style: AppTextStyles.messageTime),
                ],
                const SizedBox(height: 6),
                Row(children: [
                  TextButton(
                    key: const ValueKey('help_guide_back'),
                    onPressed: () => Navigator.pop(context, 'back'),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF5E4E54)),
                    child: const Text('← 다른 안내'),
                  ),
                  const Spacer(),
                  if (offerKey)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: OutlinedButton(
                        key: const ValueKey('help_guide_key'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                        onPressed: () => Navigator.pop(context, 'key'),
                        child: const Text('키 연결하기'),
                      ),
                    ),
                  FilledButton(
                    key: const ValueKey('help_guide_ok'),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB83B66), minimumSize: const Size(0, 44)),
                    onPressed: () => Navigator.pop(context, 'ok'),
                    child: const Text('알겠어'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      );
}
