import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/character_avatar.dart';
import '../library/character_library.dart';
import '../chat/chat_notifier.dart';
import '../chat/start_chat.dart';
import 'gallery_card.dart';

/// 새로 올라온 말랑이 정렬
enum GallerySort { latest, popular }

/// 최신순: 처음 올린 때가 늦은 순 (모르면 맨 뒤)
int _byLatest(GalleryItem a, GalleryItem b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000));

/// 인기순: 친구 수가 많은 순, 같으면 최신순
int _byPopular(GalleryItem a, GalleryItem b) {
  final byFriends = b.friends.compareTo(a.friends);
  return byFriends != 0 ? byFriends : _byLatest(a, b);
}

/// 오늘의 추천: 친구 수에 최근에 올라온 덤을 얹어 고름 (새 말랑이도 한 번씩 보이게)
List<GalleryItem> recommendedOf(List<GalleryItem> items, {DateTime? now, int count = 6}) {
  final today = now ?? DateTime.now();
  double score(GalleryItem g) {
    final days = g.createdAt == null ? 365 : today.difference(g.createdAt!).inHours / 24;
    return g.friends + 6 / (1 + days.clamp(0, 365));
  }

  return ([...items]..sort((a, b) => score(b).compareTo(score(a)))).take(count).toList();
}

/// 갤러리에 많이 쓰인 태그 (장르 칩)
List<String> topTagsOf(List<GalleryItem> items, {int count = 10}) {
  final counts = <String, int>{};
  for (final g in items) {
    for (final t in g.character.tags) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
  }
  return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(count).map((e) => e.key).toList();
}

/// 성별 필터: 'male'·'female'·'none'(미정). 성별을 안 고른 말랑이는 미정에 함께 보여요. null이면 전체
List<GalleryItem> genderFiltered(List<GalleryItem> items, String? gender) {
  if (gender == null) return items;
  return items.where((g) {
    final value = g.character.gender.isEmpty ? 'none' : g.character.gender;
    return value == gender;
  }).toList();
}

const _genders = [('male', '남성'), ('female', '여성'), ('none', '미정')];

