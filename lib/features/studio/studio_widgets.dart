import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';

/// 만들기 화면 공통 입력칸. 초안 객체의 값을 바로 바꿉니다.
/// fieldKey는 초안이 통째로 바뀌었을 때(AI 생성·불러오기) 칸 내용을 새로 채우려고 씀
class EditField extends StatelessWidget {
  const EditField({
    super.key,
    required this.fieldKey,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.lines = 1,
    this.maxLength,
    this.dense = false,
  });

  final Object fieldKey;
  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? hint;
  final int lines;
  final int? maxLength;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      key: ValueKey(fieldKey),
      initialValue: value,
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 6,
      maxLength: maxLength,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintMaxLines: 3,
        isDense: dense,
        counterText: maxLength == null ? null : '',
      ),
    );
    if (label == null) return field;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label!, style: AppTextStyles.speakerName),
          const SizedBox(height: 4),
          field,
        ],
      ),
    );
  }
}

/// 섹션 제목 + 설명
class StudioSection extends StatelessWidget {
  const StudioSection({super.key, required this.title, this.note, this.trailing});

  final String title;
  final String? note;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTextStyles.appBarTitle.copyWith(fontSize: 16))),
              if (trailing != null) trailing!,
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 2),
            Text(note!, style: AppTextStyles.systemNotice),
          ],
        ],
      ),
    );
  }
}

/// 흰 카드
class StudioCard extends StatelessWidget {
  const StudioCard({super.key, required this.child, this.highlight = false});

  final Widget child;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    // 안에 ListTile(체크박스·펼치기)이 있어서 배경은 Material로 칠함
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: AppColors.surfaceWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.choiceRadius),
          side: BorderSide(color: highlight ? AppColors.primaryPink : AppColors.borderLight),
        ),
        child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: child),
      ),
    );
  }
}

/// − 숫자 + 카운터
class StudioCounter extends StatelessWidget {
  const StudioCounter({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTextStyles.chatBubbleBody)),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline_rounded),
        ),
        SizedBox(width: 24, child: Text('$value', textAlign: TextAlign.center, style: AppTextStyles.appBarTitle)),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
      ],
    );
  }
}

/// 타자 스타일 고르기 + 예상 입력 시간 표시
class TypingStylePicker extends StatelessWidget {
  const TypingStylePicker({super.key, required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    // 채팅방과 같은 계산: 멈칫 0.5초 + (0.7초 + 글자당 0.15초)
    const sample = '오늘 뭐해? 나 방금 일어남';
    final seconds = (500 + 700 + sample.length * 150) * value / 1000;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final style in TypingStyle.all)
              StudioPill(
                label: style.label,
                selected: (style.multiplier - value).abs() < 0.01,
                onTap: () => onChanged(style.multiplier),
              ),
          ],
        ),
        Slider(
          value: value.clamp(0.5, 2.0),
          min: 0.5,
          max: 2.0,
          divisions: 30,
          activeColor: AppColors.primaryPink,
          onChanged: (v) => onChanged(double.parse(v.toStringAsFixed(2))),
        ),
        Text(
          '${TypingStyle.closest(value).note} · "$sample" 입력 중 약 ${seconds.toStringAsFixed(1)}초',
          style: AppTextStyles.messageTime.copyWith(height: 1.4),
        ),
      ],
    );
  }
}

class StudioPill extends StatelessWidget {
  const StudioPill({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.myBubble : AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.primaryPink : AppColors.borderLight),
        ),
        child: Text(label, style: AppTextStyles.choiceButton.copyWith(fontSize: 13)),
      ),
    );
  }
}

/// 긴 설정용 큰 입력칸: 남는 화면을 꽉 채우고, 아래에 글자 수를 보여 줌 (설정이 천 자를 넘어도 편하게)
class BigTextField extends StatefulWidget {
  const BigTextField({
    super.key,
    required this.fieldKey,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final Object fieldKey;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;

  @override
  State<BigTextField> createState() => _BigTextFieldState();
}

class _BigTextFieldState extends State<BigTextField> {
  late int _length = widget.value.characters.length;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: TextFormField(
            key: ValueKey(widget.fieldKey),
            initialValue: widget.value,
            expands: true,
            minLines: null,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            style: AppTextStyles.chatBubbleBody.copyWith(height: 1.6),
            decoration: InputDecoration(hintText: widget.hint, hintMaxLines: 6, alignLabelWithHint: true),
            onChanged: (v) {
              widget.onChanged(v);
              setState(() => _length = v.characters.length);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('$_length자', textAlign: TextAlign.right, style: AppTextStyles.messageTime),
        ),
      ],
    );
  }
}

/// 사진 자리 상태: 사진 고름 / 같은 설명 사진이 나옴 / 사진함에 사진은 있는데 안 고름 / 설명 카드
enum PhotoState { filled, shared, missing, card }

/// 사진이 있는지 한눈에 보이는 작은 꼬리표 (이벤트 카드·대사 탭)
class PhotoTag extends StatelessWidget {
  const PhotoTag({super.key, required this.label, required this.state, this.icon});

  final String label;
  final PhotoState state;
  final IconData? icon;

  static Color colorOf(PhotoState state) => switch (state) {
        PhotoState.filled => AppColors.primaryPink,
        PhotoState.shared => AppColors.aiActivePurple,
        PhotoState.missing => AppColors.affectionWarm,
        PhotoState.card => AppColors.textMuted,
      };

  @override
  Widget build(BuildContext context) {
    final color = colorOf(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ??
                switch (state) {
                  PhotoState.filled || PhotoState.shared => Icons.image_rounded,
                  PhotoState.missing => Icons.warning_amber_rounded,
                  PhotoState.card => Icons.image_not_supported_outlined,
                },
            size: 13,
            color: color,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.messageTime.copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
