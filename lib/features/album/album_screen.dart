import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/widgets/cutscene_view.dart';
import '../chat/chat_notifier.dart';

/// [초보자 노트] 지금까지 모은 컷씬(CG)을 모아 보는 앨범 화면입니다.
/// 아직 못 본 장면은 제목을 가린 채 자물쇠로 보여줘서 "더 모으고 싶게" 만듭니다.
class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({super.key});

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  ScenarioEventModel? _viewing;

  @override
  Widget build(BuildContext context) {
    final bundle = ref.watch(scenarioBundleProvider).requireValue;
    final unlocked = ref.watch(
      chatRoomProvider.select((s) => s.unlockedCutsceneEventIds),
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
  final bool isUnlocked;
  final VoidCallback onTap;

  const _AlbumTile({
    required this.event,
    required this.isUnlocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
