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
  ending('엔딩', '호감도 이벤트를 다 끝내면 나와요. 엔딩 이름은 제목이에요'),
  afterEnding('공략 후 이야기', '엔딩을 본 뒤 순서대로 와요. 사진도 넣을 수 있어요');

  const DraftKind(this.label, this.note);
  final String label;
  final String note;

  /// 호감도 단계를 골라야 하는 종류 (엔딩·공략 후 이야기는 단계 없음)
  bool get needsStage => this != ending && this != afterEnding;

  /// '이어지는 대화'로 다른 대화 뒤에 붙일 수 있는 종류
  bool get canFollow => this == daily || this == afterEnding;
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
  /// 내 캐릭터를 불러와 연결했으면 그 ID
  String? characterId;
  CastDraft({this.name = '', this.role = '', this.speech = '', this.characterId});
}

class LoreDraft {
  /// 쉼표로 나눈 키워드
  String keys;
  String content;
  bool always;
  LoreDraft({this.keys = '', this.content = '', this.always = false});
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
  /// 답장이 늦게 오는 연출: 이 말풍선 전에 기다리는 초 (0이면 보통)
  int delay;
  LineDraft({this.text = '', this.speed = 1.0, this.photo = '', this.photoImage = '', this.delay = 0});

  /// 사진 말풍선인지 (설명이나 사진이 있음)
  bool get isPhoto => photo.isNotEmpty || photoImage.isNotEmpty;
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
  /// 선톡: 이 장면에서 캐릭터보다 먼저 내가 보내는 톡 (줄마다 말풍선 하나, 비우면 캐릭터가 먼저)
  String userFirst;
  SceneDraft({List<LineDraft>? lines, List<ChoiceDraft>? choices, this.cutsceneHere = false, this.userFirst = ''})
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
  /// 컷씬으로 보여 줄 진짜 사진 (data: 주소, 캐릭터 사진함 사진 중 하나). 비우면 설명 카드
  String cutsceneImage;
  int fromHour;
  int toHour;
  String date;
  List<String> requiredFlags;
  /// 이어지는 대화: 이 대화(ID)가 끝나면 바로 이어서 나옴. 비우면 따로
  String follows;
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
    this.follows = '',
    this.keptMin = 0,
    this.keptStage = '',
    List<SceneDraft>? scenes,
  }) : scenes = scenes ?? [SceneDraft()];

  /// 설명이나 사진이 있으면 컷씬 (일상 대화는 컷씬 없음)
  bool get hasCutscene =>
      kind != DraftKind.daily && (cutscene.trim().isNotEmpty || cutsceneImage.isNotEmpty);

  /// 저장할 때 컷씬 설명 (비우면 제목)
  String get cutsceneLabel => cutscene.trim().isEmpty ? title.trim() : cutscene.trim();

  /// 사진이 들어갈 자리: 컷씬 + 사진 말풍선들 (장면 순서대로)
  List<PhotoSlot> get photoSlots => [
        if (hasCutscene) PhotoSlot(this),
        for (var i = 0; i < scenes.length; i++)
          for (final l in scenes[i].lines)
            if (l.isPhoto) PhotoSlot(this, line: l, sceneIndex: i),
      ];
}

/// 사진이 들어갈 자리 하나: 컷씬(line이 null)이거나 사진 말풍선
class PhotoSlot {
  PhotoSlot(this.event, {this.line, this.sceneIndex});
  final EventDraft event;
  final LineDraft? line;
  final int? sceneIndex;

  bool get isCutscene => line == null;
  /// 저장할 때 붙는 설명 (같은 설명끼리 사진을 같이 씀)
  String get label => line == null ? event.cutsceneLabel : (line!.photo.trim().isEmpty ? '사진' : line!.photo.trim());
  String get image => line?.photoImage ?? event.cutsceneImage;
  set image(String v) => line == null ? event.cutsceneImage = v : line!.photoImage = v;
  bool get filled => image.isNotEmpty;
  /// 다른 사진과 이어 붙여도 되는 설명인지 ('사진'처럼 기본 설명은 아무 사진이나 붙어서 뺌)
  bool get hasOwnLabel => label.isNotEmpty && label != '사진';
  String get where =>
      isCutscene ? '컷씬' : '장면 ${sceneIndex! + 1} 사진 말풍선 "${label.length > 18 ? '${label.substring(0, 18)}…' : label}"';
}

class ScenarioDraft {
  String id;
  String name = '';
  String statusMessage = '';
  String tagline = '';
  String tags = '';
  String avatarUrl = '';

