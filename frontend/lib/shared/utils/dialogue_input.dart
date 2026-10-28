/// Whole-message delimiters mean stage direction; ordinary inline parentheses
/// remain spoken text. Delimiters are kept in saved messages.
String? stageDirectionOf(String input) {
  final text = input.trim();
  if (text.length < 3) return null;
  if ((text.startsWith('(') && text.endsWith(')')) ||
      (text.startsWith('*') && text.endsWith('*'))) {
    final body = text.substring(1, text.length - 1).trim();
    return body.isEmpty ? null : body;
  }
  return null;
}

String dialogueInputForAi(String input) {
  final direction =
      stageDirectionOf(input) ?? (isUnspokenAction(input) ? input : null);
  return direction == null ? input : '[유저 행동·상황 지시, 발화 아님: $direction]';
}

bool isUnspokenAction(String input) {
  final text =
      (stageDirectionOf(input) ?? input).replaceAll(RegExp(r'[\s.!…]'), '');
  return const {
    '답장하지않는다',
    '답장하지않기',
    '답장을하지않는다',
    '답하지않는다',
    '아무말도하지않는다',
    '침묵한다',
    '침묵하기',
    '읽고답장하지않는다',
    '이어서듣기',
    '계속듣기',
    '조용히듣기',
    '가만히듣기',
    '듣고있는다',
    '계속듣는다',
    '이어서듣는다'
  }.contains(text);
}
