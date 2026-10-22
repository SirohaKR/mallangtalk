import 'dart:typed_data';
import 'package:excel/excel.dart' as xl;
import '../../shared/models/mallangtalk_models.dart';

/// 엑셀 대본을 읽다가 고쳐야 할 곳이 있을 때
class ScriptWorkbookException implements Exception {
  final List<String> errors;
  const ScriptWorkbookException(this.errors);
  @override
  String toString() => errors.join('\n');
}

/// 엑셀 대본을 읽은 결과 (캐릭터 시나리오 + 고치면 좋은 점)
class ScriptWorkbookResult {
  final ScenarioBundle bundle;
  final List<String> warnings;
  const ScriptWorkbookResult(this.bundle, this.warnings);
}

/// [초보자 노트] 제작자가 엑셀로 모든 대사를 직접 쓰고 올릴 수 있게 해 주는 변환기입니다.
/// - encode: 캐릭터 시나리오 → 엑셀 파일 (템플릿 받기, AI가 만든 대본을 엑셀로 내보내 고치기)
/// - decode: 엑셀 파일 → 캐릭터 시나리오 (엑셀 대본 올리기)
/// 시트 구성: 설명 / 캐릭터 / 호감도단계 / 이벤트 / 대사 / 선택지
class ScriptWorkbook {
  ScriptWorkbook._();

  static const sheetGuide = '설명';
  static const sheetCharacter = '캐릭터';
  static const sheetStages = '호감도단계';
  static const sheetEvents = '이벤트';
  static const sheetLines = '대사';
  static const sheetChoices = '선택지';

  static const _characterKeys = ['캐릭터ID', '이름', '상태메시지', '성격·세계관', '타자속도'];
  static const _stageHeaders = ['단계명', '시작점수', '끝점수'];
  static const _eventHeaders = [
    '이벤트ID', '종류', '순서', '호감도단계', '최소호감도', '최대호감도',
    '필요플래그', '시간안내', '제목', '컷씬설명', '컷씬단계',
  ];
  static const _lineHeaders = ['이벤트ID', '장면', '단계', '대사', '빠르기', '사진'];
  static const _choiceHeaders = [
    '이벤트ID', '장면', '선택지ID', '버튼문구', '내 말풍선', '호감도', '획득플래그', '다음장면',
  ];

  static const _guideLines = [
    '말랑톡 대본 템플릿',
    '',
    '[캐릭터] 이름, 상태메시지, 성격·세계관(말투·습관·취미까지 자세히), 타자속도를 적어요.',
    '  타자속도: 번개같이 / 빠릿빠릿 / 보통 / 느긋하게 / 한참 고민 중 하나, 또는 0.5~2.0 숫자 (클수록 천천히 침)',
    '[호감도단계] 단계마다 이름과 점수 구간(0~100)을 적어요. 예: 어색한 사이 0~19, 친구 20~49, 썸 50~100',
    '[이벤트] 한 줄이 이야기 하나예요.',
    '  종류: 이벤트(공략에 필요한 호감도 이벤트) / 일상(이벤트 사이사이 일상 톡, 공략엔 필요 없음) / 엔딩',
    '  호감도단계: 이 단계가 되면 이벤트가 열려요. 일상은 이 단계에 머무는 동안에만 나와요.',
    '  최소·최대호감도: 단계 대신 점수로 직접 정하고 싶을 때만 (비워도 됨)',
    '  필요플래그: 앞 선택지에서 얻은 플래그가 있어야 열릴 때 (여러 개는 쉼표로)',
    '  컷씬설명·컷씬단계: 그 단계 대사가 끝나면 전체 화면 장면(CG)이 떠요. 컷씬 없는 이벤트는 비워요.',
    '[대사] 한 줄이 캐릭터 말풍선 하나예요. 같은 장면에 여러 줄을 쓰면 차례로 끊어서 보내요.',
    '  장면: 1, 2, 3처럼 숫자로 쓰면 돼요. 갈림길이 있으면 3-수락, 3-거절처럼 이름을 붙여요.',
    '  단계: 장면이 숫자면 비워도 돼요. 이름 붙인 장면은 몇 번째 단계인지 숫자로 적어요.',
    '  빠르기: 0.5(툭 빠르게) ~ 1.5(망설이며 느리게), 비우면 1',
    '  사진: 캐릭터가 사진을 보내는 말풍선이면 사진 설명',
    '[선택지] 장면 대사가 끝난 뒤 나오는 버튼이에요. 선택지가 없는 장면에서 이벤트가 끝나요.',
    '  내 말풍선: 버튼을 누르면 내가 보내는 톡. 여러 개는 줄바꿈(Alt+Enter)이나 | 로 나눠요.',
    '  호감도: 숫자(화면엔 안 보여요). 다음장면: 이어질 장면, 비우면 이벤트 끝',
    '',
    '공략 완료: 호감도 이벤트를 모두 끝내고 컷씬을 전부 모으면 엔딩이 나와요.',
  ];

