import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/mallang_mark.dart';

/// [초보자 노트] 처음 사용자 도움말. 말랑이가 말풍선으로 화면을 짧게 알려 줘요.
/// - 처음 켜면 인사 → 내 프로필 → AI 키 (welcome_screen.dart)
/// - 그다음은 화면에 처음 들어갈 때 한 번씩: 말랑이 찾기 → 대화 시작 창 → 대화방
/// - 만들기 화면은 '?' 버튼과 처음 한 번 뜨는 안내 고르기 (create_help.dart)
/// 본 안내는 계정에 연동돼서 PC에서 본 안내는 폰에서 다시 안 떠요. 설정 › 도움말 다시 보기로 다시 켤 수 있어요.
class HelpGuide {
  HelpGuide._();

  /// 화면에 처음 들어갈 때 안내를 저절로 띄울지 (테스트에서는 꺼 둠, test/flutter_test_config.dart)
  static bool autoShow = true;

  static const welcome = 'welcome';
  static const discover = 'discover';
  static const start = 'start';
  static const startService = 'start_service';
  static const room = 'room';
  static const roomFree = 'room_free';
  static const roomService = 'room_service';
  static const create = 'create';
  static const createAi = 'create_ai';
  static const createScript = 'create_script';
  static const createPhoto = 'create_photo';
  static const createService = 'create_service';

  /// 처음 안내 순서 (점 다섯 개): 프로필 · AI 키 · 말랑이 찾기 · 대화 시작 · 대화방
  static const tour = [welcome, discover, start, room];
  static const rooms = [room, roomFree, roomService];
}

/// 이미 본 안내 id 모음
class HelpSeenNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.watch(localStoreProvider).helpSeen.toSet();

  Future<void> mark(Iterable<String> ids) async {
    final next = {...state, ...ids};
    if (next.length == state.length) return;
    state = next;
    await ref.read(localStoreProvider).saveHelpSeen(next.toList());
  }

  Future<void> unmark(Iterable<String> ids) async {
    state = {...state}..removeAll(ids);
    await ref.read(localStoreProvider).saveHelpSeen(state.toList());
  }

  /// 모든 화면 안내를 처음처럼 다시 켜기
  Future<void> reset() async {
    state = {};
    await ref.read(localStoreProvider).saveHelpSeen(const []);
  }
}

final helpSeenProvider = NotifierProvider<HelpSeenNotifier, Set<String>>(HelpSeenNotifier.new);

/// 다른 화면에서 '이 안내를 지금 띄워 줘'라고 부탁할 때 (인사·프로필·키를 마치면 말랑이 찾기 안내)
final helpRequestProvider = StateProvider<String?>((ref) => null);

/// 이 안내를 지금 저절로 띄울지
bool shouldShowHelp(WidgetRef ref, String id) => HelpGuide.autoShow && !ref.read(helpSeenProvider).contains(id);

// ───────────────────────── 말랑이와 말풍선 ─────────────────────────

const _ink = Color(0xFF2B2326);
const _rose = Color(0xFFB83B66);

/// 동그란 분홍 바탕 위 말랑이 얼굴
class MallangFace extends StatelessWidget {
  const MallangFace({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: Color(0xFFF6E3EA), shape: BoxShape.circle),
        child: MallangMark(size: size * 0.72, color: Colors.white, eyeColor: _ink),
      );
}

/// '**굵게**'를 분홍 굵은 글씨로 바꿔 보여 주는 글
class HelpText extends StatelessWidget {
  const HelpText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? const TextStyle(fontSize: 14, height: 1.6, color: _ink);
    final parts = text.split('**');
    return Text.rich(TextSpan(style: base, children: [
      for (var i = 0; i < parts.length; i++)
        TextSpan(
          text: parts[i],
          style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700, color: _rose) : null,
        ),
    ]));
  }
}

/// 말랑이가 말풍선으로 하는 말
class MallangSays extends StatelessWidget {
  const MallangSays(this.text, {super.key, this.size = 48});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          MallangFace(size: size),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.surfaceWhite,
                border: Border.all(color: const Color(0xFFEEE3E7)),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4),
                ),
              ),
              child: HelpText(text, style: const TextStyle(fontSize: 14.5, height: 1.55, color: _ink)),
            ),
          ),
        ],
      );
}

/// 번호 붙은 안내 한 줄
class HelpLine extends StatelessWidget {
  const HelpLine(this.number, this.text, {super.key, this.tag});

  final int? number;
  final String text;