  /// 대표(커버) 사진. 비우면 프로필 사진이 커버로 보여요
  String coverUrl = '';
  String setting = '';
  String world = '';
  String userRole = '';
  String secret = '';
  String quote = '';
  String themeColor = '';
  String chatBackground = '';
  String chatBackgroundImage = '';
  String gender = '';
  bool unlisted = false;
  /// 말랑이 종류: '' 이야기 말랑이, 'service' 서비스 말랑이
  String kind = '';
  /// 서비스 말랑이의 보내기 설정
  ServiceConfig service = const ServiceConfig();
  String bubbleStyle = '';
  String authorComment = '';
  double typing = 1.0;
  List<PersonalityTrait> traits = [];
  List<CharacterQuote> sampleQuotes = [];
  final List<FieldDraft> fields = [];
  final List<CastDraft> cast = [];
  final List<LoreDraft> lore = [];
  final List<StageDraft> stages = [];
  final List<EventDraft> events = [];

  /// 캐릭터 사진함: 이 캐릭터에 올린 사진 전부 (data: 주소). 컷씬과 사진 말풍선이 여기서 골라 씀
  final List<String> photos = [];

  /// 사진함 사진별 설명·'보낼 때' (사진 주소 → 설명·감정·상황·키워드)
  final Map<String, PhotoTrigger> photoTriggers = {};

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

  // ───────────────────────── 사진함 ─────────────────────────

  /// 사진을 사진함에 넣음 (이미 있으면 그대로)
  void addPhoto(String image) {
    if (image.isNotEmpty && !photos.contains(image)) photos.add(image);
  }

  /// 사진함에서 빼고, 그 사진을 쓰던 컷씬·말풍선도 비움
  void removePhoto(String image) {
    photos.remove(image);
    photoTriggers.remove(image);
    for (final s in photoSlots) {
      if (s.image == image) s.image = '';
    }
  }

  /// 사진이 들어갈 자리 전부 (대화 순서대로)
  List<PhotoSlot> get photoSlots => [for (final e in events) ...e.photoSlots];

  /// 이 사진을 쓰는 자리
  List<PhotoSlot> slotsUsing(String image) => [for (final s in photoSlots) if (s.image == image) s];

  /// 사진함에 있지만 컷씬·말풍선 어디에도 안 쓴 사진
  List<String> get unusedPhotos {
    final used = {for (final s in photoSlots) s.image};
    return [for (final p in photos) if (!used.contains(p)) p];
  }

  /// 사진 설명: 적어 둔 설명, 없으면 이 사진을 쓰는 첫 자리의 설명
  String captionOf(String image) {
    final own = photoTriggers[image]?.caption.trim() ?? '';
    if (own.isNotEmpty) return own;
    for (final s in slotsUsing(image)) {
      if (s.hasOwnLabel) return s.label;
    }
    return '';
  }

  // ───────────────────────── 시나리오 → 초안 ─────────────────────────