/// [초보자 노트] 앱을 켜면 처음 보이는 '말랑이 찾기' 탭입니다.
/// 위에서부터 검색창 → 장르(태그) 칩 → 성별 칩 → 오늘의 추천(가로로 넘김) → 새로 올라온 말랑이(최신·인기 정렬) 순서예요.
/// 모든 카드에 만든 사람이 보이고, 누르면 상세 화면(/gallery/ID)으로 가요.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  String? _tag;
  String? _gender;
  GallerySort _sort = GallerySort.latest;

  @override
  Widget build(BuildContext context) {
    final gallery = ref.watch(galleryProvider);
    final all = gallery.valueOrNull ?? const <GalleryItem>[];
    final friends = ref.watch(characterLibraryProvider).map((e) => e.id).toSet();
    final items = genderFiltered(_tag == null ? all : all.where((g) => g.character.tags.contains(_tag)).toList(), _gender);
    final tags = topTagsOf(all);
    final picks = recommendedOf(items);
    final sorted = [...items]..sort(_sort == GallerySort.latest ? _byLatest : _byPopular);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final gridColumns = screenWidth >= 980
        ? 4
        : screenWidth >= 680
            ? 3
            : 2;

    return Scaffold(
      appBar: AppBar(title: const Text('말랑이 찾기'), actions: const [_AlertBell(), SizedBox(width: 6)]),
      body: Center(
        child: ConstrainedBox(
          constraints: AppSpacing.pageConstraints(context),
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(galleryProvider.future),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                    child: _SearchBox(onTap: () => context.push('/search')),
                  ),
                ),
                if (tags.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 52,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 4),
                        children: [
                          _TagChip(label: '전체', selected: _tag == null, onTap: () => setState(() => _tag = null)),
                          for (final t in tags)
                            _TagChip(
                                label: t,
                                selected: _tag == t,
                                onTap: () => setState(() => _tag = _tag == t ? null : t)),
                        ],
                      ),
                    ),
                  ),
                if (all.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.fromLTRB(AppSpacing.lg, tags.isEmpty ? AppSpacing.md : 2, AppSpacing.lg, 4),
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Center(child: Text('성별', style: AppTextStyles.systemNotice)),
                          ),
                          _TagChip(
                              key: const ValueKey('gender_all'),
                              label: '전체',
                              selected: _gender == null,
                              onTap: () => setState(() => _gender = null)),
                          for (final (value, label) in _genders)
                            _TagChip(
                                key: ValueKey('gender_$value'),
                                label: label,
                                plain: true,
                                selected: _gender == value,
                                onTap: () => setState(() => _gender = _gender == value ? null : value)),
                        ],
                      ),
                    ),
                  ),
                if (gallery.isLoading && all.isEmpty)
                  const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
                else if (items.isEmpty)
                  SliverFillRemaining(hasScrollBody: false, child: _Empty(filtered: _tag != null || _gender != null))
                else ...[
                  const _SectionTitle('오늘의 추천'),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 268,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        itemCount: picks.length,
                        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
                        itemBuilder: (context, i) =>
                            _PickCard(item: picks[i], isFriend: friends.contains(picks[i].character.id)),
                      ),
                    ),
                  ),
                  _SectionTitle(
                    '새로 올라온 말랑이',
                    trailing: SegmentedButton<GallerySort>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                          visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      segments: const [
                        ButtonSegment(value: GallerySort.latest, label: Text('최신')),
                        ButtonSegment(value: GallerySort.popular, label: Text('인기')),
                      ],
                      selected: {_sort},
                      onSelectionChanged: (s) => setState(() => _sort = s.first),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
                    sliver: SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: gridColumns,
                        mainAxisSpacing: AppSpacing.md,
                        crossAxisSpacing: AppSpacing.md,
                        childAspectRatio: screenWidth >= 680 ? 0.63 : 0.58,
                      ),
                      itemCount: sorted.length,
                      itemBuilder: (context, i) {
                        final item = sorted[i];
                        return GalleryCard(
                          character: item.character,
                          creator: item.creator,
                          creatorAvatar: item.creatorAvatar,
                          mine: item.mine,
                          isFriend: friends.contains(item.character.id),
                          onTap: () => context.push('/gallery/${item.character.id}'),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: InkWell(
        key: const ValueKey('discover_search'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: AppColors.textSecondary),
              SizedBox(width: 8),
              Expanded(child: Text('이름, 태그, 만든 사람으로 찾기', style: AppTextStyles.systemNotice)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({super.key, required this.label, required this.selected, required this.onTap, this.plain = false});

  final String label;
  /// 태그가 아닌 칩(성별)은 # 없이
  final bool plain;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label == '전체' || plain ? label : '#$label'),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.textPrimary,
        labelStyle: AppTextStyles.messageTime.copyWith(
          fontSize: 13,
          color: selected ? AppColors.surfaceWhite : AppColors.textPrimary,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        backgroundColor: AppColors.surfaceWhite,
        side: BorderSide(color: selected ? AppColors.textPrimary : AppColors.borderLight),
        shape: const StadiumBorder(),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
        child: Row(
          children: [
            Expanded(child: Text(title, style: AppTextStyles.appBarTitle.copyWith(fontSize: 17))),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// 오늘의 추천 큰 카드 (사진 위에 이름·한줄 소개)
class _PickCard extends StatelessWidget {
  const _PickCard({required this.item, required this.isFriend});

  final GalleryItem item;
  final bool isFriend;

  @override
  Widget build(BuildContext context) {
    final c = item.character;
    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              onTap: () => context.push('/gallery/${c.id}'),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CharacterImage(character: c, fontSize: 64, cover: true),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xCC000000)],
                          stops: [0.45, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.appBarTitle.copyWith(color: Colors.white, fontSize: 17)),
                          const SizedBox(height: 2),
                          Text(taglineOf(c),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.systemNotice.copyWith(color: Colors.white.withValues(alpha: 0.9))),
                        ],
                      ),
                    ),
                    if (isFriend)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration:
                              BoxDecoration(color: AppColors.primaryPink, borderRadius: BorderRadius.circular(10)),
                          child: Text('친구',
                              style:
                                  AppTextStyles.messageTime.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (item.creator != null) ...[
            const SizedBox(height: 6),
            CreatorLine(creator: item.creator!, avatarUrl: item.creatorAvatar, mine: item.mine),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.screenPadding,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.travel_explore_rounded, size: 48, color: AppColors.textMuted),
          const SizedBox(height: AppSpacing.md),
          Text(filtered ? '조건에 맞는 말랑이가 없어요' : '아직 올라온 말랑이가 없어요', style: AppTextStyles.appBarTitle),
          const SizedBox(height: 6),
          const Text('내 말랑이를 만들어 첫 번째로 올려 보세요', style: AppTextStyles.systemNotice),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(onPressed: () => context.push('/create'), child: const Text('말랑이 만들기')),
        ],
      ),
    );
  }
}

