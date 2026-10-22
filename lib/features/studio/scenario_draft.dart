import '../../core/network/claude_studio_client.dart';
import '../../shared/models/mallangtalk_models.dart';

/// [초보자 노트] 만들기 화면에서 고치는 중인 캐릭터 한 명 분량의 '초안'입니다.
/// 화면의 입력칸이 이 객체들의 값을 바로 바꾸고, 저장할 때 toBundle()로 앱이 플레이하는 시나리오로 바꿉니다.
/// 다음 장면은 이름 대신 장면 객체를 직접 가리켜서, 장면을 지우거나 순서를 바꿔도 연결이 꼬이지 않아요.

/// 대화 종류 (편집기에서 고르는 이름)
enum DraftKind {
  story('호감도 이벤트', '그 단계가 되면 열려요. 공략하려면 다 봐야 해요'),
  daily('일상 대화', '그 단계에 머무는 동안 이벤트 사이사이에 와요'),
  special('특별 이벤트', '실제 시간에 대화방에 있을 때만 한 번 와요'),
  ending('엔딩', '이벤트를 다 보고 컷씬을 다 모으면 나와요');

  const DraftKind(this.label, this.note);
  final String label;
  final String note;
}

class FieldDraft {
  String label;
  String value;
  bool isSecret;
  FieldDraft({this.label = '', this.value = '', this.isSecret = false});
}

class CastDraft {
  String name;
  String role;
  String speech;
  CastDraft({this.name = '', this.role = '', this.speech = ''});
}

class StageDraft {
  String name;
  int start;
  StageDraft({this.name = '', this.start = 0});
}

class LineDraft {
  String text;
  double speed;
  String photo;
  /// 올린 진짜 사진 (data: 주소). 비우면 설명만 있는 사진 카드
  String photoImage;
  LineDraft({this.text = '', this.speed = 1.0, this.photo = '', this.photoImage = ''});
}

class ChoiceDraft {
  String label;
  /// 버튼을 누르면 내가 보내는 톡 (줄마다 말풍선 하나)
  String messages;
  int affection;
  SceneDraft? next;
  String flag;
  ChoiceDraft({this.label = '', this.messages = '', this.affection = 2, this.next, this.flag = ''});
}

class SceneDraft {
  final List<LineDraft> lines;
  final List<ChoiceDraft> choices;
  /// 이 장면 대사까지 보면 컷씬이 앨범에 모임
  bool cutsceneHere;
  SceneDraft({List<LineDraft>? lines, List<ChoiceDraft>? choices, this.cutsceneHere = false})
      : lines = lines ?? [LineDraft()],
        choices = choices ?? [];
}

class EventDraft {
  String id;
  DraftKind kind;
  String title;
  /// 장면 전환 문구 (다음 날, 그날 밤 …)
  String notice;
  String stage;
  String synopsis;
  /// 컷씬(앨범 장면) 설명. 설명과 사진이 둘 다 비면 컷씬 없음
  String cutscene;
  /// 컷씬으로 보여 줄 진짜 사진 (data: 주소). 비우면 설명 카드
  String cutsceneImage;
  int fromHour;
  int toHour;
  String date;
  List<String> requiredFlags;
  /// 불러온 시나리오에 단계 대신 점수로 적힌 조건 (단계를 안 바꾸면 그대로 지킴)
  final int keptMin;
  final String keptStage;
  final List<SceneDraft> scenes;
  EventDraft({
    required this.id,
    this.kind = DraftKind.story,
    this.title = '',
    this.notice = '',
    this.stage = '',
    this.synopsis = '',
    this.cutscene = '',
    this.cutsceneImage = '',
    this.fromHour = 22,
    this.toHour = 2,
    this.date = '',
    this.requiredFlags = const [],
    this.keptMin = 0,
    this.keptStage = '',
    List<SceneDraft>? scenes,
  }) : scenes = scenes ?? [SceneDraft()];

  /// 설명이나 사진이 있으면 컷씬 (일상 대화는 컷씬 없음)
  bool get hasCutscene =>
      kind != DraftKind.daily && (cutscene.trim().isNotEmpty || cutsceneImage.isNotEmpty);
}