  // ───────────────────────── 내보내기 ─────────────────────────

  static Uint8List encode(ScenarioBundle bundle) {
    final excel = xl.Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultSheet, sheetGuide);

    final guide = excel[sheetGuide];
    for (final line in _guideLines) {
      guide.appendRow([xl.TextCellValue(line)]);
    }
    guide.setColumnWidth(0, 110);

    final c = bundle.character;
    final characterSheet = excel[sheetCharacter];
    _header(characterSheet, ['항목', '내용']);
    final values = [c.id, c.name, c.statusMessage, c.worldviewPrompt];
    for (var i = 0; i < values.length; i++) {
      characterSheet.appendRow([xl.TextCellValue(_characterKeys[i]), xl.TextCellValue(values[i])]);
    }
    characterSheet.appendRow([
      xl.TextCellValue(_characterKeys[4]),
      xl.DoubleCellValue(c.typingSpeedMultiplier),
    ]);
    characterSheet.setColumnWidth(0, 14);
    characterSheet.setColumnWidth(1, 90);

    final stageSheet = excel[sheetStages];
    _header(stageSheet, _stageHeaders);
    for (final s in c.affectionStages) {
      stageSheet.appendRow([
        xl.TextCellValue(s.stageLabel),
        xl.IntCellValue(s.minScore),
        xl.IntCellValue(s.maxScore),
      ]);
    }

    final eventSheet = excel[sheetEvents];
    _header(eventSheet, _eventHeaders);
    for (final e in bundle.events) {
      eventSheet.appendRow([
        xl.TextCellValue(e.id),
        xl.TextCellValue(_typeLabel(e.eventType)),
        xl.IntCellValue(e.chapterOrder),
        _text(e.stageLabel),
        e.stageLabel == null || e.requiredAffection > 0 ? xl.IntCellValue(e.requiredAffection) : null,
        e.maxAffection != null ? xl.IntCellValue(e.maxAffection!) : null,
        _text(e.requiredFlags.join(', ')),
        _text(e.timeNotice),
        xl.TextCellValue(e.title),
        _text(e.cutscenePhotoTitle),
        e.cutsceneTriggerStep != null ? xl.IntCellValue(e.cutsceneTriggerStep!) : null,
      ]);
    }
    for (final (col, width) in [(0, 22.0), (1, 8.0), (3, 14.0), (7, 18.0), (8, 20.0), (9, 40.0)]) {
      eventSheet.setColumnWidth(col, width);
    }