/// 검색 정렬: 정확도(이름이 맞을수록 위)·최신·인기
enum SearchSort { relevance, latest, popular }

/// 검색어와 얼마나 잘 맞는지. 0이면 안 맞음 (이름 > 태그 > 한줄 소개 > 만든 사람)
int searchScore(GalleryItem g, String query) {
  final q = query.trim().toLowerCase().replaceFirst('#', '');
  if (q.isEmpty) return 1;
  final c = g.character;
  final name = c.name.toLowerCase();
  if (name == q) return 100;
  if (name.startsWith(q)) return 80;
  if (name.contains(q)) return 60;
  if (c.tags.any((t) => t.toLowerCase() == q)) return 50;
  if (c.tags.any((t) => t.toLowerCase().contains(q))) return 40;
  if (c.tagline.toLowerCase().contains(q) || c.statusMessage.toLowerCase().contains(q)) return 20;
  if ((g.creator ?? '').toLowerCase().contains(q)) return 10;
  return 0;
}

/// 검색어에 맞는 제작자: (이름, 프로필 사진, 말랑이 수, 친구 수)
List<({String name, String avatar, int count, int friends})> creatorsMatching(List<GalleryItem> all, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final byName = <String, List<GalleryItem>>{};
  for (final g in all) {
    final name = g.creator;
    if (name != null && name.toLowerCase().contains(q)) (byName[name] ??= []).add(g);
  }
  return [
    for (final e in byName.entries)
      (
        name: e.key,
        avatar: e.value.map((g) => g.creatorAvatar).firstWhere((a) => a.isNotEmpty, orElse: () => ''),
        count: e.value.length,
        friends: e.value.fold(0, (sum, g) => sum + g.friends),
      ),
  ]..sort((a, b) => b.friends.compareTo(a.friends));
}

