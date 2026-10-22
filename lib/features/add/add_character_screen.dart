import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/widgets/character_avatar.dart';
import '../library/character_library.dart';
import '../studio/studio_screen.dart';
import '../../shared/utils/korean.dart';

/// [초보자 노트] '캐릭터 추가' 탭: 받아오기(기본 캐릭터·파일) / 만들기(엑셀 대본·AI 생성)
class AddCharacterScreen extends StatelessWidget {
  const AddCharacterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('캐릭터 추가'),
          bottom: TabBar(
            labelStyle: AppTextStyles.choiceButton,
            unselectedLabelStyle: AppTextStyles.choiceButton.copyWith(color: AppColors.textSecondary),
            indicatorColor: AppColors.primaryPink,
            tabs: const [Tab(text: '받아오기'), Tab(text: '만들기')],
          ),
        ),
        body: const TabBarView(
          children: [ImportCharacterTab(), StudioScreen()],
        ),
      ),
    );
  }
}

/// 받아오기: 캐릭터 갤러리 (썸네일 · 이름 · 한줄 소개). 누르면 상세 화면에서 친구 추가
/// 지금은 앱에 들어 있는 기본 캐릭터만 보이고, 4단계 서버가 생기면 다른 사람이 공개한 캐릭터가 여기 올라옵니다.
class ImportCharacterTab extends ConsumerWidget {
  const ImportCharacterTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gallery = ref.watch(builtinBundlesProvider).valueOrNull ?? const [];
    final mine = ref.watch(characterLibraryProvider).map((e) => e.id).toSet();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.mobileMaxWidth),
        child: GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.lg),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: 0.62,
          ),
          itemCount: gallery.length,
          itemBuilder: (context, index) {
            final bundle = gallery[index];
            return GalleryCard(
              character: bundle.character,
              isFriend: mine.contains(bundle.character.id),
              onTap: () => context.push('/gallery/${bundle.character.id}'),
            );
          },
        ),
      ),
    );
  }
}

/// 갤러리 카드: 썸네일 + 이름 + 한줄 소개 + 태그
class GalleryCard extends StatelessWidget {
  const GalleryCard({super.key, required this.character, required this.isFriend, required this.onTap});

  final CharacterModel character;
  final bool isFriend;
  final VoidCallback onTap;

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
                  CharacterImage(character: character, fontSize: 52),
                  if (isFriend)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primaryPink,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '친구',
                          style: AppTextStyles.messageTime.copyWith(
                            color: AppColors.surfaceWhite,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(character.name, style: AppTextStyles.appBarTitle.copyWith(fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    CharacterModel.fillUserName(
                      character.tagline.isNotEmpty ? character.tagline : character.statusMessage,
                      '너',
                      charName: character.name,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.systemNotice,
                  ),
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

/// 내 캐릭터에 넣고 '채팅하기' 바로가기를 띄움 (받아오기·만들기 공통)
Future<void> addCharacterAndAnnounce(
  BuildContext context,
  WidgetRef ref,
  ScenarioBundle bundle,
  CharacterSource source,
) async {
  await ref.read(characterLibraryProvider.notifier).add(bundle, source);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('${josa(bundle.character.name, '을', '를')} 친구로 추가했어요. 내 캐릭터에서 대화를 시작해 보세요')),
  );
}

/// 오류·주의 목록 카드
class ProblemList extends StatelessWidget {
  const ProblemList({super.key, required this.title, required this.items, this.isError = false});

  final String title;
  final List<String> items;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.primaryPink : AppColors.affectionWarm;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.choiceRadius),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.speakerName.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          for (final item in items.take(12))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('• $item', style: AppTextStyles.systemNotice),
            ),
          if (items.length > 12)
            Text('그 외 ${items.length - 12}개', style: AppTextStyles.systemNotice),
        ],
      ),
    );
  }
}
