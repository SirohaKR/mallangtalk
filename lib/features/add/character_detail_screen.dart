import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/widgets/character_avatar.dart';
import '../../shared/widgets/character_sheet_view.dart';
import '../chat/start_chat.dart';
import '../discover/gallery_card.dart';
import '../library/character_library.dart';
import '../settings/user_profile.dart';
import '../../shared/utils/korean.dart';

/// [초보자 노트] 갤러리에서 캐릭터를 누르면 뜨는 상세 화면입니다.
/// 큰 이미지, 만든 사람, 한줄 소개, 태그, 캐릭터 설정을 보여주고, 아래 고정 버튼으로 친구 추가하고 바로 대화해요.
class CharacterDetailScreen extends ConsumerWidget {
  const CharacterDetailScreen({super.key, required this.characterId});

  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gallery = ref.watch(galleryProvider).valueOrNull ?? const [];
    final item = gallery.where((g) => g.bundle.character.id == characterId).firstOrNull;
    final bundle = item?.bundle;
    if (item == null || bundle == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('캐릭터를 찾을 수 없어요', style: AppTextStyles.systemNotice)),
      );
    }
    final c = bundle.character;
    final isFriend = ref.watch(characterLibraryProvider).any((e) => e.id == c.id);

    return Scaffold(
      backgroundColor: AppColors.surfaceWhite,
      appBar: AppBar(title: Text(c.name), backgroundColor: AppColors.surfaceWhite),
      // 아래에 고정된 버튼: 친구가 아니면 친구 추가하고 바로 대화방으로
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
          decoration: const BoxDecoration(
            color: AppColors.surfaceWhite,
            border: Border(top: BorderSide(color: AppColors.borderLight)),
          ),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryPink,
              minimumSize: const Size.fromHeight(48),
              textStyle: AppTextStyles.choiceButton,
            ),
            icon: Icon(isFriend ? Icons.chat_bubble_rounded : Icons.person_add_alt_1_rounded, size: 18),
            label: Text(isFriend ? '대화하러 가기' : '친구 추가하고 대화하기'),
            onPressed: () async {
              if (!isFriend) {
                await ref.read(characterLibraryProvider.notifier).addFriend(
                      bundle,
                      item.isBuiltin
                          ? CharacterSource.builtin
                          : item.mine
                              ? CharacterSource.created
                              : CharacterSource.imported,
                    );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${josa(c.name, '을', '를')} 친구로 추가했어요')),
                );
              }
              openChat(context, c);
            },
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.mobileMaxWidth),
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              AspectRatio(
                aspectRatio: 1.1,
                child: CharacterImage(character: c, fontSize: 96),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: AppTextStyles.appBarTitle.copyWith(fontSize: 22)),
                    if (item.creator != null) ...[
                      const SizedBox(height: 8),
                      CreatorLine(creator: item.creator!, mine: item.mine, size: 22),
                    ],
                    if (c.tagline.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(CharacterModel.fillUserName(c.tagline, '너', charName: c.name),
                          style: AppTextStyles.chatBubbleBody),
                    ],
                    if (c.tags.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in c.tags)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.myBubble,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('#$tag',
                                  style: AppTextStyles.speakerName.copyWith(color: AppColors.primaryPink)),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    CharacterSheetView(character: c, nickname: ref.watch(chatNicknameProvider(c.id))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