  factory ScenarioDraft.fromBundle(ScenarioBundle bundle) {
    final c = bundle.character;
    final d = ScenarioDraft(id: c.id)
      ..name = c.name
      ..statusMessage = c.statusMessage
      ..tagline = c.tagline
      ..tags = c.tags.join(', ')
      ..avatarUrl = c.avatarUrl
      ..coverUrl = c.coverUrl
      ..setting = c.worldviewPrompt
      ..world = c.worldSetting
      ..userRole = c.userRole
      ..secret = c.secret
      ..quote = c.quote
      ..themeColor = c.themeColor
      ..chatBackground = c.chatBackground
      ..chatBackgroundImage = c.chatBackgroundImage
      ..gender = c.gender
      ..unlisted = c.unlisted
      ..kind = c.kind
      ..service = c.service ?? const ServiceConfig()
      ..bubbleStyle = c.bubbleStyle
      ..authorComment = c.authorComment
      ..typing = c.typingSpeedMultiplier
      ..traits = [...c.traits]
      ..sampleQuotes = [...c.sampleQuotes];
    d.fields.addAll([for (final f in c.profileFields) FieldDraft(label: f.label, value: f.value, isSecret: f.isSecret)]);
    d.cast.addAll([for (final e in c.extraCast) CastDraft(name: e.name, role: e.role, speech: e.speech, characterId: e.characterId)]);
    d.lore.addAll([for (final e in c.lorebook) LoreDraft(keys: e.keys.join(', '), content: e.content, always: e.always)]);
    d.stages.addAll([for (final s in c.affectionStages) StageDraft(name: s.stageLabel, start: s.minScore)]);
    final events = [...bundle.events]..sort((a, b) => a.chapterOrder.compareTo(b.chapterOrder));
    for (final e in events) {
      d.events.add(eventFromBundle(bundle, e));
    }
    // 사진함: 캐릭터 사진함 + 예전 파일의 이벤트별 사진함 + 컷씬·말풍선이 쓰던 사진을 한곳에
    for (final ref in [...bundle.photoRefs, for (final e in events) ...e.photoRefs]) {
      if (bundle.resolveImage(ref) case final image?) d.addPhoto(image);
    }
    for (final s in d.photoSlots) {
      d.addPhoto(s.image);
    }
    for (final entry in [...bundle.photoTriggers.entries, for (final e in events) ...e.photoTriggers.entries]) {
      if (bundle.resolveImage(entry.key) case final image?) d.photoTriggers.putIfAbsent(image, () => entry.value);
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
                photoImage: bundle.photoFor(b.photoImage, b.photoLabel) ?? '',
                delay: b.delaySeconds,
              ),
          ],
          userFirst: n.userFirst.map((b) => b.text).join('\n'),
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
    final cutsceneImage = bundle.cutsceneImageFor(e) ?? '';
    return EventDraft(
      id: e.id,
      kind: e.isEnding
          ? DraftKind.ending
          : e.isAfterEnding
              ? DraftKind.afterEnding
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
      cutsceneImage: cutsceneImage,
      fromHour: e.realTime?.fromHour ?? 22,
      toHour: e.realTime?.toHour ?? 2,
      date: e.realTime?.date ?? '',
      requiredFlags: e.requiredFlags,
      follows: e.followsEventId ?? '',
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
        coverUrl: coverUrl,
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
            if (e.name.trim().isNotEmpty) ExtraCast(name: e.name.trim(), role: e.role.trim(), speech: e.speech.trim(), characterId: e.characterId),
        ],
        lorebook: [
          for (final e in lore)
            if (e.content.trim().isNotEmpty && (e.always || LoreEntry.splitKeys(e.keys).isNotEmpty))
              LoreEntry(keys: LoreEntry.splitKeys(e.keys), content: e.content.trim(), always: e.always),
        ],
        themeColor: themeColor,
        chatBackground: chatBackground,
        chatBackgroundImage: chatBackgroundImage,
        gender: gender,
        unlisted: unlisted,
        kind: kind,
        service: isService ? service : null,
        bubbleStyle: bubbleStyle,
        authorComment: authorComment.trim(),
        typingSpeedMultiplier: typing,
        affectionStages: isService ? const [] : buildStages(),
      );

  bool get isService => kind == CharacterModel.serviceKind;

  static String nodeId(EventDraft e, int sceneIndex) => '${e.id}_${sceneIndex + 1}';

  ScenarioEventModel buildEvent(EventDraft e, int order) {
    final cutsceneIndex = e.scenes.indexWhere((s) => s.cutsceneHere);
    final hasCutscene = e.hasCutscene;
    return ScenarioEventModel(
      id: e.id,
      characterId: id,
      chapterOrder: switch (e.kind) {
        DraftKind.ending => 999,
        DraftKind.afterEnding => 1000 + (order + 1) * 10,
        _ => (order + 1) * 10,
      },
      eventType: switch (e.kind) {
        DraftKind.story => ScenarioEventType.custom,
        DraftKind.daily => ScenarioEventType.daily,
        DraftKind.special => ScenarioEventType.special,
        DraftKind.ending => ScenarioEventType.ending,
        DraftKind.afterEnding => ScenarioEventType.afterEnding,
      },
      title: e.title.trim(),
      timeNotice: e.kind == DraftKind.special || e.notice.trim().isEmpty ? null : e.notice.trim(),
      stageLabel: !e.kind.needsStage || e.stage.trim().isEmpty ? null : e.stage.trim(),
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
      followsEventId: e.follows.isNotEmpty && e.kind.canFollow && events.any((o) => o.id == e.follows && o != e)
          ? e.follows
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
                delaySeconds: l.delay,
              ),
        ],
        userFirst: [
          for (final m in scene.userFirst.split('\n'))
            if (m.trim().isNotEmpty) ScriptBubblePiece(text: m.trim()),
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
      userBubbles: messages,
      affectionDelta: c.affection,
      addFlag: c.flag.trim().isEmpty ? null : c.flag.trim(),
      nextNodeId: nextIndex < 0 ? null : nodeId(e, nextIndex),
    );
  }

  ScenarioBundle toBundle() {
    // 서비스 말랑이는 이야기(이벤트·대사)가 없음
    if (isService) return ScenarioBundle(character: buildCharacter(), events: const [], nodes: const {});
    final events = <ScenarioEventModel>[];
    final nodes = <String, ScriptNodeModel>{};
    for (var i = 0; i < this.events.length; i++) {
      final e = this.events[i];
      events.add(buildEvent(e, i));
      for (final n in buildNodes(e)) {
        nodes[n.id] = n;
      }
    }
    return ScenarioBundle(
      character: buildCharacter(),
      events: events,
      nodes: nodes,
      images: collectImages(),
      photoRefs: [
        for (final p in photos)
          if (imageRef(p) case final ref?) ref,
      ],
      photoTriggers: {
        for (final entry in photoTriggers.entries)
          if (entry.value.hasData && photos.contains(entry.key))
            if (imageRef(entry.key) case final ref?) ref: entry.value,
      },
    );
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
        for (final p in photos)
          if (p.startsWith('data:')) imageId(p): p,
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
    if (isService) return out..addAll(serviceProblems());
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
      if (e.kind.needsStage && !names.contains(e.stage.trim())) {
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

  /// 설명 → 사진. 플레이할 때도 설명이 같은 컷씬·사진 말풍선·사진함 사진은 사진을 같이 씀 (ScenarioBundle.photoFor)
  Map<String, String> _photosByLabel() {
    final map = <String, String>{};
    for (final s in photoSlots) {
      if (s.filled && s.hasOwnLabel) map.putIfAbsent(s.label, () => s.image);
    }
    for (final p in photos) {
      final caption = photoTriggers[p]?.caption.trim() ?? '';
      if (caption.isNotEmpty) map.putIfAbsent(caption, () => p);
    }
    return map;
  }

  /// 사진을 안 골랐어도 설명이 같은 다른 자리의 사진이 나오면 그 사진
  String? sharedPhotoFor(PhotoSlot slot) => slot.hasOwnLabel ? _photosByLabel()[slot.label] : null;

  /// 서비스 말랑이 보내기 설정에서 고칠 곳
  List<String> serviceProblems() {
    final s = service;
    return [
      if (s.days.isEmpty) '[보내기] 보낼 요일을 하나 이상 골라 주세요.',
      if (s.times.isEmpty) '[보내기] 보낼 시간을 하나 이상 넣어 주세요.',
      if (s.mode == 'list' && !s.lines.any((l) => l.trim().isNotEmpty)) '[보내기] 보낼 문구를 하나 이상 적어 주세요.',
      if (s.mode == 'table' && s.rows.isEmpty) '[보내기] 데이터 표를 붙여 넣어 주세요.',
      if (s.mode == 'table' && s.template.trim().isEmpty) '[보내기] 보낼 말 틀을 적어 주세요.',
      if (s.mode == 'ai' && s.aiPrompt.trim().isEmpty) '[보내기] AI가 어떤 톡을 쓸지 적어 주세요.',
    ];
  }

  /// 저장하기 전에 빈 사진 자리를 채워 줌. 채운 자리 수를 돌려줌
  /// 1) 설명이 같은 컷씬·사진 말풍선·사진함 사진의 사진
  /// 2) 사진함에 안 쓴 사진이 1장 남고 빈 자리(같은 설명끼리는 한 자리)도 1곳이면 그 사진
  int autoLinkPhotos() {
    var linked = 0;
    final byLabel = _photosByLabel();
    for (final s in photoSlots) {
      if (s.filled || !s.hasOwnLabel) continue;
      final shared = byLabel[s.label];
      if (shared == null) continue;
      s.image = shared;
      addPhoto(shared);
      linked++;
    }
    final empty = [for (final s in photoSlots) if (!s.filled) s];
    final unused = unusedPhotos;
    if (empty.isEmpty || unused.length != 1) return linked;
    final groups = {for (final s in empty) s.hasOwnLabel ? s.label : identityHashCode(s)};
    if (groups.length != 1) return linked;
    for (final s in empty) {
      s.image = unused.single;
      linked++;
    }
    return linked;
  }

  /// 사진함에 안 쓴 사진이 있는데 아직 사진을 안 고른 컷씬·사진 말풍선 (플레이 때 설명 카드로 나옴)
  List<PhotoSlot> missingPhotos() {
    if (unusedPhotos.isEmpty) return const [];
    final byLabel = _photosByLabel();
    return [
      for (final s in photoSlots)
        if (!s.filled && !(s.hasOwnLabel && byLabel.containsKey(s.label))) s,
    ];
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
