import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/character_avatar.dart';
import '../auth/auth_state.dart';
import '../home/friends_screen.dart';
import '../library/character_library.dart';

/// [초보자 노트] '내 말랑이' 탭: 친구 / 내가 만든 두 칸.
/// 오른쪽 위 '만들기' 버튼을 누르면 어디서든 바로 새 말랑이를 만들어요 (/create).
class MyMallangScreen extends StatelessWidget {
  const MyMallangScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('내 말랑이'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: FilledButton.icon(
                key: const ValueKey('my_create'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryPink,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('만들기'),
                onPressed: () => context.push('/create'),
              ),
            ),
          ],
          bottom: TabBar(
            labelStyle: AppTextStyles.choiceButton,
            unselectedLabelStyle: AppTextStyles.choiceButton.copyWith(color: AppColors.textSecondary),
            indicatorColor: AppColors.primaryPink,
            tabs: const [Tab(text: '친구'), Tab(text: '내가 만든')],
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: AppSpacing.pageConstraints(context),
            child: const TabBarView(children: [FriendsList(), MyCreationsList()]),
          ),
        ),
      ),
    );
  }
}

/// 내가 만든 말랑이 목록. 줄마다 '수정' 버튼, 누르면 프로필(대화·앨범·내보내기)
class MyCreationsList extends ConsumerWidget {
  const MyCreationsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(characterLibraryProvider).where((e) => e.source == CharacterSource.created).toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    // 로그인해서 서버에 올렸으면 말랑이 찾기에 보이고, 아니면 이 기기에만 있어요
    final online = ref.watch(accountApiProvider) != null;
    final wide = AppSpacing.isWide(context, 760);
    // 말랑이 찾기에서 몇 명이 친구로 추가했는지 (서버 목록에 있을 때만)
    final gallery = ref.watch(galleryProvider).valueOrNull ?? const <GalleryItem>[];
    int? friendsOf(String id) => gallery.where((g) => g.character.id == id).firstOrNull?.friends;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        _NewTile(onTap: () => context.push('/create')),
        if (mine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 6),
            child: Text('내가 만든 ${mine.length}', style: AppTextStyles.messageTime),
          ),
        if (mine.isNotEmpty && wide)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 520,
                mainAxisExtent: 74,
                mainAxisSpacing: 8,
                crossAxisSpacing: 12,
              ),
              itemCount: mine.length,
              itemBuilder: (context, i) => Material(
                color: AppColors.surfaceWhite,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppColors.borderLight),
                ),
                child: _CreationTile(entry: mine[i], online: online, friends: friendsOf(mine[i].id)),
              ),
            ),
          )
        else
          for (final entry in mine) _CreationTile(entry: entry, online: online, friends: friendsOf(entry.id)),
        if (mine.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Text(
              '아직 만든 말랑이가 없어요. 위의 새 말랑이 만들기를 눌러 시작해 보세요',
              textAlign: TextAlign.center,
              style: AppTextStyles.systemNotice,
            ),
          ),
        if (mine.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: OutlinedButton.icon(
              onPressed: () => context.push('/relations'),
              icon: const Icon(Icons.hub_outlined, size: 18),
              label: const Text('관계도 보기 · 캐릭터끼리 관계 잇기'),
            ),
          ),
        ],
      ],
    );
  }
}

class _NewTile extends StatelessWidget {
  const _NewTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 4),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.myBubble,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primaryPink.withValues(alpha: 0.4)),
        ),
        child: const Icon(Icons.add_rounded, color: AppColors.primaryPink),
      ),
      title: Text('새 말랑이 만들기', style: AppTextStyles.appBarTitle.copyWith(fontSize: 15)),
      subtitle: const Text('직접 쓰거나 AI로 대본까지 만들어요', style: AppTextStyles.systemNotice),
      onTap: onTap,
    );
  }
}

class _CreationTile extends StatelessWidget {
  const _CreationTile({required this.entry, required this.online, this.friends});

  final LibraryEntry entry;
  final bool online;

  /// 말랑이 찾기 친구 수 (서버에 없으면 null)
  final int? friends;

  @override
  Widget build(BuildContext context) {
    final c = entry.bundle.character;
    final events = entry.bundle.events.length;
    // 공개: 로그인해서 말랑이 찾기에 올라감 / 나만 보기: 찾기에 안 보이게 했거나 이 기기에만 있음
    final public = online && !c.unlisted;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 2),
      leading: CharacterAvatar(character: c, radius: 24),
      title: Row(
        children: [
          Flexible(
            child: Text(c.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.appBarTitle.copyWith(fontSize: 15)),
          ),
          const SizedBox(width: 6),
          Container(
            key: ValueKey('creation_visibility_${c.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: public ? const Color(0xFFFBE3EB) : const Color(0xFFEFEDEE),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(public ? '공개' : '나만 보기',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: public ? const Color(0xFF8E2E52) : AppColors.textSecondary)),
          ),
        ],
      ),
      subtitle: Text(
        [
          if (public && friends != null) '친구 $friends',
          if (!online) '이 기기에만 저장',
          c.isService ? '서비스 말랑이' : '이야기 $events개',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.systemNotice,
      ),
      trailing: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
        icon: const Icon(Icons.edit_outlined, size: 16),
        label: const Text('수정'),
        onPressed: () => context.push('/edit/${c.id}'),
      ),
      onTap: () => showCharacterProfile(context, entry),
    );
  }
}
