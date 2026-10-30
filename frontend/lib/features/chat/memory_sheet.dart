import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/utils/korean.dart';

/// 대화방 로어북: 대화가 끝날 때마다 캐릭터가 남긴 기억([제목][세부사항])을 유저가 보고 고치고 지우고 더함.
/// 바뀔 때마다 [onChanged]로 바로 저장. AI에겐 최근 5개 + 지금 대화와 관련된 옛 기억이 넘어감
Future<void> showMemorySheet(
  BuildContext context, {
  required String characterName,
  required List<String> memories,
  required ValueChanged<List<String>> onChanged,
}) =>
    showDialog<void>(
      context: context,
      builder: (context) => _MemoryDialog(
          characterName: characterName, memories: memories, onChanged: onChanged),
    );

class _MemoryDialog extends StatefulWidget {
  const _MemoryDialog(
      {required this.characterName,
      required this.memories,
      required this.onChanged});

  final String characterName;
  final List<String> memories;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_MemoryDialog> createState() => _MemoryDialogState();
}

class _MemoryDialogState extends State<_MemoryDialog> {
  late final List<MemoryNote> _items = [
    for (final m in widget.memories) MemoryNote.parse(m)
  ];

  void _save() => widget.onChanged([for (final m in _items) m.encode()]);

  /// [index]가 null이면 새 기억 추가
  Future<void> _edit(int? index) async {
    final old = index == null ? const MemoryNote() : _items[index];
    final title = TextEditingController(text: old.title);
    final detail = TextEditingController(text: old.detail);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(index == null ? '기억 추가' : '기억 고치기'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('memory_title_field'),
                controller: title,
                autofocus: true,
                maxLines: 1,
                decoration: const InputDecoration(
                  hintText: '제목 (예: 고양이 알레르기)',
                  prefixIcon: Icon(Icons.sell_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('memory_edit_field'),
                controller: detail,
                minLines: 3,
                maxLines: null,
                decoration: const InputDecoration(
                    hintText: '세부사항 (예: 내가 고양이 알레르기가 있어서 루나를 만지면 재채기한다고 했다)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('저장')),
        ],
      ),
    );
    if (ok != true) return;
    final note = MemoryNote(title: title.text.trim(), detail: detail.text.trim());
    if (note.title.isEmpty && note.detail.isEmpty) return;
    setState(() => index == null ? _items.add(note) : _items[index] = note);
    _save();
  }

  void _delete(int index) {
    setState(() => _items.removeAt(index));
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('로어북', style: AppTextStyles.appBarTitle)),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  '대화가 끝날 때마다 ${josa(widget.characterName, '이', '가')} 남긴 기억이에요. '
                  '핀이 꽂힌 최근 5개는 늘, 그 전 기억은 대화에 관련된 말이 나오면 떠올려요',
                  style: AppTextStyles.messageTime,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: _items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('아직 남은 기억이 없어요',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.messageTime),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _items.length,
                        // 최근 기억이 위로
                        itemBuilder: (context, i) => _card(_items.length - 1 - i),
                      ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('memory_add'),
                  onPressed: () => _edit(null),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('기억 추가'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 기억 한 개: 위 [제목] + 버튼, 아래 [세부사항]
  Widget _card(int index) {
    final m = _items[index];
    final recent = index >= _items.length - 5;
    return Container(
      key: ValueKey('memory_$index'),
      margin: const EdgeInsets.only(bottom: 8, right: 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 0, 12),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(recent ? Icons.push_pin_rounded : Icons.bookmark_border_rounded,
                  size: 16, color: recent ? AppColors.primaryPink : AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(m.title.isEmpty ? '제목 없음' : m.title,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: m.title.isEmpty ? AppColors.textMuted : AppColors.textPrimary)),
              ),
              IconButton(
                tooltip: '고치기',
                visualDensity: VisualDensity.compact,
                onPressed: () => _edit(index),
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              IconButton(
                tooltip: '지우기',
                visualDensity: VisualDensity.compact,
                onPressed: () => _delete(index),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(m.detail, style: const TextStyle(fontSize: 14, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
