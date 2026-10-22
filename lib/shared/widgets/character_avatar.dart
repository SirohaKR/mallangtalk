import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../models/mallangtalk_models.dart';

/// 캐릭터 프로필 동그라미 (사진이 아직 없으니 이름 첫 글자 + 캐릭터마다 다른 파스텔색)
class CharacterAvatar extends StatelessWidget {
  const CharacterAvatar({super.key, required this.character, this.radius = 22});

  final CharacterModel character;
  final double radius;

  static const _palette = [
    Color(0xFFFFE0EB),
    Color(0xFFE3ECFF),
    Color(0xFFFFF1D6),
    Color(0xFFE2F5EA),
    Color(0xFFEDE4FF),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _palette[character.id.hashCode.abs() % _palette.length];
    final initial = character.name.isEmpty ? '?' : character.name.characters.first;
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: 'NotoSansKR',
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryNavy,
        ),
      ),
    );
  }
}
