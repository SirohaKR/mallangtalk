import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/network/api_endpoint.dart';
import '../models/mallangtalk_models.dart';
import 'inline_image_cache.dart';

/// [초보자 노트] 캐릭터 이미지 하나로 프로필 동그라미와 갤러리 썸네일을 함께 그립니다.
/// 이미지가 없거나 못 불러오면 이름 첫 글자가 들어간 파스텔 카드로 대신합니다.
class CharacterImage extends StatelessWidget {
  static final _inlineImages = InlineImageCache();
  const CharacterImage(
      {super.key,
      required this.character,
      this.borderRadius = 0,
      this.fontSize = 40,
      this.cover = false});

  final CharacterModel character;
  final double borderRadius;
  final double fontSize;

  /// 대표(커버) 사진을 먼저 씀 (말랑이 찾기 카드·상세 화면 맨 위)
  final bool cover;

  static const _palette = [
    [Color(0xFFFFD6E4), Color(0xFFFFEFF4)],
    [Color(0xFFD9E5FF), Color(0xFFF0F4FF)],
    [Color(0xFFFFE8C7), Color(0xFFFFF6E8)],
    [Color(0xFFD5F2E1), Color(0xFFEFFAF3)],
    [Color(0xFFE4D9FF), Color(0xFFF4F0FF)],
  ];

  static ImageProvider? providerFor(String url) {
    if (url.isEmpty) return null;
    if (url.startsWith('data:')) {
      return _inlineImages.providerFor(url);
    }
    if (url.startsWith('http')) return NetworkImage(url);
    // 말랑톡 서버 DB에 저장된 사진 (/api/images/…). 지금 연 서버 주소 기준으로
    if (url.startsWith('/api/')) return NetworkImage(resolveApiAsset(url));
    if (url.startsWith('assets/')) return AssetImage(url);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = providerFor(cover ? character.coverOrAvatar : character.avatarUrl);
    final fallback = _Fallback(character: character, fontSize: fontSize);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: provider == null
          ? fallback
          : Image(
              image: provider,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => fallback,
            ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.character, required this.fontSize});

  final CharacterModel character;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final colors = CharacterImage
        ._palette[character.id.hashCode.abs() % CharacterImage._palette.length];
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        character.name.isEmpty ? '?' : character.name.characters.first,
        style: TextStyle(
          fontFamily: 'NotoSansKR',
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryNavy.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

/// 캐릭터 프로필 동그라미
class CharacterAvatar extends StatelessWidget {
  const CharacterAvatar({super.key, required this.character, this.radius = 22});

  final CharacterModel character;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: CharacterImage(
          character: character, borderRadius: radius, fontSize: radius * 0.8),
    );
  }
}

/// 프로필 사진 크게 보기. 두 손가락으로 확대, 배경이나 X를 누르면 닫혀요
Future<void> showCharacterPhoto(
    BuildContext context, CharacterModel character) {
  return showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (dialogContext) => GestureDetector(
      key: const ValueKey('photo_viewer'),
      onTap: () => Navigator.of(dialogContext).pop(),
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              maxScale: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _PhotoOrCard(character: character),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: '닫기',
                color: Colors.white,
                icon: const Icon(Icons.close_rounded, size: 28),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 사진이 있으면 잘리지 않게 원래 비율로, 없으면 이름 카드
class _PhotoOrCard extends StatelessWidget {
  const _PhotoOrCard({required this.character});

  final CharacterModel character;

  @override
  Widget build(BuildContext context) {
    final card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: CharacterImage(
            character: character, borderRadius: 12, fontSize: 96),
      ),
    );
    final provider = CharacterImage.providerFor(character.avatarUrl);
    if (provider == null) return card;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image(
          image: provider,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => card),
    );
  }
}
