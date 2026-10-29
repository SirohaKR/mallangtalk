import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../utils/file_io.dart';
import 'character_avatar.dart';

/// 크게 보기에서 보여 줄 사진 한 장
class PhotoViewerItem {
  const PhotoViewerItem({required this.label, this.image, this.chip, this.caption, this.onGoTo});

  /// 사진 설명 (진짜 사진이 없으면 이 글을 카드로 보여 줌)
  final String label;
  final String? image;

  /// 위에 작게 붙는 이름표 (예: 호감도 단계 이름)
  final String? chip;

  /// 맨 아래 작은 글 (예: 10월 26일 밤 11:43에 받음 · 카이엔)
  final String? caption;

  /// '이 톡으로 가기': 크게 보기를 닫고 이 사진이 온 톡으로 (없으면 버튼 안 보임)
  final VoidCallback? onGoTo;
}

/// [초보자 노트] 사진 크게 보기 화면 (대화방·앨범이 같이 써요).
/// 뒤는 같은 사진을 흐리고 어둡게 깔아서 사진이 떠 보이게 하고,
/// 옆으로 밀면 다음 사진, 두 손가락으로 확대할 수 있어요.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({
    super.key,
    required this.items,
    this.initialIndex = 0,
    required this.onClose,
    this.accent = AppColors.primaryPink,
  });

  final List<PhotoViewerItem> items;
  final int initialIndex;
  final VoidCallback onClose;
  final Color accent;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late int _index = widget.initialIndex.clamp(0, widget.items.length - 1);
  late final PageController _pages = PageController(initialPage: _index);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int index) => _pages.animateToPage(index,
      duration: const Duration(milliseconds: 240), curve: Curves.easeOut);

  bool _saving = false;

  Future<void> _save(PhotoViewerItem item) async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await FileIO.savePhoto(item.image ?? '', item.label);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(ok ? '사진을 저장했어요' : '사진을 저장하지 못했어요')));
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    final photo = CharacterImage.providerFor(item.image ?? '');
    final many = widget.items.length > 1;
    return Material(
      key: const ValueKey('photo_viewer'),
      color: const Color(0xFF0E0D12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 뒤에 깔리는 흐린 사진
          if (photo != null)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.55), BlendMode.darken),
                child: Image(image: photo, fit: BoxFit.cover),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                // 위: 닫기 + 몇 번째 사진
                SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      const SizedBox(width: 6),
                      _RoundButton(icon: Icons.close_rounded, tooltip: '닫기', onTap: widget.onClose),
                      const Spacer(),
                      if (many)
                        Text('${_index + 1} / ${widget.items.length}',
                            style: AppTextStyles.choiceButton.copyWith(color: Colors.white)),
                      const SizedBox(width: 18),
                    ],
                  ),
                ),
                // 가운데: 사진 (옆으로 넘기기)
                Expanded(
                  child: Stack(
                    children: [
                      PageView.builder(
                        controller: _pages,
                        itemCount: widget.items.length,
                        onPageChanged: (i) => setState(() => _index = i),
                        itemBuilder: (context, i) => _PhotoPage(item: widget.items[i], accent: widget.accent),
                      ),
                      if (many && _index > 0)
                        Positioned(
                          left: 8,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: _RoundButton(
                                icon: Icons.chevron_left_rounded, tooltip: '이전 사진', onTap: () => _go(_index - 1)),
                          ),
                        ),
                      if (many && _index < widget.items.length - 1)
                        Positioned(
                          right: 8,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: _RoundButton(
                                icon: Icons.chevron_right_rounded, tooltip: '다음 사진', onTap: () => _go(_index + 1)),
                          ),
                        ),
                    ],
                  ),
                ),
                // 아래: 이름표 + 설명 + 받은 때
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xF20A090E), Color(0x000A090E)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.chip != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: widget.accent.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(item.chip!,
                              style: AppTextStyles.messageTime
                                  .copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(item.label,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.chatBubbleBody
                              .copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                      if (item.caption != null) ...[
                        const SizedBox(height: 4),
                        Text(item.caption!,
                            style: AppTextStyles.messageTime.copyWith(color: Colors.white70)),
                      ],
                      if (photo != null || item.onGoTo != null) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            if (photo != null)
                              Expanded(
                                child: OutlinedButton.icon(
                                  key: const ValueKey('photo_viewer_save'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white38),
                                    minimumSize: const Size.fromHeight(44),
                                  ),
                                  onPressed: _saving ? null : () => _save(item),
                                  icon: const Icon(Icons.download_rounded, size: 18),
                                  label: const Text('저장'),
                                ),
                              ),
                            if (photo != null && item.onGoTo != null) const SizedBox(width: 10),
                            if (item.onGoTo != null)
                              Expanded(
                                child: FilledButton.icon(
                                  key: const ValueKey('photo_viewer_goto'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: widget.accent,
                                    minimumSize: const Size.fromHeight(44),
                                  ),
                                  onPressed: () {
                                    widget.onClose();
                                    item.onGoTo!();
                                  },
                                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                                  label: const Text('이 톡으로 가기'),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 사진 한 장: 진짜 사진이면 확대 가능, 없으면 설명 카드
class _PhotoPage extends StatelessWidget {
  const _PhotoPage({required this.item, required this.accent});

  final PhotoViewerItem item;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final photo = CharacterImage.providerFor(item.image ?? '');
    if (photo != null) {
      return InteractiveViewer(
        maxScale: 4,
        child: Center(child: Image(image: photo, fit: BoxFit.contain, semanticLabel: item.label)),
      );
    }
    return Center(
      child: Container(
        width: 260,
        height: 340,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_camera_back_rounded, size: 52, color: accent),
            const SizedBox(height: 14),
            Text(item.label,
                textAlign: TextAlign.center,
                style: AppTextStyles.chatBubbleBody.copyWith(color: Colors.white)),
            const SizedBox(height: 10),
            Text('아직 사진이 없어서 설명으로 보여 줘요',
                textAlign: TextAlign.center,
                style: AppTextStyles.messageTime.copyWith(color: Colors.white60)),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.35)),
      icon: Icon(icon, color: Colors.white),
    );
  }
}

/// '10월 26일 밤 11:43' 같은 받은 때 글
String photoTimeLabel(DateTime t) {
  final h = t.hour;
  final part = h < 6
      ? '새벽'
      : h < 12
          ? '오전'
          : h < 18
              ? '오후'
              : '밤';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '${t.month}월 ${t.day}일 $part $h12:${t.minute.toString().padLeft(2, '0')}';
}

/// 사진 크게 보기를 화면 전체(윗줄까지 덮어서)로 띄움. 닫으면 끝나는 Future
Future<void> showPhotoViewer(
  BuildContext context, {
  required List<PhotoViewerItem> items,
  int initialIndex = 0,
  Color accent = AppColors.primaryPink,
}) {
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (routeContext, _, __) => PhotoViewer(
      items: items,
      initialIndex: initialIndex,
      accent: accent,
      onClose: () => Navigator.of(routeContext).pop(),
    ),
    transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
  ));
}
