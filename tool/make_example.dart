// 받아오기 갤러리의 예시 캐릭터(서이준) 파일을 다시 만드는 스크립트: dart run tool/make_example.dart
// (만들기 화면의 '예시 캐릭터 불러오기'와 같은 내용)
import 'dart:convert';
import 'dart:io';
import 'package:mallangtalk/features/studio/template_scenario.dart';

void main() {
  final json = File('assets/scenarios/example_seo_ijun.json');
  json.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(templateScenario().toJson()));
  stdout.writeln('저장: ${json.path}');
}
