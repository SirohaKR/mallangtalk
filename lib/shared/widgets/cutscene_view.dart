import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../models/mallangtalk_models.dart';

/// 컷씬(CG) 전체 화면 팝업. 이미지 경로가 있으면 이미지를, 없으면 장면 제목 카드를 보여줍니다.
class CutsceneView extends StatelessWidget {
  final ScenarioEventModel event;
  final String footer;
  final VoidCallback onClose;

  const CutsceneView({
    super.key,
    required this.event,
    required this.footer,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = event.cutsceneImageUrl;
    final placeholder = Container(
      height: 320,
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryNavy,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome_rounded, size: 44, color: AppColors.myBubble),
          const SizedBox(height: 14),
          Text(
            event.cutscenePhotoTitle ?? event.title,
            textAlign: TextAlign.center,
            style: AppTextStyles.chatBubbleBody.copyWith(color: AppColors.surfaceWhite),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onClose,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.96),
        child: SafeArea(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: AppSpacing.mobileMaxWidth),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    event.title,
                    style: AppTextStyles.appBarTitle.copyWith(color: AppColors.myBubble),
                  ),
                  const SizedBox(height: 16),
                  if (imageUrl != null && imageUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => placeholder,
                      ),
                    )
                  else
                    placeholder,
                  const SizedBox(height: 16),
                  Text(
                    footer,
                    style: AppTextStyles.messageTime.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