class ScenarioDraft {
  String id;
  String name = '';
  String statusMessage = '';
  String tagline = '';
  String tags = '';
  String avatarUrl = '';
  String setting = '';
  String world = '';
  String userRole = '';
  String secret = '';
  String quote = '';
  String themeColor = '';
  double typing = 1.0;
  List<PersonalityTrait> traits = [];
  List<CharacterQuote> sampleQuotes = [];
  final List<FieldDraft> fields = [];
  final List<CastDraft> cast = [];
  final List<StageDraft> stages = [];
  final List<EventDraft> events = [];

  ScenarioDraft({String? id}) : id = id ?? 'char_${DateTime.now().millisecondsSinceEpoch}';

  /// 빈 초안 (단계 3개, 첫 이벤트 하나)
  factory ScenarioDraft.blank() {
    final d = ScenarioDraft();
    d.stages.addAll([
      StageDraft(name: '어색한 사이', start: 0),
      StageDraft(name: '친구', start: 20),
      StageDraft(name: '썸', start: 45),
    ]);
    d.fields.addAll([FieldDraft(label: '나이'), FieldDraft(label: '직업')]);
    d.events.add(EventDraft(id: d.newEventId(), stage: '어색한 사이'));
    return d;
  }

  int _seq = 0;
  String newEventId() {
    String id;
    do {
      id = 'evt_${DateTime.now().millisecondsSinceEpoch % 100000}_${_seq++}';
    } while (events.any((e) => e.id == id));
    return id;
  }

  List<String> get stageNames => [for (final s in stages) if (s.name.trim().isNotEmpty) s.name.trim()];

  // ───────────────────────── 시나리오 → 초안 ─────────────────────────

  factory ScenarioDraft.fromBundle(ScenarioBundle bundle) {
    final c = bundle.character;
    final d = ScenarioDraft(id: c.id)
      ..name = c.name
      ..statusMessage = c.statusMessage
      ..tagline = c.tagline
      ..tags = c.tags.join(', ')
      ..avatarUrl = c.avatarUrl
      ..setting = c.worldviewPrompt
      ..world = c.worldSetting
      ..userRole = c.userRole
      ..secret = c.secret
      ..quote = c.quote
      ..themeColor = c.themeColor
      ..typing = c.typingSpeedMultiplier
      ..traits = [...c.traits]
      ..sampleQuotes = [...c.sampleQuotes];
    d.fields.addAll([for (final f in c.profileFields) FieldDraft(label: f.label, value: f.value, isSecret: f.isSecret)]);
    d.cast.addAll([for (final e in c.extraCast) CastDraft(name: e.name, role: e.role, speech: e.speech)]);
    d.stages.addAll([for (final s in c.affectionStages) StageDraft(name: s.stageLabel, start: s.minScore)]);
    final events = [...bundle.events]..sort((a, b) => a.chapterOrder.compareTo(b.chapterOrder));
    for (final e in events) {
      d.events.add(eventFromBundle(bundle, e));
    }
    return d;
  }

