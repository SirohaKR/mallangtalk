import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/character_avatar.dart';
import '../../shared/widgets/character_sheet_view.dart';
import '../chat/start_chat.dart';
import '../library/character_library.dart';
import '../settings/user_profile.dart';
import '../../shared/utils/korean.dart';

/// [초보자 노트] 갤러리에서 캐릭터를 누르면 뜨는 상세 화면입니다.
/// 큰 이미지, 한줄 소개, 태그, 캐릭터 설정, 관계 단계를 보여주고 '친구 추가'로 내 캐릭터에 넣습니다.
class CharacterDetailScreen extends ConsumerWidget {
  const CharacterDetailScreen({super.key, required this.characterId});

  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gallery = ref.watch(builtinBundlesProvider).valueOrNull ?? const [];
    final bundle = gallery.where((b) => b.character.id == characterId).firstOrNull;
    if (bundle == null) {
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
                    if (c.tagline.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(c.tagline, style: AppTextStyles.chatBubbleBody),
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
                              child: Text('#$tag', style: AppTextStyles.speakerName.copyWith(color: AppColors.primaryPink)),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    SizedBox(
                      width: double.infinity,
                      child: isFriend
                          ? ElevatedButton.icon(
                              icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                              label: const Text('친구 · 1:1 채팅'),
                              onPressed: () => openChat(context, ref, c),
                            )
                          : ElevatedButton.icon(
                              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                              label: const Text('친구 추가'),
                              onPressed: () async {
                                await ref.read(characterLibraryProvider.notifier)
                                    .add(bundle, CharacterSource.builtin);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('${josa(c.name, '을', '를')} 친구로 추가했어요')),
                                  );
                                }
                              },
                            ),
                    ),
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
