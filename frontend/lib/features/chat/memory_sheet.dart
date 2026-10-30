import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/utils/korean.dart';

/// 기억 노트: 대화가 끝날 때마다 캐릭터가 남긴 한 줄 기억을 유저가 보고 고치고 지우고 더함.
/// 바뀔 때마다 [onChanged]로 바로 저장. AI에겐 최근 5개 + 지금 대화와 관련된 옛 기억이 넘어감
Future<void> showMemorySheet(
  BuildContext context, {
  required String characterName,
  required List<String> memories,
  required ValueChanged<List<String>> onChanged,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _MemorySheet(
          characterName: characterName, memories: memories, onChanged: onChanged),
    );

class _MemorySheet extends StatefulWidget {
  const _MemorySheet(
      {required this.characterName,
      required this.memories,
      required this.onChanged});

  final String characterName;
  final List<String> memories;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_MemorySheet> createState() => _MemorySheetState();
}

class _MemorySheetState extends State<_MemorySheet> {
  late final List<String> _items = [...widget.memories];

  void _save() => widget.onChanged([..._items]);

  /// [index]가 null이면 새 기억 추가
  Future<void> _edit(int? index) async {
    final controller =
        TextEditingController(text: index == null ? '' : _items[index]);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(index == null ? '기억 추가' : '기억 고치기'),
        content: TextField(
          key: const ValueKey('memory_edit_field'),
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: null,
          decoration: const InputDecoration(
              hintText: '예) 내가 고양이 알레르기가 있다고 했다'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('저장')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    setState(() => index == null ? _items.add(text) : _items[index] = text);
    _save();
  }

  void _delete(int index) {
    setState(() => _items.removeAt(index));
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('기억 노트', style: AppTextStyles.appBarTitle),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '대화가 끝날 때마다 ${josa(widget.characterName, '이', '가')} 남긴 기억이에요. '
              '최근 5개는 늘, 그 전 기억은 대화에 관련된 말이 나오면 떠올려요. 고치거나 지울 수 있어요',
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
                : ListView.separated(
                    shrinkWrap: true,
                    // 최근 기억이 위로
                    itemCount: _items.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.borderLight),
                    itemBuilder: (context, i) {
                      final index = _items.length - 1 - i;
                      return ListTile(
                        key: ValueKey('memory_$index'),
                        contentPadding: const EdgeInsets.only(left: 4),
                        leading: index >= _items.length - 5
                            ? const Tooltip(
                                message: '최근 기억 (늘 떠올림)',
                                child: Icon(Icons.push_pin_rounded,
                                    size: 18, color: AppColors.primaryPink))
                            : const Icon(Icons.bookmark_border_rounded,
                                size: 18, color: AppColors.textMuted),
                        minLeadingWidth: 20,
                        title: Text(_items[index],
                            style: const TextStyle(fontSize: 14)),
                        onTap: () => _edit(index),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '고치기',
                              onPressed: () => _edit(index),
                              icon: const Icon(Icons.edit_outlined, size: 20),
                            ),
                            IconButton(
                              tooltip: '지우기',
                              onPressed: () => _delete(index),
                              icon: const Icon(Icons.delete_outline_rounded,
                                  size: 20),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
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
    );
  }
}