    final lineSheet = excel[sheetLines];
    final choiceSheet = excel[sheetChoices];
    _header(lineSheet, _lineHeaders);
    _header(choiceSheet, _choiceHeaders);
    for (final e in bundle.events) {
      final nodes = bundle.nodes.values.where((n) => n.eventId == e.id).toList()
        ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
      for (final n in nodes) {
        final scene = _sceneLabel(e.id, n.id);
        final numeric = int.tryParse(scene) == n.stepOrder;
        for (final b in n.characterBubbles) {
          lineSheet.appendRow([
            xl.TextCellValue(e.id),
            int.tryParse(scene) != null ? xl.IntCellValue(int.parse(scene)) : xl.TextCellValue(scene),
            numeric ? null : xl.IntCellValue(n.stepOrder),
            xl.TextCellValue(b.text),
            b.speedFactor != 1.0 ? xl.DoubleCellValue(b.speedFactor) : null,
            _text(b.photoLabel),
          ]);
        }
        for (final ch in n.choices) {
          final next = ch.nextNodeId != null ? _sceneLabel(e.id, ch.nextNodeId!) : null;
          choiceSheet.appendRow([
            xl.TextCellValue(e.id),
            int.tryParse(scene) != null ? xl.IntCellValue(int.parse(scene)) : xl.TextCellValue(scene),
            xl.TextCellValue(ch.id),
            xl.TextCellValue(ch.buttonLabel),
            xl.TextCellValue(ch.userBubbles.map(_userBubbleText).join('\n')),
            xl.IntCellValue(ch.affectionDelta),
            _text(ch.addFlag),
            next == null
                ? null
                : int.tryParse(next) != null
                    ? xl.IntCellValue(int.parse(next))
                    : xl.TextCellValue(next),
          ]);
        }
      }
    }
    for (final (col, width) in [(0, 22.0), (1, 12.0), (3, 50.0), (5, 30.0)]) {
      lineSheet.setColumnWidth(col, width);
    }
    for (final (col, width) in [(0, 22.0), (1, 12.0), (3, 30.0), (4, 45.0), (7, 12.0)]) {
      choiceSheet.setColumnWidth(col, width);
    }

