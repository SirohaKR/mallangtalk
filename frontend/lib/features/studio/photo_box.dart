import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/utils/file_io.dart';
import '../../shared/widgets/character_avatar.dart';
import 'scenario_draft.dart';
import 'studio_widgets.dart';

/// 8단계 캐릭터 사진함: 이 캐릭터의 사진을 한곳에 올리고, 사진마다 설명·스토리에만/자유대화에도·보낼 때를 정함.
/// 대본의 컷씬·사진 말풍선은 여기서 골라 쓰고, 설명이 같으면 저절로 붙음
class CharacterPhotoBox extends StatefulWidget {
  const CharacterPhotoBox({super.key, required this.draft, required this.onChanged, required this.onOpenEvent});

  final ScenarioDraft draft;

  /// 사진함이 바뀌면 (편집기 다시 그리기·임시 저장)
  final VoidCallback onChanged;

  /// '…에서 씀'을 누르면 그 대화의 대사 편집으로
  final ValueChanged<EventDraft> onOpenEvent;

  @override
  State<CharacterPhotoBox> createState() => _CharacterPhotoBoxState();
}

class _CharacterPhotoBoxState extends State<CharacterPhotoBox> {
  String? _selected;
  final _keyword = TextEditingController();

  static const moods = ['기쁨', '설렘', '장난', '자신만만', '뿌듯함', '다정', '서운함', '질투', '걱정', '피곤함', '심심함'];

  ScenarioDraft get d => widget.draft;

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  void _update(String image, PhotoTrigger Function(PhotoTrigger t) change) {
    setState(() => d.photoTriggers[image] = change(d.photoTriggers[image] ?? const PhotoTrigger()));
    widget.onChanged();
  }

