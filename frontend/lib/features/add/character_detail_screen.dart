import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/widgets/character_avatar.dart';
import '../../shared/widgets/character_sheet_view.dart';
import '../chat/service_messages.dart';
import '../chat/start_chat.dart';
import '../discover/gallery_card.dart';
import '../library/character_library.dart';
import '../settings/user_profile.dart';
import '../../shared/utils/korean.dart';

/// 상세 화면 탭: 이름과 그 탭에 보여 줄 설정 묶음
const _tabs = [
  ('소개', [SheetSection.info, SheetSection.setting, SheetSection.comment]),
  ('세계관', [SheetSection.world]),
  ('나는 이 이야기에서', [SheetSection.role]),
  ('주변 인물', [SheetSection.cast]),
];

/// [초보자 노트] 갤러리에서 캐릭터를 누르면 뜨는 상세 화면입니다.
/// 맨 위 대표 사진(커버) 위에 프로필 사진이 겹치고, 이름·한줄 소개·만든 사람 카드·태그·친구 수가 나와요.
/// 아래는 소개/세계관/나는 이 이야기에서/주변 인물 탭(내용 있는 탭만), 맨 아래 고정 버튼으로 친구 추가하고 바로 대화해요.
class CharacterDetailScreen extends ConsumerStatefulWidget {
  const CharacterDetailScreen({super.key, required this.characterId});

  final String characterId;

  @override
  ConsumerState<CharacterDetailScreen> createState() => _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends ConsumerState<CharacterDetailScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final gallery = ref.watch(galleryProvider).valueOrNull ?? const [];
    final item = gallery.where((g) => g.bundle.character.id == widget.characterId).firstOrNull;
    final bundle = item?.bundle;
    if (item == null || bundle == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('캐릭터를 찾을 수 없어요', style: AppTextStyles.systemNotice)),
      );
    }
    final c = bundle.character;
    final isFriend = ref.watch(characterLibraryProvider).any((e) => e.id == c.id);
    final nickname = ref.watch(chatNicknameProvider(c.id));
    final tabs = [
      for (final t in _tabs)
        if (t.$2.any((s) => CharacterSheetView.hasContent(c, s))) t,
    ];
    final tab = tabs.isEmpty ? null : tabs[_tab.clamp(0, tabs.length - 1)];
    final coverHeight = AppSpacing.isWide(context, 760) ? 300.0 : 240.0;
    final stats = [
      if (item.friends > 0) '친구 ${item.friends}명',
      if (!c.isService && bundle.events.isNotEmpty) '이야기 ${bundle.events.length}개',
      if (!c.isService && bundle.albumPhotos.isNotEmpty) '사진 ${bundle.albumPhotos.length}장',
    ];

    return Scaffold(
      backgroundColor: AppColors.surfaceWhite,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: Padding(
          padding: const EdgeInsets.all(6),
          child: Material(
            color: Colors.white.withValues(alpha: 0.85),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: '뒤로',
              icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
              onPressed: () => context.canPop() ? context.pop() : context.go('/discover'),
            ),
          ),
        ),
      ),
      // 아래에 고정된 버튼: 친구가 아니면 친구 추가하고 바로 대화방으로
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
          decoration: const BoxDecoration(
            color: AppColors.surfaceWhite,
            border: Border(top: BorderSide(color: AppColors.borderLight)),
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: AppSpacing.pageConstraints(context, maxDesktop: 840),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryPink,
                  minimumSize: const Size.fromHeight(50),
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
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: AppSpacing.pageConstraints(context, maxDesktop: 840),
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              // 대표 사진 위에 프로필 사진이 반쯤 겹침
              SizedBox(
                height: coverHeight + 48,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: coverHeight,
                      child: CharacterImage(character: c, fontSize: 96, cover: true),
                    ),
                    Positioned(
                      left: AppSpacing.lg,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: AppColors.surfaceWhite, shape: BoxShape.circle),
                        child: CharacterAvatar(character: c, radius: 40),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: AppTextStyles.appBarTitle.copyWith(fontSize: 22)),
                    if (c.tagline.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(CharacterModel.fillUserName(c.tagline, nickname, charName: c.name),
                          style: AppTextStyles.chatBubbleBody.copyWith(color: AppColors.textSecondary)),
                    ],
                    if (item.creator != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _CreatorCard(item: item),
                    ],
                    if (c.isService && c.service != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        key: const ValueKey('detail_service'),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFCEFD2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '서비스 말랑이 · ${serviceScheduleLabel(c.service!)} 먼저 톡이 와요',
                          style: AppTextStyles.messageTime
                              .copyWith(color: const Color(0xFF6B4800), fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                    if (c.tags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in c.tags)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceWhite,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: AppColors.borderLight),
                              ),
                              child: Text('#$tag', style: AppTextStyles.messageTime.copyWith(color: AppColors.textPrimary)),
                            ),
                        ],
                      ),
                    ],
                    if (stats.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(stats.join(' · '), key: const ValueKey('detail_stats'), style: AppTextStyles.messageTime),
                    ],
                    if (c.quote.trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '"${CharacterModel.fillUserName(c.quote.trim(), nickname, charName: c.name)}"',
                        style: AppTextStyles.chatBubbleBody.copyWith(fontStyle: FontStyle.italic, height: 1.6),
                      ),
                    ],
                  ],
                ),
              ),
              if (tab != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderLight))),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: Row(
                      children: [
                        for (var i = 0; i < tabs.length; i++)
                          _TabButton(
                            key: ValueKey('detail_tab_$i'),
                            label: tabs[i].$1,
                            on: tabs[i] == tab,
                            onTap: () => setState(() => _tab = i),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: CharacterSheetView(character: c, nickname: nickname, sections: tab.$2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// '○○ 님이 만든 말랑이' 카드. 누르면 제작자 프로필
class _CreatorCard extends StatelessWidget {
  const _CreatorCard({required this.item});

  final GalleryItem item;

  @override
  Widget build(BuildContext context) {
    final creator = item.creator!;
    return Material(
      color: AppColors.surfaceWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: InkWell(
        key: const ValueKey('detail_creator'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/creator/${Uri.encodeComponent(creator)}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CreatorAvatar(name: creator, avatarUrl: item.creatorAvatar, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: item.mine ? '$creator (나)' : creator, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const TextSpan(text: ' 님이 만든 말랑이'),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.chatBubbleBody.copyWith(fontSize: 13),
                ),
              ),
              Text('다른 말랑이 ›', style: AppTextStyles.messageTime.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({super.key, required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: on ? AppColors.primaryPink : Colors.transparent, width: 2)),
        ),
        child: Text(
          label,
          style: AppTextStyles.chatBubbleBody.copyWith(
            fontSize: 14,
            fontWeight: on ? FontWeight.w700 : FontWeight.w400,
            color: on ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
