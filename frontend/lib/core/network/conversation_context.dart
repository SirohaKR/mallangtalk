import '../../shared/models/mallangtalk_models.dart';
import '../../shared/utils/dialogue_input.dart';

List<ChatMessageLog> activeConversation(List<ChatMessageLog> history) => history
    .skip(history.lastIndexWhere((m) => m.isConversationBreak) + 1)
    .toList();

String conversationTranscript(
    List<ChatMessageLog> history, String userName, String characterName) {
  String lines(Iterable<ChatMessageLog> messages) =>
      messages.where((m) => !m.isSystem).map((m) {
        final who = m.isUser ? userName : characterName;
        final text = m.isUser ? dialogueInputForAi(m.text) : m.text;
        final photo = m.hasPhoto ? ' [사진: ${m.photoLabel}]' : '';
        return '$who: ${m.replyToText == null ? '' : '[${m.replyToName}의 말에 답장: ${m.replyToText}] '}$text$photo';
      }).join('\n');
  final boundary = history.lastIndexWhere((m) => m.isConversationBreak);
  if (boundary < 0) return lines(history.reversed.take(30).toList().reversed);
  final old = lines(
      history.take(boundary).toList().reversed.take(10).toList().reversed);
  final current =
      lines(activeConversation(history).reversed.take(30).toList().reversed);
  return '[종료된 이전 대화 — 배경 기억용, 현재 진행 중인 장면 아님]\n$old\n\n'
      '[대화 구분: 이전 장면 종료. 여기부터 새 장면]\n'
      '[현재 장면]\n${current.isEmpty ? '아직 대화 없음. 방금 유저가 보낸 톡에서 새로 시작한다.' : current}';
}