/// [초보자 노트] 검색 화면 (/search). 위에 말랑이/제작자 탭, 말랑이 탭엔 정확도·최신·인기 정렬.
/// 검색어가 비어 있으면 최근 검색어(이 기기에만 저장)와 많이 쓰인 태그를 보여 줘요.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _query = TextEditingController();
  bool _creators = false;
  SearchSort _sort = SearchSort.relevance;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// 최근 검색어에 넣기 (같은 말은 맨 앞으로, 10개까지)
  void _remember(String word) {
    final w = word.trim();
    if (w.isEmpty) return;
    final store = ref.read(localStoreProvider);
    store.saveRecentSearches([w, ...store.recentSearches.where((x) => x != w)].take(10).toList());
  }

  void _search(String word) => setState(() => _query.text = word);

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(galleryProvider).valueOrNull ?? const <GalleryItem>[];
    final store = ref.watch(localStoreProvider);
    final q = _query.text.trim();
    final scored = q.isEmpty ? const <(GalleryItem, int)>[] : [for (final g in all) (g, searchScore(g, q))];
    final results = [for (final (g, score) in scored) if (score > 0) g];
    final score = {for (final (g, s) in scored) g: s};
    results.sort(switch (_sort) {
      SearchSort.relevance => (a, b) {
          final byScore = score[b]!.compareTo(score[a]!);
          return byScore != 0 ? byScore : _byPopular(a, b);
        },
      SearchSort.latest => _byLatest,
      SearchSort.popular => _byPopular,
    });
    final creators = creatorsMatching(all, q);
    final recent = store.recentSearches;

    Widget body;
    if (q.isEmpty) {
      body = ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (recent.isNotEmpty) ...[
            Row(
              children: [
                const Expanded(child: Text('최근 검색', style: AppTextStyles.speakerName)),
                TextButton(
                  onPressed: () {
                    store.saveRecentSearches(const []);
                    setState(() {});
                  },
                  child: const Text('모두 지우기'),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final w in recent)
                  InputChip(
                    key: ValueKey('recent_$w'),
                    label: Text(w),
                    onPressed: () => _search(w),
                    deleteButtonTooltipMessage: '지우기',
                    onDeleted: () {
                      store.saveRecentSearches(recent.where((x) => x != w).toList());
                      setState(() {});
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          const Text('많이 쓰인 태그', style: AppTextStyles.speakerName),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in topTagsOf(all, count: 16)) ActionChip(label: Text('#$t'), onPressed: () => _search('#$t')),
            ],
          ),
        ],
      );
    } else if (_creators) {
      body = creators.isEmpty
          ? Center(child: Text("'$q'에 맞는 제작자가 없어요", style: AppTextStyles.systemNotice))
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                for (final c in creators)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 4),
                    leading: CreatorAvatar(name: c.name, avatarUrl: c.avatar, size: 48),
                    title: Text(c.name, style: AppTextStyles.appBarTitle.copyWith(fontSize: 15)),
                    subtitle: Text('말랑이 ${c.count} · 친구 ${c.friends}', style: AppTextStyles.messageTime),
                    onTap: () {
                      _remember(q);
                      context.push('/creator/${Uri.encodeComponent(c.name)}');
                    },
                  ),
              ],
            );
    } else {
      body = Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 8, AppSpacing.lg, 4),
              children: [
                for (final (value, label) in const [
                  (SearchSort.relevance, '정확도'),
                  (SearchSort.latest, '최신'),
                  (SearchSort.popular, '인기'),
                ])
                  _TagChip(
                    key: ValueKey('search_sort_${value.name}'),
                    label: label,
                    plain: true,
                    selected: _sort == value,
                    onTap: () => setState(() => _sort = value),
                  ),
              ],
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? Center(child: Text("'$q'에 맞는 말랑이가 없어요", style: AppTextStyles.systemNotice))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 88),
                    itemBuilder: (context, i) => GalleryRow(item: results[i], onOpen: () => _remember(q)),
                  ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          onSubmitted: _remember,
          decoration: InputDecoration(
            hintText: '이름, #태그, 만든 사람',
            isDense: true,
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    tooltip: '지우기',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(_query.clear),
                  ),
          ),
        ),
        bottom: q.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(46),
                child: Row(
                  children: [
                    _SearchTab(
                      key: const ValueKey('search_tab_mallang'),
                      label: '말랑이 ${results.length}',
                      on: !_creators,
                      onTap: () => setState(() => _creators = false),
                    ),
                    _SearchTab(
                      key: const ValueKey('search_tab_creator'),
                      label: '제작자 ${creators.length}',
                      on: _creators,
                      onTap: () => setState(() => _creators = true),
                    ),
                  ],
                ),
              ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: AppSpacing.pageConstraints(context, maxDesktop: 840),
          child: body,
        ),
      ),
    );
  }
}

/// 검색 결과 위 말랑이/제작자 탭 한 칸
class _SearchTab extends StatelessWidget {
  const _SearchTab({super.key, required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: on ? AppColors.primaryPink : AppColors.borderLight, width: on ? 2 : 1)),
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
      ),
    );
  }
}

/// 검색·제작자 화면의 한 줄 (사진 + 이름 + 한줄 소개 + 만든 사람)
class GalleryRow extends StatelessWidget {
  const GalleryRow({super.key, required this.item, this.showCreator = true, this.onOpen});

  final GalleryItem item;
  final bool showCreator;