  Future<void> _add() async {
    final picked = await pickPhoto(context);
    if (picked == null || !mounted) return;
    setState(() {
      d.addPhoto(picked);
      _selected = picked;
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final photos = d.photos;
    final selected = photos.contains(_selected) ? _selected : photos.firstOrNull;
    final free = photos.where((p) => d.photoTriggers[p]?.isSet ?? false).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${d.name.trim().isEmpty ? '캐릭터' : d.name.trim()} 사진함', style: AppTextStyles.choiceButton),
                  Text('${photos.length}장 · 자유대화용 $free장', style: AppTextStyles.messageTime),
                ],
              ),
            ),
            IconButton.filledTonal(
              key: const ValueKey('photo_box_add'),
              tooltip: '사진 올리기',
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '이 캐릭터의 사진을 여기 다 올려요. 대본의 컷씬·사진 말풍선은 여기서 골라 쓰고, 설명이 같으면 저절로 붙어요.',
          style: AppTextStyles.messageTime,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (photos.isEmpty)
          OutlinedButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('첫 사진 올리기'),
          )
        else
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (final p in photos) _thumb(p, p == selected),
            ],
          ),
        if (selected != null) ...[
          const SizedBox(height: AppSpacing.md),
          _detail(selected),
        ],
      ],
    );
  }

  Widget _thumb(String image, bool isSelected) {
    final provider = CharacterImage.providerFor(image);
    final t = d.photoTriggers[image];
    final used = d.slotsUsing(image).isNotEmpty;
    return GestureDetector(
      key: ValueKey('photo_box_${ScenarioDraft.imageId(image)}'),
      onTap: () => setState(() => _selected = image),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? AppColors.primaryPink : Colors.transparent, width: 2.5),
        ),
        padding: const EdgeInsets.all(2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (provider != null)
                Image(image: provider, fit: BoxFit.cover)
              else
                const ColoredBox(color: AppColors.borderLight),
              if (t?.isSet ?? false)
                const Positioned(
                  left: 3,
                  bottom: 3,
                  child: CircleAvatar(
                    radius: 9,
                    backgroundColor: Color(0xFFF2B13C),
                    child: Icon(Icons.bolt_rounded, size: 13, color: Colors.white),
                  ),
                ),
              if (!used)
                Positioned(
                  right: 3,
                  top: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                    child: const Text('안 씀', style: TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(String image) {
    final t = d.photoTriggers[image] ?? const PhotoTrigger();
    final slots = d.slotsUsing(image);
    final events = {for (final s in slots) s.event}.toList();
    final id = ScenarioDraft.imageId(image);
    final provider = CharacterImage.providerFor(image);
    final picked = {
      for (final m in t.mood.split(RegExp(r'[,，]')))
        if (m.trim().isNotEmpty) m.trim()
    };
    final free = !t.storyOnly;
    return StudioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (provider != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image(image: provider, width: 88, height: 110, fit: BoxFit.cover),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EditField(
                      fieldKey: 'photo_caption_$id',
                      value: t.caption.isEmpty ? d.captionOf(image) : t.caption,
                      hint: '사진 설명 (예: 책 들고 웃는 셀카)',
                      dense: true,
                      onChanged: (v) => _update(image, (t) => t.copyWith(caption: v)),
                    ),
                    const SizedBox(height: 4),
                    if (events.isEmpty)
                      const Text('아직 대본에 안 썼어요. 사진 말풍선 설명을 같게 적으면 저절로 붙어요', style: AppTextStyles.messageTime)
                    else
                      Wrap(
                        spacing: 2,
                        children: [
                          for (final e in events)
                            TextButton(
                              style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 30)),
                              onPressed: () => widget.onOpenEvent(e),
                              child: Text('· ${e.title.trim().isEmpty ? '(제목 없음)' : e.title.trim()}에서 씀',
                                  style: AppTextStyles.messageTime),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<bool>(
            key: const ValueKey('photo_box_free'),
            segments: const [
              ButtonSegment(value: false, label: Text('스토리에만')),
              ButtonSegment(value: true, label: Text('자유대화에도')),
            ],
            selected: {free},
            showSelectedIcon: false,
            onSelectionChanged: (v) => _update(image, (t) => t.copyWith(storyOnly: !v.first)),
          ),
          if (free) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text('감정 (여러 개)', style: AppTextStyles.speakerName),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in {...moods, ...picked})
                  StudioPill(
                    label: m,
                    selected: picked.contains(m),
                    onTap: () => _update(image, (t) {
                      final next = {...picked};
                      if (!next.remove(m)) next.add(m);
                      return t.copyWith(mood: next.join(', '));
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            EditField(
              fieldKey: 'photo_situation_$id',
              value: t.situation,
              label: '이럴 때 보내요',
              hint: '예: {{user}}를 놀리거나 도서관에 오라고 꼬실 때',
              onChanged: (v) => _update(image, (t) => t.copyWith(situation: v)),
            ),
            const Text('키워드', style: AppTextStyles.speakerName),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final k in t.keywords)
                  InputChip(
                    label: Text(k),
                    onDeleted: () => _update(image, (t) => t.copyWith(keywords: [...t.keywords]..remove(k))),
                  ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    key: const ValueKey('photo_box_keyword'),
                    controller: _keyword,
                    decoration: const InputDecoration(isDense: true, hintText: '＋ 키워드'),
                    onSubmitted: (v) {
                      final words = [
                        for (final w in v.split(RegExp(r'[,，]')))
                          if (w.trim().isNotEmpty && !t.keywords.contains(w.trim())) w.trim(),
                      ];
                      _keyword.clear();
                      if (words.isNotEmpty) _update(image, (t) => t.copyWith(keywords: [...t.keywords, ...words]));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              t.isSet ? 'AI는 대화 흐름이 감정·상황과 맞을 때만 이 사진을 보내요. 받은 사진은 앨범에 들어가요.' : '감정·상황·키워드 중 하나는 정해야 자유대화에서 보내요.',
              style: AppTextStyles.messageTime,
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('photo_box_remove'),
              onPressed: () {
                setState(() {
                  d.removePhoto(image);
                  _selected = null;
                });
                widget.onChanged();
              },
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(slots.isEmpty ? '사진 빼기' : '사진 빼기 (쓰던 ${slots.length}곳도 비워요)'),
            ),
          ),
        ],
      ),
    );
  }
}
