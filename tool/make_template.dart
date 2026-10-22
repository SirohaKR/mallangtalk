// 엑셀 대본 템플릿을 다시 만드는 스크립트: dart run tool/make_template.dart
// (앱의 '템플릿 받기' 버튼과 같은 파일을 templates/ 폴더에 저장)
import 'dart:convert';
import 'dart:io';
import 'package:mallangtalk/features/studio/script_workbook.dart';
import 'package:mallangtalk/features/studio/template_scenario.dart';

void main() {
  final file = File('templates/mallangtalk_script_template.xlsx')..createSync(recursive: true);
  file.writeAsBytesSync(ScriptWorkbook.encode(templateScenario()));
  stdout.writeln('저장: ${file.path} (${file.lengthSync()} bytes)');
  // 받아오기 갤러리에도 같은 예시 캐릭터를 넣어 둠
  final json = File('assets/scenarios/example_seo_ijun.json');
  json.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(templateScenario().toJson()));
  stdout.writeln('저장: ${json.path}');
}
