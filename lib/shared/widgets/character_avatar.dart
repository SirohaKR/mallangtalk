import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../models/mallangtalk_models.dart';

/// [초보자 노트] 캐릭터 이미지 하나로 프로필 동그라미와 갤러리 썸네일을 함께 그립니다.
/// 이미지가 없거나 못 불러오면 이름 첫 글자가 들어간 파스텔 카드로 대신합니다.
class CharacterImage extends StatelessWidget {
  const CharacterImage({super.key, required this.character, this.borderRadius = 0, this.fontSize = 40});

  final CharacterModel character;
  final double borderRadius;
  final double fontSize;

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
      final comma = url.indexOf(',');
      if (comma < 0) return null;
      try {
        return MemoryImage(base64Decode(url.substring(comma + 1)));
      } catch (_) {
        return null;
      }
    }
    if (url.startsWith('http')) return NetworkImage(url);
    // 말랑톡 서버 DB에 저장된 사진 (/api/images/…). 지금 연 서버 주소 기준으로
    if (url.startsWith('/api/')) return NetworkImage(Uri.base.resolve(url).toString());
    if (url.startsWith('assets/')) return AssetImage(url);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = providerFor(character.avatarUrl);
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
    final colors = CharacterImage._palette[character.id.hashCode.abs() % CharacterImage._palette.length];
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
      child: CharacterImage(character: character, borderRadius: radius, fontSize: radius * 0.8),
    );
  }
}