  /// 누르기 직전에 할 일 (검색어 기억하기 등)
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = item.character;
    return InkWell(
      onTap: () {
        onOpen?.call();
        context.push('/gallery/${c.id}');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(width: 60, height: 72, child: CharacterImage(character: c, fontSize: 28)),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: AppTextStyles.appBarTitle.copyWith(fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(taglineOf(c), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.systemNotice),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (showCreator && item.creator != null) ...[
                        Flexible(child: CreatorLine(creator: item.creator!, avatarUrl: item.creatorAvatar, mine: item.mine, size: 16)),
                        const SizedBox(width: 8),
                      ],
                      if (item.friends > 0) Text('친구 ${item.friends}', style: AppTextStyles.messageTime),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [초보자 노트] 제작자 프로필 (/creator/닉네임): 그 사람이 올린 말랑이를 2열 카드로 모아 봐요 (최신·인기 정렬).
class CreatorScreen extends ConsumerStatefulWidget {
  const CreatorScreen({super.key, required this.creator});

  final String creator;

  @override
  ConsumerState<CreatorScreen> createState() => _CreatorScreenState();
}

class _CreatorScreenState extends ConsumerState<CreatorScreen> {
  GallerySort _sort = GallerySort.latest;

  @override
  Widget build(BuildContext context) {
    final creator = widget.creator;
    final all = ref.watch(galleryProvider).valueOrNull ?? const <GalleryItem>[];
    final friendIds = ref.watch(characterLibraryProvider).map((e) => e.id).toSet();
    final items = all.where((g) => g.creator == creator).toList()
      ..sort(_sort == GallerySort.latest ? _byLatest : _byPopular);
    final friends = items.fold(0, (sum, g) => sum + g.friends);
    // 사진·소개는 그 사람의 계정 프로필을 그대로 따라와요 (어느 말랑이에 실려 와도 같은 값)
    final avatar = items.map((g) => g.creatorAvatar).firstWhere((a) => a.isNotEmpty, orElse: () => '');
    final intro = items.map((g) => g.creatorIntro).firstWhere((a) => a.isNotEmpty, orElse: () => '');
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 980
        ? 4
        : width >= 680
            ? 3
            : 2;

    return Scaffold(
      appBar: AppBar(title: const Text('제작자')),
      body: Center(
        child: ConstrainedBox(
          constraints: AppSpacing.pageConstraints(context, maxDesktop: 840),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      CreatorAvatar(name: creator, avatarUrl: avatar, size: 64),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(creator, style: AppTextStyles.appBarTitle.copyWith(fontSize: 20)),
                            if (intro.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(intro, style: AppTextStyles.systemNotice.copyWith(color: AppColors.textSecondary)),
                            ],
                            const SizedBox(height: 4),
                            Text('만든 말랑이 ${items.length} · 받은 친구 추가 $friends', style: AppTextStyles.messageTime),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _SectionTitle(
                '만든 말랑이',
                trailing: SegmentedButton<GallerySort>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  segments: const [
                    ButtonSegment(value: GallerySort.latest, label: Text('최신')),
                    ButtonSegment(value: GallerySort.popular, label: Text('인기')),
                  ],
                  selected: {_sort},
                  onSelectionChanged: (s) => setState(() => _sort = s.first),
                ),
              ),
              if (items.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: Text('공개한 말랑이가 없어요', style: AppTextStyles.systemNotice)),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: AppSpacing.md,
                      crossAxisSpacing: AppSpacing.md,
                      childAspectRatio: width >= 680 ? 0.66 : 0.62,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      return GalleryCard(
                        character: item.character,
                        mine: item.mine,
                        isFriend: friendIds.contains(item.character.id),
                        friends: item.friends,
                        onTap: () => context.push('/gallery/${item.character.id}'),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 알림(종): 말랑이들이 보낸 안 읽은 톡을 모아 보여 줌. 누르면 그 대화방으로 (와이어프레임 1-1)
class _AlertBell extends ConsumerWidget {
  const _AlertBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(chatRoomsProvider);
    final unread = [
      for (final id in rooms)
        if (ref.watch(chatRoomProvider(id).select((s) => s.unreadCount)) > 0) id
    ];
    final total = unread.fold<int>(0, (n, id) => n + ref.read(chatRoomProvider(id)).unreadCount);
    return IconButton(
      key: const ValueKey('alert_bell'),
      tooltip: '알림',
      onPressed: () => _open(context, ref, unread),
      icon: Badge(
        isLabelVisible: total > 0,
        label: Text('$total'),
        backgroundColor: AppColors.primaryPink,
        child: Icon(total > 0 ? Icons.notifications_rounded : Icons.notifications_none_rounded),
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref, List<String> unread) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceWhite,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('알림', style: AppTextStyles.appBarTitle),
              const SizedBox(height: 8),
              if (unread.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('새로 온 톡이 없어요', textAlign: TextAlign.center, style: AppTextStyles.systemNotice),
                ),
              for (final id in unread)
                Builder(builder: (_) {
                  final room = ref.read(chatRoomProvider(id));
                  final last = room.lastBubble;
                  return ListTile(
                    key: ValueKey('alert_$id'),
                    contentPadding: EdgeInsets.zero,
                    leading: CharacterAvatar(character: room.character, radius: 22),
                    title: Text(isFreeRoom(id) ? '${room.character.name} · 자유대화' : room.character.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      last == null ? '' : (last.hasPhoto && last.text.isEmpty ? '사진' : last.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.messageTime,
                    ),
                    trailing: Badge(
                      label: Text('${room.unreadCount}'),
                      backgroundColor: AppColors.primaryPink,
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      openChat(context, room.character, roomId: id);
                    },
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}
