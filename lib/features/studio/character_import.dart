import 'dart:convert';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/utils/file_io.dart';

/// 캐릭터 파일(.json)을 시나리오로 바꿉니다. 형식이 틀리면 FormatException
ScenarioBundle readCharacterFile(PickedFile file) {
  try {
    final json = jsonDecode(utf8.decode(file.bytes)) as Map<String, dynamic>;
    final bundle = ScenarioBundle.fromJson(json);
    if (bundle.character.name.isEmpty || bundle.events.isEmpty) throw const FormatException();
    return bundle;
  } catch (_) {
    throw const FormatException('말랑톡 캐릭터 파일(.json)이 아니거나 내용이 깨졌어요.');
  }
}

/// 캐릭터 한 명 분량 요약 (미리보기 카드용)
class ScenarioSummary {
  final int stages;
  final int storyEvents;
  final int dailyTalks;
  final int specials;
  final int cutscenes;
  final int bubbles;
  final bool hasEnding;

  const ScenarioSummary({
    required this.stages,
    required this.storyEvents,
    required this.dailyTalks,
    this.specials = 0,
    required this.cutscenes,
    required this.bubbles,
    required this.hasEnding,
  });

  factory ScenarioSummary.of(ScenarioBundle bundle) => ScenarioSummary(
        stages: bundle.character.affectionStages.length,
        storyEvents: bundle.events.where((e) => e.isAffectionEvent).length,
        dailyTalks: bundle.events.where((e) => e.isDaily).length,
        specials: bundle.events.where((e) => e.isSpecial).length,
        cutscenes: bundle.events.where((e) => e.hasCutscene && !e.isDaily).length,
        bubbles: bundle.nodes.values.fold(
          0,
          (sum, n) => sum + n.characterBubbles.length + n.choices.fold(0, (s, c) => s + c.userBubbles.length),
        ),
        hasEnding: bundle.events.any((e) => e.isEnding),
      );

  String get line =>
      '호감도 단계 $stages개 · 이벤트 $storyEvents개 · 일상 대화 $dailyTalks개${specials > 0 ? ' · 특별 이벤트 $specials개' : ''} · 컷씬 $cutscenes장 · 말풍선 $bubbles개${hasEnding ? ' · 엔딩 있음' : ''}';
}
