import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/widgets/character_avatar.dart';

/// 갤러리 카드: 썸네일 + 이름 + 한줄 소개 + 만든 사람 + 태그
/// 만든 사람 이름을 누르면 그 사람의 말랑이 모아 보기(/creator/이름)로 가요.
class GalleryCard extends StatelessWidget {
  const GalleryCard({
    super.key,
    required this.character,
    this.creator,
    this.creatorAvatar = '',
    this.mine = false,
    required this.isFriend,
    required this.onTap,
    this.friends,
  });

  final CharacterModel character;

  /// 만든 사람 (앱 기본 캐릭터면 null)
  final String? creator;

  /// 만든 사람의 프로필 사진
  final String creatorAvatar;
  final bool mine;
  final bool isFriend;
  final VoidCallback onTap;

  /// 친구 수 (제작자 화면처럼 만든 사람 줄 대신 보여 줄 때)
  final int? friends;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: AppColors.borderLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CharacterImage(character: character, fontSize: 52, cover: true),
                  if (isFriend) const Positioned(top: 8, right: 8, child: _Badge('친구')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(character.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.appBarTitle.copyWith(fontSize: 15)),
                      ),
                      if (character.isService) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCEFD2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text('서비스',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF6B4800))),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    taglineOf(character),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.systemNotice,
                  ),
                  if (creator != null) ...[
                    const SizedBox(height: 6),
                    CreatorLine(creator: creator!, avatarUrl: creatorAvatar, mine: mine),
                  ],
                  if (friends != null) ...[
                    const SizedBox(height: 4),
                    Text('친구 $friends', style: AppTextStyles.messageTime),
                  ],
                  if (character.tags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      character.tags.take(3).map((t) => '#$t').join(' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.messageTime.copyWith(color: AppColors.primaryPink),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 카드·목록에 보이는 한줄 소개 (없으면 상태 메시지)
String taglineOf(CharacterModel c) => CharacterModel.fillUserName(
      c.tagline.isNotEmpty ? c.tagline : c.statusMessage,
      '너',
      charName: c.name,
    );

/// 만든 사람 줄: 동그라미 첫 글자 + 이름. 누르면 제작자 프로필
class CreatorLine extends StatelessWidget {
  const CreatorLine({super.key, required this.creator, this.avatarUrl = '', this.mine = false, this.size = 18});

  final String creator;

  /// 만든 사람의 프로필 사진 (비우면 이름 첫 글자 동그라미)
  final String avatarUrl;
  final bool mine;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/creator/${Uri.encodeComponent(creator)}'),
      child: Row(
        children: [
          CreatorAvatar(name: creator, avatarUrl: avatarUrl, size: size),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              mine ? '$creator (나)' : creator,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.messageTime.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 제작자 동그라미: 그 사람이 설정에서 정한 프로필 사진.
/// 사진이 없으면 이름 첫 글자 (색은 이름으로 정해짐)
class CreatorAvatar extends StatelessWidget {
  const CreatorAvatar({super.key, required this.name, this.avatarUrl = '', this.size = 18});

  final String name;
  final String avatarUrl;
  final double size;

  static const _colors = [
    Color(0xFFB83B66),
    Color(0xFF3B4A8C),
    Color(0xFF2F7A5B),
    Color(0xFF8A5A2B),
    Color(0xFF6B3FA0),
    Color(0xFF1F7A8C)
  ];

  @override
  Widget build(BuildContext context) {
    final color = _colors[name.codeUnits.fold(0, (a, b) => a + b) % _colors.length];
    final photo = CharacterImage.providerFor(avatarUrl);
    if (photo != null) {
      return CircleAvatar(radius: size / 2, backgroundColor: color, backgroundImage: photo);
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        name.isEmpty ? '?' : name.characters.first,
        style: TextStyle(color: Colors.white, fontSize: size * 0.5, fontWeight: FontWeight.w700, height: 1),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.primaryPink, borderRadius: BorderRadius.circular(10)),
      child: Text(
        text,
        style: AppTextStyles.messageTime.copyWith(color: AppColors.surfaceWhite, fontWeight: FontWeight.w700),
      ),
    );
  }
}
