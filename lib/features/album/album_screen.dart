import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/widgets/character_avatar.dart';
import '../../shared/widgets/cutscene_view.dart';
import '../chat/chat_notifier.dart';
import '../library/character_library.dart';

/// [초보자 노트] 지금까지 모은 컷씬(CG)을 모아 보는 앨범 화면입니다.
/// 아직 못 본 장면은 제목을 가린 채 자물쇠로 보여줘서 "더 모으고 싶게" 만듭니다.
class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({super.key, required this.characterId});

  final String characterId;

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  ScenarioEventModel? _viewing;

  @override
  Widget build(BuildContext context) {
    final bundle = ref.watch(characterBundleProvider(widget.characterId));
    if (bundle == null) {
      return const Scaffold(body: Center(child: Text('캐릭터를 찾을 수 없어요')));
    }
    final unlocked = ref.watch(
      chatRoomProvider(widget.characterId).select((s) => s.unlockedCutsceneEventIds),
    );
    final cutsceneEvents = bundle.events.where((e) => e.hasCutscene).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('${bundle.character.name} 앨범 '
            '${unlocked.length}/${cutsceneEvents.length}'),
      ),
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppSpacing.mobileMaxWidth),
              child: GridView.count(
                padding: const EdgeInsets.all(AppSpacing.lg),
                crossAxisCount: 2,
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: 0.78,
                children: [
                  for (final event in cutsceneEvents)
                    _AlbumTile(
                      event: event,
                      imageUrl: bundle.resolveImage(event.cutsceneImageUrl),
                      isUnlocked: unlocked.contains(event.id),
                      onTap: () => setState(() => _viewing = event),
                    ),
                ],
              ),
            ),
          ),
          if (_viewing != null)
            CutsceneView(
              event: _viewing!,
              imageUrl: bundle.resolveImage(_viewing!.cutsceneImageUrl),
              footer: '화면을 탭하면 닫혀요',
              onClose: () => setState(() => _viewing = null),
            ),
        ],
      ),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  final ScenarioEventModel event;
  /// 컷씬 진짜 사진 (모은 뒤에만 썸네일로 보여 줌)
  final String? imageUrl;
  final bool isUnlocked;
  final VoidCallback onTap;

  const _AlbumTile({
    required this.event,
    this.imageUrl,
    required this.isUnlocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final photo = isUnlocked ? CharacterImage.providerFor(imageUrl ?? '') : null;
    if (photo != null) {
      return GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(image: photo, fit: BoxFit.cover),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Text(
                    event.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.messageTime.copyWith(color: AppColors.surfaceWhite),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: isUnlocked ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isUnlocked ? AppColors.primaryNavy : AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isUnlocked ? Icons.auto_awesome_rounded : Icons.lock_rounded,
              size: 32,
              color: isUnlocked ? AppColors.myBubble : AppColors.textMuted,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              isUnlocked ? event.title : '???',
              textAlign: TextAlign.center,
              style: AppTextStyles.choiceButton.copyWith(
                color: isUnlocked ? AppColors.surfaceWhite : AppColors.textMuted,
              ),
            ),
            if (isUnlocked && event.cutscenePhotoTitle != null) ...[
              const SizedBox(height: 6),
              Text(
                event.cutscenePhotoTitle!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.messageTime.copyWith(color: AppColors.borderLight),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