  /// 시나리오의 이벤트 하나를 편집기 초안으로 (AI가 이벤트 하나만 새로 쓸 때도 씀)
  static EventDraft eventFromBundle(ScenarioBundle bundle, ScenarioEventModel e, {List<ScriptNodeModel>? nodes}) {
    final eventNodes = (nodes ?? bundle.nodes.values.where((n) => n.eventId == e.id).toList())
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
    final scenes = <String, SceneDraft>{
      for (final n in eventNodes)
        n.id: SceneDraft(
          lines: [
            for (final b in n.characterBubbles)
              LineDraft(
                text: b.text,
                speed: b.speedFactor,
                photo: b.photoLabel ?? '',
                photoImage: bundle.resolveImage(b.photoImage) ?? '',
              ),
          ],
        ),
    };
    var cutsceneMarked = false;
    for (final n in eventNodes) {
      final scene = scenes[n.id]!;
      if (!cutsceneMarked && e.cutsceneTriggerStep == n.stepOrder) {
        scene.cutsceneHere = true;
        cutsceneMarked = true;
      }
      for (final c in n.choices) {
        scene.choices.add(ChoiceDraft(
          label: c.buttonLabel,
          messages: c.userBubbles.map((b) => b.text).join('\n'),
          affection: c.affectionDelta,
          next: c.nextNodeId != null ? scenes[c.nextNodeId] : null,
          flag: c.addFlag ?? '',
        ));
      }
    }
    final stage = e.stageLabel ??
        bundle.character.stageFor(e.requiredAffection)?.stageLabel ??
        '';
    return EventDraft(
      id: e.id,
      kind: e.isEnding
          ? DraftKind.ending
          : e.isDaily
              ? DraftKind.daily
              : e.isSpecial
                  ? DraftKind.special
                  : DraftKind.story,
      title: e.title,
      notice: e.timeNotice ?? '',
      stage: stage,
      synopsis: e.synopsis,
      cutscene: e.cutscenePhotoTitle ?? '',
      cutsceneImage: bundle.resolveImage(e.cutsceneImageUrl) ?? '',
      fromHour: e.realTime?.fromHour ?? 22,
      toHour: e.realTime?.toHour ?? 2,
      date: e.realTime?.date ?? '',
      requiredFlags: e.requiredFlags,
      keptMin: e.requiredAffection,
      keptStage: stage,
      scenes: scenes.values.isEmpty ? null : scenes.values.toList(),
    );
  }

  // ───────────────────────── 초안 → 시나리오 ─────────────────────────

  List<AffectionStage> buildStages() {
    final sorted = [for (final s in stages) if (s.name.trim().isNotEmpty) s]
      ..sort((a, b) => a.start.compareTo(b.start));
    return [
      for (var i = 0; i < sorted.length; i++)
        AffectionStage(
          minScore: sorted[i].start,
          maxScore: i + 1 < sorted.length ? sorted[i + 1].start - 1 : 100,
          stageLabel: sorted[i].name.trim(),
        ),
    ];
  }

  CharacterModel buildCharacter() => CharacterModel(
        id: id,
        creatorId: 'me',
        name: name.trim(),
        statusMessage: statusMessage.trim(),
        avatarUrl: avatarUrl,
        tagline: tagline.trim(),
        tags: [
          for (final t in tags.split(RegExp(r'[,#\s]+')))
            if (t.trim().isNotEmpty) t.trim(),
        ],
        worldviewPrompt: setting.trim(),
        worldSetting: world.trim(),
        quote: quote.trim(),
        profileFields: [
          for (final f in fields)
            if (f.label.trim().isNotEmpty && f.value.trim().isNotEmpty)
              ProfileField(label: f.label.trim(), value: f.value.trim(), isSecret: f.isSecret),
        ],
        traits: traits,
        sampleQuotes: sampleQuotes,
        secret: secret.trim(),
        userRole: userRole.trim(),
        extraCast: [
          for (final e in cast)
            if (e.name.trim().isNotEmpty) ExtraCast(name: e.name.trim(), role: e.role.trim(), speech: e.speech.trim()),
        ],
        themeColor: themeColor,
        typingSpeedMultiplier: typing,
        affectionStages: buildStages(),
      );

  static String nodeId(EventDraft e, int sceneIndex) => '${e.id}_${sceneIndex + 1}';

  ScenarioEventModel buildEvent(EventDraft e, int order) {
    final cutsceneIndex = e.scenes.indexWhere((s) => s.cutsceneHere);
    final hasCutscene = e.hasCutscene;
    return ScenarioEventModel(
      id: e.id,
      characterId: id,
      chapterOrder: e.kind == DraftKind.ending ? 999 : (order + 1) * 10,
      eventType: switch (e.kind) {
        DraftKind.story => ScenarioEventType.custom,
        DraftKind.daily => ScenarioEventType.daily,
        DraftKind.special => ScenarioEventType.special,
        DraftKind.ending => ScenarioEventType.ending,
      },
      title: e.title.trim(),
      timeNotice: e.kind == DraftKind.special || e.notice.trim().isEmpty ? null : e.notice.trim(),
      stageLabel: e.kind == DraftKind.ending || e.stage.trim().isEmpty ? null : e.stage.trim(),
      requiredFlags: e.requiredFlags,
      requiredAffection: e.stage == e.keptStage ? e.keptMin : 0,
      synopsis: e.synopsis.trim(),
      cutscenePhotoTitle: hasCutscene ? (e.cutscene.trim().isEmpty ? e.title.trim() : e.cutscene.trim()) : null,
      cutsceneImageUrl: hasCutscene ? imageRef(e.cutsceneImage) : null,
      // 컷씬 장면을 안 골랐으면 첫 장면에서
      cutsceneTriggerStep: hasCutscene ? (cutsceneIndex < 0 ? 0 : cutsceneIndex) + 1 : null,
      realTime: e.kind == DraftKind.special
          ? RealTimeWindow(fromHour: e.fromHour, toHour: e.toHour, date: e.date.trim().isEmpty ? null : e.date.trim())
          : null,
      participantCharacterIds: [id],
    );
  }