    excel.setDefaultSheet(sheetGuide);
    return Uint8List.fromList(excel.encode()!);
  }

  static void _header(xl.Sheet sheet, List<String> headers) {
    sheet.appendRow([for (final h in headers) xl.TextCellValue(h)]);
    for (var i = 0; i < headers.length; i++) {
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).cellStyle =
          xl.CellStyle(bold: true, backgroundColorHex: xl.ExcelColor.fromHexString('#FFE0EB'));
    }
  }

  static xl.CellValue? _text(String? value) =>
      value == null || value.isEmpty ? null : xl.TextCellValue(value);

  static String _typeLabel(String type) => switch (type) {
        ScenarioEventType.daily => '일상',
        ScenarioEventType.ending => '엔딩',
        ScenarioEventType.intrusion => '난입',
        _ => '이벤트',
      };

  /// 노드 ID를 엑셀의 '장면' 칸 값으로 (이벤트ID_3 → 3, 이벤트ID_3-거절 → 3-거절)
  static String _sceneLabel(String eventId, String nodeId) {
    final prefix = '${eventId}_';
    return nodeId.startsWith(prefix) ? nodeId.substring(prefix.length) : nodeId;
  }

  static String _userBubbleText(ScriptBubblePiece b) =>
      b.hasPhoto ? '[사진: ${b.photoLabel}] ${b.text}'.trim() : b.text;

  // ───────────────────────── 읽어오기 ─────────────────────────

  static ScriptWorkbookResult decode(Uint8List bytes) {
    final xl.Excel excel;
    try {
      excel = xl.Excel.decodeBytes(bytes);
    } catch (_) {
      throw const ScriptWorkbookException(['엑셀 파일(.xlsx)을 읽지 못했어요. 템플릿으로 저장한 파일인지 확인해 주세요.']);
    }
    final errors = <String>[];
    final warnings = <String>[];

    List<Map<String, String>> rows(String name, {required bool required}) {
      final sheet = excel.tables[name];
      if (sheet == null) {
        if (required) errors.add('"$name" 시트가 없어요.');
        return const [];
      }
      final all = sheet.rows;
      if (all.isEmpty) return const [];
      final headers = [for (final cell in all.first) _cell(cell)];
      return [
        for (final row in all.skip(1))
          {
            for (var i = 0; i < headers.length && i < row.length; i++)
              if (headers[i].isNotEmpty && _cell(row[i]).isNotEmpty) headers[i]: _cell(row[i]),
          },
      ].where((r) => r.isNotEmpty).toList();
    }

    // 캐릭터
    final info = <String, String>{
      for (final r in rows(sheetCharacter, required: true))
        if (r['항목'] != null) r['항목']!: r['내용'] ?? '',
    };
    final name = info['이름']?.trim() ?? '';
    if (name.isEmpty && excel.tables.containsKey(sheetCharacter)) {
      errors.add('[캐릭터] 이름을 적어 주세요.');
    }
    final characterId = (info['캐릭터ID']?.trim().isNotEmpty ?? false)
        ? info['캐릭터ID']!.trim()
        : 'char_${DateTime.now().millisecondsSinceEpoch}';

    // 호감도 단계
    final stages = <AffectionStage>[];
    final stageRows = rows(sheetStages, required: true);
    for (var i = 0; i < stageRows.length; i++) {
      final r = stageRows[i];
      final label = r['단계명']?.trim() ?? '';
      final min = _int(r['시작점수']);
      final max = _int(r['끝점수']);
      if (label.isEmpty || min == null) {
        errors.add('[호감도단계] ${i + 2}번째 줄: 단계명과 시작점수를 적어 주세요.');
        continue;
      }
      stages.add(AffectionStage(minScore: min, maxScore: max ?? 100, stageLabel: label));
    }
    stages.sort((a, b) => a.minScore.compareTo(b.minScore));
    // 끝점수를 비우면 다음 단계 시작 직전까지
    for (var i = 0; i < stages.length; i++) {
      final raw = stageRows.where((r) => r['단계명']?.trim() == stages[i].stageLabel).firstOrNull;
      if (raw != null && _int(raw['끝점수']) == null) {
        stages[i] = AffectionStage(
          minScore: stages[i].minScore,
          maxScore: i + 1 < stages.length ? stages[i + 1].minScore - 1 : 100,
          stageLabel: stages[i].stageLabel,
        );
      }
    }
    if (stages.isEmpty && excel.tables.containsKey(sheetStages)) {
      errors.add('[호감도단계] 단계를 하나 이상 적어 주세요.');
    }

    final character = CharacterModel(
      id: characterId,
      creatorId: 'me',
      name: name,
      statusMessage: info['상태메시지']?.trim() ?? '',
      avatarUrl: '',
      worldviewPrompt: info['성격·세계관']?.trim() ?? info['성격']?.trim() ?? '',
      typingSpeedMultiplier: _typingSpeed(info['타자속도']),
      affectionStages: stages,
    );

    // 이벤트
    final events = <ScenarioEventModel>[];
    final eventIds = <String>{};
    final eventRows = rows(sheetEvents, required: true);
    for (var i = 0; i < eventRows.length; i++) {
      final r = eventRows[i];
      final line = '[이벤트] ${i + 2}번째 줄';
      final id = r['이벤트ID']?.trim() ?? '';
      final title = r['제목']?.trim() ?? '';
      if (id.isEmpty) {
        errors.add('$line: 이벤트ID를 적어 주세요.');
        continue;
      }
      if (!eventIds.add(id)) {
        errors.add('$line: 이벤트ID "$id"가 두 번 나와요.');
        continue;
      }
      final type = _eventType(r['종류']);
      if (type == null) {
        errors.add('$line: 종류는 이벤트 / 일상 / 엔딩 중 하나로 적어 주세요.');
        continue;
      }
      final stageLabel = r['호감도단계']?.trim();
      if (stageLabel != null && !stages.any((s) => s.stageLabel == stageLabel)) {
        errors.add('$line: 호감도단계 "$stageLabel"이 [호감도단계] 시트에 없어요.');
      }
      events.add(ScenarioEventModel(
        id: id,
        characterId: characterId,
        chapterOrder: _int(r['순서']) ?? (type == ScenarioEventType.ending ? 999 : i + 1),
        eventType: type,
        title: title.isEmpty ? id : title,
        timeNotice: r['시간안내']?.trim(),
        requiredAffection: _int(r['최소호감도']) ?? 0,
        maxAffection: _int(r['최대호감도']),
        stageLabel: stageLabel,
        requiredFlags: [
          for (final f in (r['필요플래그'] ?? '').split(RegExp(r'[,，\n]')))
            if (f.trim().isNotEmpty) f.trim(),
        ],
        cutscenePhotoTitle: r['컷씬설명']?.trim(),
        cutsceneTriggerStep: type == ScenarioEventType.daily ? null : _int(r['컷씬단계']),
        participantCharacterIds: [characterId],
      ));
      if (type == ScenarioEventType.daily && _int(r['컷씬단계']) != null) {
        warnings.add('$line: 일상 대화에는 컷씬을 넣을 수 없어서 뺐어요.');
      }
    }

    // 대사 → 장면(노드)
    final sceneBubbles = <String, List<ScriptBubblePiece>>{};
    final sceneStep = <String, int>{};
    final sceneEvent = <String, String>{};
    final sceneOrder = <String>[];
    final lineRows = rows(sheetLines, required: true);
    String? lastEvent;
    String? lastScene;
    for (var i = 0; i < lineRows.length; i++) {
      final r = lineRows[i];
      final line = '[대사] ${i + 2}번째 줄';
      final eventId = r['이벤트ID']?.trim() ?? lastEvent;
      if (eventId == null || !eventIds.contains(eventId)) {
        errors.add('$line: 이벤트ID "${eventId ?? ''}"가 [이벤트] 시트에 없어요.');
        continue;
      }
      final rawScene = r['장면']?.trim() ?? (eventId == lastEvent ? lastScene : null) ?? '1';
      final nodeId = _nodeId(eventId, rawScene);
      lastEvent = eventId;
      lastScene = rawScene;
      final text = r['대사']?.trim() ?? '';
      final photo = r['사진']?.trim();
      if (text.isEmpty && (photo == null || photo.isEmpty)) continue;
      if (!sceneBubbles.containsKey(nodeId)) {
        sceneOrder.add(nodeId);
        sceneEvent[nodeId] = eventId;
        sceneStep[nodeId] = _int(r['단계']) ??
            int.tryParse(rawScene) ??
            int.tryParse(RegExp(r'^\d+').stringMatch(rawScene) ?? '') ??
            sceneOrder.where((n) => sceneEvent[n] == eventId).length;
      }
      (sceneBubbles[nodeId] ??= []).add(ScriptBubblePiece(
        text: text,
        speedFactor: _double(r['빠르기'])?.clamp(0.3, 2.5) ?? 1.0,
        photoLabel: photo,
      ));
    }

    // 선택지
    final sceneChoices = <String, List<ChoiceOption>>{};
    final choiceRows = rows(sheetChoices, required: false);
    final pendingNext = <(String line, String next)>[];
    for (var i = 0; i < choiceRows.length; i++) {
      final r = choiceRows[i];
      final line = '[선택지] ${i + 2}번째 줄';
      final eventId = r['이벤트ID']?.trim() ?? '';
      if (!eventIds.contains(eventId)) {
        errors.add('$line: 이벤트ID "$eventId"가 [이벤트] 시트에 없어요.');
        continue;
      }
      final nodeId = _nodeId(eventId, r['장면']?.trim() ?? '1');
      if (!sceneBubbles.containsKey(nodeId)) {
        errors.add('$line: 장면 "${r['장면'] ?? '1'}"의 대사가 [대사] 시트에 없어요.');
        continue;
      }
      final label = r['버튼문구']?.trim() ?? '';
      final bubbles = _userBubbles(r['내 말풍선'] ?? '');
      if (label.isEmpty && bubbles.isEmpty) {
        errors.add('$line: 버튼문구나 내 말풍선을 적어 주세요.');
        continue;
      }
      final next = r['다음장면']?.trim();
      final nextId = next == null || next.isEmpty ? null : _nodeId(eventId, next);
      if (nextId != null) pendingNext.add((line, nextId));
      final list = sceneChoices[nodeId] ??= [];
      list.add(ChoiceOption(
        id: r['선택지ID']?.trim() ?? '${nodeId}_c${list.length + 1}',
        buttonLabel: label.isEmpty ? bubbles.first.text : label,
        userBubbles: bubbles.isEmpty ? [ScriptBubblePiece(text: label)] : bubbles,
        affectionDelta: _int(r['호감도']) ?? 0,
        addFlag: r['획득플래그']?.trim(),
        nextNodeId: nextId,
      ));
    }
    for (final (line, next) in pendingNext) {
      if (!sceneBubbles.containsKey(next)) {
        errors.add('$line: 다음장면 "${_sceneLabel(sceneEvent[next] ?? '', next)}"의 대사가 [대사] 시트에 없어요.');
      }
    }

    final nodes = <String, ScriptNodeModel>{
      for (final id in sceneOrder)
        id: ScriptNodeModel(
          id: id,
          eventId: sceneEvent[id]!,
          stepOrder: sceneStep[id]!,
          speakerCharacterId: characterId,
          characterBubbles: sceneBubbles[id]!,
          choices: sceneChoices[id] ?? const [],
        ),
    };

    for (final e in events) {
      if (!nodes.values.any((n) => n.eventId == e.id)) {
        warnings.add('"${e.title}"에 대사가 없어요.');
      }
    }
    if (!events.any((e) => e.isAffectionEvent)) {
      errors.add('[이벤트] 종류가 "이벤트"인 호감도 이벤트를 하나 이상 넣어 주세요.');
    }
    if (!events.any((e) => e.isEnding) && events.isNotEmpty) {
      warnings.add('엔딩이 없어요. 이벤트를 다 끝내면 "공략 완료" 안내만 나와요.');
    }
    if (!events.any((e) => e.isDaily) && events.isNotEmpty) {
      warnings.add('일상 대화가 없어요. 이벤트 사이에 일상 톡을 넣으면 더 오래 즐길 수 있어요.');
    }

    if (errors.isNotEmpty) throw ScriptWorkbookException(errors);
    events.sort((a, b) => a.chapterOrder.compareTo(b.chapterOrder));
    return ScriptWorkbookResult(
      ScenarioBundle(character: character, events: events, nodes: nodes),
      warnings,
    );
  }

  static String _cell(xl.Data? cell) {
    final value = cell?.value;
    if (value == null) return '';
    if (value is xl.DoubleCellValue && value.value == value.value.roundToDouble()) {
      return value.value.toInt().toString();
    }
    return value.toString().trim();
  }

  static int? _int(String? raw) {
    if (raw == null) return null;
    final text = raw.trim().replaceAll('+', '');
    return int.tryParse(text) ?? double.tryParse(text)?.round();
  }

  static double? _double(String? raw) => raw == null ? null : double.tryParse(raw.trim());

  static double _typingSpeed(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 1.0;
    final number = double.tryParse(raw.trim());
    if (number != null) return number.clamp(0.4, 2.5);
    final style = TypingStyle.all.where((s) => s.label == raw.trim()).firstOrNull;
    return style?.multiplier ?? 1.0;
  }

  static String? _eventType(String? raw) {
    final text = (raw ?? '이벤트').trim().toLowerCase();
    return switch (text) {
      '이벤트' || '호감도 이벤트' || '호감도이벤트' || 'custom' || 'event' || 'auto_story' =>
        ScenarioEventType.custom,
      '일상' || '일상 대화' || '일상대화' || 'daily' => ScenarioEventType.daily,
      '엔딩' || 'ending' => ScenarioEventType.ending,
      _ => null,
    };
  }

  /// 장면 이름은 이벤트마다 따로 쓰도록 노드 ID 앞에 이벤트ID를 붙임 (다른 이벤트의 '1'과 안 겹치게)
  static String _nodeId(String eventId, String scene) =>
      '${eventId}_${int.tryParse(scene)?.toString() ?? scene}';

  static final _photoPattern = RegExp(r'^\[사진\s*[:：]\s*([^\]]+)\]\s*');

  static List<ScriptBubblePiece> _userBubbles(String raw) {
    return [
      for (final part in raw.split(RegExp(r'\r?\n|\|')))
        if (part.trim().isNotEmpty) _userBubble(part.trim()),
    ];
  }

  static ScriptBubblePiece _userBubble(String text) {
    final match = _photoPattern.firstMatch(text);
    if (match == null) return ScriptBubblePiece(text: text);
    return ScriptBubblePiece(
      text: text.substring(match.end).trim(),
      photoLabel: match.group(1)!.trim(),
    );
  }
}
