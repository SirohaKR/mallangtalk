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

/// 로어북 키워드·옛 기억을 찾을 글: 지금 장면의 최근 말 몇 개 + 방금 보낸 톡
String recentTextForRecall(
        List<ChatMessageLog> history, List<String> newUserMessages) =>
    [
      for (final m in activeConversation(history).reversed.take(8))
        if (!m.isSystem) '${m.text} ${m.photoLabel ?? ''}',
      ...newUserMessages,
    ].join('\n');

/// 한 줄 기억 중 AI에게 넘길 것: 최근 [recent]개는 늘, 그 전 기억은 지금 대화에 같은 낱말이 나올 때만 (최대 [related]개)
List<String> recallMemories(List<String> memories, String text,
    {int recent = 5, int related = 5, Set<String> ignore = const {}}) {
  if (memories.length <= recent) return memories;
  final cut = memories.length - recent;
  final older = memories.take(cut).toList();
  final picked = [
    for (final m in older.reversed)
      if (_sharesWord(m, text, ignore)) m,
  ].take(related).toSet();
  return [
    for (final m in older)
      if (picked.contains(m)) m,
    ...memories.skip(cut),
  ];
}

/// 너무 흔해서 기억을 꺼낼 단서가 안 되는 말
const _commonWords = {
  '오늘', '어제', '내일', '우리', '같이', '그냥', '진짜', '너무', '정말', '조금', '많이',
  '유저', '대화', '이야기', '얘기', '서로', '함께', '그리고', '하지만', '했다', '했음',
  '나눴다', '말했다', '좋아', '좋다', '있다', '없다', '했던', '하는', '하고',
};

/// 낱말 끝에 붙는 조사 (긴 것부터 떼어 봄)
const _particles = [
  '에서는', '한테서', '으로는', '이랑', '에서', '에게', '한테', '으로', '까지', '부터',
  '처럼', '보다', '이랑', '하고', '은', '는', '이', '가', '을', '를', '에', '도', '와',
  '과', '랑', '의', '로', '만',
];

String _stem(String word) {
  for (final p in _particles) {
    if (word.length - p.length >= 2 && word.endsWith(p)) {
      return word.substring(0, word.length - p.length);
    }
  }
  return word;
}

bool _sharesWord(String memory, String text, Set<String> ignore) {
  final lower = text.toLowerCase();
  for (final raw in memory.toLowerCase().split(RegExp(r'[^0-9a-z가-힣]+'))) {
    final w = _stem(raw);
    if (w.length < 2 || _commonWords.contains(w) || ignore.contains(w)) {
      continue;
    }
    if (lower.contains(w)) return true;
  }
  return false;
}