  List<ScriptNodeModel> buildNodes(EventDraft e) {
    final nodes = <ScriptNodeModel>[];
    for (var i = 0; i < e.scenes.length; i++) {
      final scene = e.scenes[i];
      final nid = nodeId(e, i);
      nodes.add(ScriptNodeModel(
        id: nid,
        eventId: e.id,
        stepOrder: i + 1,
        speakerCharacterId: id,
        characterBubbles: [
          for (final l in scene.lines)
            if (l.text.trim().isNotEmpty || l.photo.trim().isNotEmpty || l.photoImage.isNotEmpty)
              ScriptBubblePiece(
                text: l.text.trim(),
                speedFactor: l.speed,
                photoLabel: l.photo.trim().isEmpty ? (l.photoImage.isEmpty ? null : '사진') : l.photo.trim(),
                photoImage: imageRef(l.photoImage),
              ),
        ],
        choices: [
          for (var j = 0; j < scene.choices.length; j++)
            _buildChoice(e, scene.choices[j], '${nid}_c${j + 1}'),
        ],
      ));
    }
    return nodes;
  }

  ChoiceOption _buildChoice(EventDraft e, ChoiceDraft c, String choiceId) {
    final messages = [
      for (final m in c.messages.split('\n'))
        if (m.trim().isNotEmpty) ScriptBubblePiece(text: m.trim()),
    ];
    final nextIndex = c.next == null ? -1 : e.scenes.indexOf(c.next!);
    return ChoiceOption(
      id: choiceId,
      buttonLabel: c.label.trim().isEmpty ? (messages.firstOrNull?.text ?? '...') : c.label.trim(),
      userBubbles: messages.isEmpty ? [ScriptBubblePiece(text: c.label.trim())] : messages,
      affectionDelta: c.affection,
      addFlag: c.flag.trim().isEmpty ? null : c.flag.trim(),
      nextNodeId: nextIndex < 0 ? null : nodeId(e, nextIndex),
    );
  }

  ScenarioBundle toBundle() {
    final events = <ScenarioEventModel>[];
    final nodes = <String, ScriptNodeModel>{};
    for (var i = 0; i < this.events.length; i++) {
      final e = this.events[i];
      events.add(buildEvent(e, i));
      for (final n in buildNodes(e)) {
        nodes[n.id] = n;
      }
    }
    return ScenarioBundle(character: buildCharacter(), events: events, nodes: nodes, images: collectImages());
  }

  /// 올린 사진(data: 주소)을 캐릭터 파일 안의 'img:번호'로. 같은 사진은 같은 번호라 한 번만 저장됨.
  /// http 주소 같은 다른 주소는 그대로 둠
  static String? imageRef(String image) {
    if (image.isEmpty) return null;
    if (!image.startsWith('data:')) return image;
    return '${ScenarioBundle.imagePrefix}${imageId(image)}';
  }