  /// 번호 대신 앞에 붙는 꼬리표 (예: 스토리)
  final String? tag;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tag != null)
              Container(
                margin: const EdgeInsets.only(top: 1, right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFFF6E3EA), borderRadius: BorderRadius.circular(999)),
                child: Text(tag!,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF8E2E52))),
              )
            else if (number != null) ...[
              HelpPin(number!, size: 20),
              const SizedBox(width: 8),
            ],
            Expanded(child: HelpText(text, style: const TextStyle(fontSize: 13, height: 1.55, color: _ink))),
          ],
        ),
      );
}

/// 동그란 번호표
class HelpPin extends StatelessWidget {
  const HelpPin(this.number, {super.key, this.size = 24});

  final int number;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFC2416C),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: size > 22 ? 2 : 0),
        ),
        child:
            Text('$number', style: TextStyle(color: Colors.white, fontSize: size * 0.5, fontWeight: FontWeight.w700)),
      );
}

/// 처음 안내 다섯 단계 중 어디인지 보여 주는 점
class HelpDots extends StatelessWidget {
  const HelpDots(this.index, {super.key, this.count = 5});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$count단계 중 ${index + 1}단계',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                margin: const EdgeInsets.only(right: 4),
                width: i == index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == index ? _rose : const Color(0xFFE5D6DC),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      );
}

// ───────────────────────── 화면 위 안내 (어둡게 + 동그라미) ─────────────────────────

/// 안내 한 줄. [target]이 있으면 화면에서 그 자리를 밝게 비우고 같은 번호를 붙여요.
class CoachItem {
  const CoachItem(this.text, {this.target});

  final String text;
  final GlobalKey? target;
}

/// 화면을 어둡게 덮고 [targets] 자리만 밝게 비운 뒤, 말랑이 말풍선 카드로 설명해요.
/// [tourIndex]가 있으면 처음 안내 점(5개 중 몇 번째)과 '건너뛰기'를 보여 줘요.
/// [neverAgain]이면 '다시 보지 않기' 칸이 생겨요 (끄면 다음에 또 떠요).
/// 돌려주는 값: 'done'(다 봤어요), 'skip'(건너뛰기), 'extra'(추가 버튼), 'again'(다시 보지 않기를 끔)
Future<String?> showCoach(
  BuildContext context, {
  required String say,
  String? title,
  List<CoachItem> items = const [],
  List<GlobalKey> highlight = const [],
  int? tourIndex,
  bool neverAgain = false,
  String doneLabel = '다음',
  String? extraLabel,
  IconData? extraIcon,
}) {
  return Navigator.of(context, rootNavigator: true).push<String>(PageRouteBuilder(
    opaque: false,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (context, animation, _) => FadeTransition(
      opacity: animation,
      child: _CoachPage(
        say: say,
        title: title,
        items: items,
        highlight: highlight,
        tourIndex: tourIndex,
        neverAgain: neverAgain,
        doneLabel: doneLabel,
        extraLabel: extraLabel,
        extraIcon: extraIcon,
      ),
    ),
  ));
}

class _CoachPage extends StatefulWidget {
  const _CoachPage({
    required this.say,
    required this.title,
    required this.items,
    required this.highlight,
    required this.tourIndex,
    required this.neverAgain,
    required this.doneLabel,
    required this.extraLabel,
    required this.extraIcon,
  });

  final String say;
  final String? title;
  final List<CoachItem> items;
  final List<GlobalKey> highlight;
  final int? tourIndex;
  final bool neverAgain;
  final String doneLabel;
  final String? extraLabel;
  final IconData? extraIcon;

  @override
  State<_CoachPage> createState() => _CoachPageState();
}

class _CoachPageState extends State<_CoachPage> {
  bool _never = true;

