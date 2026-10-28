import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/widgets/character_avatar.dart';
import '../../shared/widgets/photo_viewer.dart';
import '../chat/chat_notifier.dart';
import '../chat/chat_theme.dart';
import '../library/character_library.dart';

/// [초보자 노트] 캐릭터에게 받은 사진을 모아 보는 앨범 화면입니다.
/// 사진 말풍선과 컷씬을 구분하지 않고 전부 여기에 들어가요. 호감도 단계별로 묶어 보여 주고,
/// 아직 못 받은 사진은 자물쇠 칸으로 남겨서 "더 모으고 싶게" 만듭니다.
class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({super.key, required this.characterId});

  final String characterId;

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  @override
  Widget build(BuildContext context) {
    final bundle = ref.watch(characterBundleProvider(widget.characterId));
    if (bundle == null) {
      return const Scaffold(body: Center(child: Text('캐릭터를 찾을 수 없어요')));
    }
    final received = ref.watch(chatRoomProvider(widget.characterId).select((s) => s.receivedPhotos)).toSet();
    final theme = ChatTheme.of(bundle.character);
    final all = bundle.albumPhotos;
    // 호감도 단계 순서대로 묶음 (단계에 없는 묶음은 맨 뒤)
    final stageOrder = [for (final s in bundle.character.affectionStages) s.stageLabel];
    int rank(String g) => stageOrder.contains(g) ? stageOrder.indexOf(g) : stageOrder.length;
    final byGroup = <String, List<AlbumPhoto>>{};
    for (final p in all) {
      (byGroup[p.group] ??= []).add(p);
    }
    final keys = byGroup.keys.toList();
    final groups = {
      for (final k in keys.toList()..sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : keys.indexOf(a) - keys.indexOf(b)))
        k: byGroup[k]!,
    };
    final got = [for (final g in groups.values) ...g.where((p) => received.contains(p.label))];

    return Scaffold(
      appBar: AppBar(title: Text('${bundle.character.name}의 앨범')),
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: AppSpacing.pageConstraints(context, maxDesktop: 920),
              child: all.isEmpty
                  ? const Center(child: Text('이 말랑이는 아직 보내는 사진이 없어요', style: AppTextStyles.systemNotice))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
                      children: [
                        Row(
                          children: [
                            const Expanded(child: Text('받은 사진', style: AppTextStyles.appBarTitle)),
                            Text('${got.length} / ${all.length}장', style: AppTextStyles.systemNotice),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: got.length / all.length,
                            minHeight: 6,
                            color: theme.accent,
                            backgroundColor: AppColors.borderLight,
                          ),
                        ),
                        for (final entry in groups.entries) ...[
                          const SizedBox(height: AppSpacing.lg),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Expanded(child: Text(entry.key, style: AppTextStyles.choiceButton)),
                              Text(
                                '${entry.value.where((p) => received.contains(p.label)).length} / ${entry.value.length}',
                                style: AppTextStyles.messageTime,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: MediaQuery.sizeOf(context).width >= 860 ? 5 : MediaQuery.sizeOf(context).width >= 640 ? 4 : 3,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                            childAspectRatio: 3 / 4,
                            children: [
                              for (final photo in entry.value)
                                received.contains(photo.label)
                                    ? _PhotoTile(
                                        photo: photo,
                                        accent: theme.accent,
                                        onTap: () => showPhotoViewer(
                                          context,
                                          accent: theme.accent,
                                          initialIndex: got.indexOf(photo),
                                          items: [
                                            for (final p in got)
                                              PhotoViewerItem(
                                                  label: p.label, image: p.image, chip: p.group, caption: p.event.title),
                                          ],
                                        ),
                                      )
                                    : const _LockedTile(),
                            ],
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, required this.accent, required this.onTap});

  final AlbumPhoto photo;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = CharacterImage.providerFor(photo.image ?? '');
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: image != null
            ? Image(image: image, fit: BoxFit.cover, alignment: const Alignment(0, -0.6), semanticLabel: photo.label)
            : Container(
                padding: const EdgeInsets.all(8),
                color: Color.lerp(AppColors.surfaceWhite, accent, 0.14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.photo_camera_back_rounded, size: 24, color: accent),
                    const SizedBox(height: 6),
                    Text(
                      photo.label,
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.messageTime.copyWith(color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _LockedTile extends StatelessWidget {
  const _LockedTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFE6EA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_rounded, size: 20, color: AppColors.textSecondary),
          SizedBox(height: 4),
          Text('아직 못 받은 사진',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