  /// 사진 내용으로 만든 짧은 번호 (FNV-1a)
  static String imageId(String dataUrl) {
    var hash = 0x811c9dc5;
    for (final unit in dataUrl.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return 'p${hash.toRadixString(16).padLeft(8, '0')}_${dataUrl.length}';
  }

  /// 초안에 올린 사진을 모두 모아 번호 → 사진 표로
  Map<String, String> collectImages() => {
        for (final e in events) ...{
          if (e.hasCutscene && e.cutsceneImage.startsWith('data:')) imageId(e.cutsceneImage): e.cutsceneImage,
          for (final scene in e.scenes)
            for (final l in scene.lines)
              if (l.photoImage.startsWith('data:')) imageId(l.photoImage): l.photoImage,
        },
      };

  // ───────────────────────── 확인 ─────────────────────────

  /// 저장하기 전에 꼭 고쳐야 하는 것
  List<String> problems() {
    final out = <String>[];
    if (name.trim().isEmpty) out.add('[캐릭터] 이름을 적어 주세요.');
    final named = [for (final s in stages) if (s.name.trim().isNotEmpty) s];
    if (named.isEmpty) out.add('[호감도 단계] 단계를 하나 이상 만들어 주세요.');
    if (named.length != stages.length) out.add('[호감도 단계] 이름이 빈 단계가 있어요.');
    if (named.isNotEmpty && !named.any((s) => s.start == 0)) {
      out.add('[호감도 단계] 첫 단계는 0점부터 시작해야 해요.');
    }
    if (named.map((s) => s.start).toSet().length != named.length) {
      out.add('[호감도 단계] 시작 점수가 겹치는 단계가 있어요.');
    }
    if (named.map((s) => s.name.trim()).toSet().length != named.length) {
      out.add('[호감도 단계] 같은 이름의 단계가 있어요.');
    }
    if (!events.any((e) => e.kind == DraftKind.story)) {
      out.add('[이벤트] 호감도 이벤트를 하나 이상 만들어 주세요.');
    }
    if (events.where((e) => e.kind == DraftKind.ending).length > 1) {
      out.add('[이벤트] 엔딩은 하나만 둘 수 있어요.');
    }
    final names = stageNames.toSet();
    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      final where = '[이벤트 ${i + 1}${e.title.trim().isEmpty ? '' : ' · ${e.title.trim()}'}]';
      if (e.title.trim().isEmpty) out.add('$where 제목을 적어 주세요.');
      if (e.kind != DraftKind.ending && !names.contains(e.stage.trim())) {
        out.add('$where 호감도 단계를 골라 주세요.');
      }
      if (e.kind == DraftKind.special && e.fromHour == e.toHour && e.date.trim().isEmpty) {
        out.add('$where 열리는 시간을 정해 주세요.');
      }
      if (e.date.trim().isNotEmpty && !RegExp(r'^\d{2}-\d{2}$').hasMatch(e.date.trim())) {
        out.add('$where 날짜는 12-25처럼 적어 주세요.');
      }
      if (e.scenes.isEmpty) out.add('$where 장면이 없어요. 대사 탭에서 장면을 추가해 주세요.');
      for (var j = 0; j < e.scenes.length; j++) {
        final scene = e.scenes[j];
        if (!scene.lines.any((l) => l.text.trim().isNotEmpty || l.photo.trim().isNotEmpty)) {
          out.add('$where 장면 ${j + 1}에 캐릭터 말풍선이 없어요.');
        }
        for (final c in scene.choices) {
          if (c.label.trim().isEmpty && c.messages.trim().isEmpty) {
            out.add('$where 장면 ${j + 1}에 비어 있는 선택지가 있어요.');
          }
          if (c.next == scene) out.add('$where 장면 ${j + 1}의 선택지가 자기 장면으로 돌아가요.');
        }
      }
    }
    return out;
  }

  /// 고치면 좋은 것 (저장은 됨)
  List<String> warnings() {
    final out = <String>[];
    if (problems().isNotEmpty) return out;
    final bundle = toBundle();
    if (!bestPathClears(bundle)) {
      out.add('좋은 선택만 골라도 모든 호감도 이벤트를 열 수 없어요. 저장할 때 호감도를 자동으로 맞출 수 있어요.');
    }
    for (final e in events) {
      if (e.hasCutscene && !e.scenes.any((s) => s.cutsceneHere)) {
        out.add('"${e.title}" 컷씬이 몇 번째 장면에서 모이는지 안 골라서 첫 장면으로 정했어요.');
      }
    }
    if (setting.trim().isEmpty) out.add('캐릭터 설정이 비어 있으면 AI 자유대화가 캐릭터를 잘 모를 수 있어요.');
    return out;
  }
}