  /// 화면에 보이는 자리만 (안 그려졌거나 크기가 0이면 뺌)
  static Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize || box.size.isEmpty) return null;
    return (box.localToGlobal(Offset.zero) & box.size).inflate(5);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final screen = Offset.zero & size;
    final holes = <Rect>[
      for (final k in widget.highlight)
        if (_rectOf(k) case final r?) r,
    ];
    final pins = <(int, Rect)>[
      for (var i = 0; i < widget.items.length; i++)
        if (widget.items[i].target case final key?)
          if (_rectOf(key) case final r?) (i + 1, r),
    ];
    final all = [...holes, for (final p in pins) p.$2].where((r) => r.overlaps(screen)).toList();
    // 비운 자리가 위쪽이면 카드는 그 아래, 아래쪽이면 그 위
    double? top;
    double? bottom;
    if (all.isNotEmpty) {
      final union = all.reduce((a, b) => a.expandToInclude(b));
      if (union.bottom < size.height * 0.45) {
        top = union.bottom + 16;
      } else if (union.center.dy < size.height / 2) {
        // 아래에 자리가 모자라면 화면 맨 아래에 (비운 자리 아래쪽이 조금 가려도 위쪽은 보이게)
        bottom = 16 + MediaQuery.paddingOf(context).bottom;
      } else {
        bottom = (size.height - union.top + 16).clamp(16, size.height * 0.55);
      }
    }
    final pad = MediaQuery.paddingOf(context);
    final card = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 520, maxHeight: size.height * 0.62),
      child: Material(
        key: const ValueKey('help_coach'),
        color: AppColors.surfaceWhite,
        elevation: 3,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(20),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.title != null) ...[
                Row(children: [
                  const MallangFace(size: 44),
                  const SizedBox(width: 10),
                  Expanded(
                      child:
                          Text(widget.title!, style: AppTextStyles.choiceButton.copyWith(color: _ink, fontSize: 15))),
                ]),
                const SizedBox(height: 6),
                HelpText(widget.say, style: const TextStyle(fontSize: 13.5, height: 1.55, color: _ink)),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MallangFace(size: 48),
                    const SizedBox(width: 10),
                    Expanded(child: HelpText(widget.say)),
                  ],
                ),
              for (var i = 0; i < widget.items.length; i++) HelpLine(i + 1, widget.items[i].text),
              if (widget.extraLabel != null) ...[
                const SizedBox(height: 10),
                Material(
                  color: const Color(0xFFF7EEF2),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    key: const ValueKey('help_coach_extra'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(context, 'extra'),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(children: [
                          Icon(widget.extraIcon ?? Icons.add_rounded, size: 20, color: _rose),
                          const SizedBox(width: 10),
                          Expanded(child: Text(widget.extraLabel!, style: const TextStyle(fontSize: 13, color: _ink))),
                          const Icon(Icons.chevron_right_rounded, size: 18),
                        ]),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  if (widget.tourIndex != null) HelpDots(widget.tourIndex!),
                  const Spacer(),
                  if (widget.neverAgain)
                    InkWell(
                      key: const ValueKey('help_never_again'),
                      onTap: () => setState(() => _never = !_never),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Checkbox(
                            value: _never,
                            visualDensity: VisualDensity.compact,
                            activeColor: _rose,
                            onChanged: (v) => setState(() => _never = v ?? true),
                          ),
                          const Text('다시 보지 않기', style: TextStyle(fontSize: 13, color: Color(0xFF4A3D42))),
                        ]),
                      ),
                    )
                  else if (widget.tourIndex != null)
                    TextButton(
                      key: const ValueKey('help_skip'),
                      onPressed: () => Navigator.pop(context, 'skip'),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFF5E4E54)),
                      child: const Text('건너뛰기'),
                    ),
                  const SizedBox(width: 6),
                  FilledButton(
                    key: const ValueKey('help_done'),
                    style: FilledButton.styleFrom(backgroundColor: _rose, minimumSize: const Size(0, 44)),
                    onPressed: () => Navigator.pop(context, widget.neverAgain && !_never ? 'again' : 'done'),
                    child: Text(widget.doneLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _HolePainter([...holes, for (final p in pins) p.$2])),
          ),
          for (final (n, r) in pins)
            Positioned(
              left: (r.right - 14).clamp(2, size.width - 26),
              top: (r.top - 10).clamp(2, size.height - 26),
              child: HelpPin(n),
            ),
          Positioned(
            left: 14,
            right: 14,
            top: top,
            bottom: top == null ? (bottom ?? 24 + pad.bottom) : null,
            child: SafeArea(top: top == null, bottom: false, child: Center(child: card)),
          ),
        ],
      ),
    );
  }
}

class _HolePainter extends CustomPainter {
  _HolePainter(this.holes);

  final List<Rect> holes;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()..addRect(Offset.zero & size);
    final cut = Path();
    for (final r in holes) {
      cut.addRRect(RRect.fromRectAndRadius(r, const Radius.circular(14)));
    }
    canvas.drawPath(Path.combine(PathOperation.difference, dim, cut), Paint()..color = const Color(0x99201419));
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppColors.primaryPink;
    for (final r in holes) {
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(14)), ring);
    }
  }

  @override
  bool shouldRepaint(_HolePainter old) => old.holes != holes;
}
