/// [초보자 노트] 이름 뒤 조사를 받침에 맞게 붙여 줍니다. (서이준 → 서이준과, 윤도하 → 윤도하와)
/// 한글이 아닌 글자로 끝나면 받침 없는 쪽을 씁니다.
String josa(String word, String withFinal, String withoutFinal) {
  if (word.isEmpty) return withoutFinal;
  final code = word.codeUnitAt(word.length - 1);
  if (code < 0xAC00 || code > 0xD7A3) return word + withoutFinal;
  final hasFinal = (code - 0xAC00) % 28 != 0;
  return word + (hasFinal ? withFinal : withoutFinal);
}
