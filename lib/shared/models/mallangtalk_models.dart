/// [초보자 노트] 기획서의 8개 데이터베이스(DB) 테이블과 1:1로 대응하는 데이터 모델 파일입니다.
/// [업데이트 반영]
/// 1. 괄호 지문 없이 실제 카톡처럼 짧게 여러 번 끊어 치는 대사(TypingPiece)와 타자 속도(typingSpeed) 지원
/// 2. 유저와 캐릭터 모두 대화방 안에 직접 사진(카메라/컷씬 사진 말풍선)을 올릴 수 있도록 photoTag / photoCaption 지원
/// 3. 호감도 점수는 화면에 노출하지 않고 내부에서만 계산
/// 4. 모든 모델에 fromJson이 있어서 assets/scenarios/*.json 시나리오 파일(나중엔 서버 DB 응답)을 그대로 읽어옴

/// 1. 호감도 구간 정의 모델 (내부 판정 및 아이콘 색상 변화용)
class AffectionStage {
  final int minScore;
  final int maxScore;
  final String stageLabel;

  const AffectionStage({
    required this.minScore,
    required this.maxScore,
    required this.stageLabel,
  });

  factory AffectionStage.fromJson(Map<String, dynamic> json) {
    return AffectionStage(
      minScore: json['min'] as int,
      maxScore: json['max'] as int,
      stageLabel: json['label'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'min': minScore, 'max': maxScore, 'label': stageLabel};

  bool contains(int score) => score >= minScore && score <= maxScore;
}

/// 캐릭터 성격에 맞춘 타자 스타일 (제작 화면에서 고르고, 값은 typingSpeedMultiplier로 저장)
class TypingStyle {
  final String label;
  final String note;
  final double multiplier;

  const TypingStyle(this.label, this.note, this.multiplier);

  static const all = [
    TypingStyle('번개같이', '생각보다 손이 먼저 나가는 성격', 0.6),
    TypingStyle('빠릿빠릿', '수다스럽고 답장이 빠른 편', 0.8),
    TypingStyle('보통', '평범한 속도', 1.0),
    TypingStyle('느긋하게', '한 글자씩 신중하게 고르는 편', 1.3),
    TypingStyle('한참 고민', '썼다 지웠다 하는 무뚝뚝한 성격', 1.7),
  ];

  /// 배율에 가장 가까운 스타일
  static TypingStyle closest(double multiplier) {
    var best = all.first;
    for (final style in all) {
      if ((style.multiplier - multiplier).abs() < (best.multiplier - multiplier).abs()) {
        best = style;
      }
    }
    return best;
  }
}

/// 2. 캐릭터 기본 설정 모델 (DB 테이블: characters)
class CharacterModel {
  final String id;
  final String creatorId;
  final String name;
  final String statusMessage; // 카톡 프로필 상태메시지
  final String avatarUrl;
  final String worldviewPrompt;
  /// 캐릭터 기본 타자 속도 배율 (0.7 = 손이 빨라서 답장이 빠름, 1.3 = 신중해서 천천히 침)
  final double typingSpeedMultiplier;
  final List<AffectionStage> affectionStages;
  final bool isPublished;

  const CharacterModel({
    required this.id,
    required this.creatorId,
    required this.name,
    required this.statusMessage,
    required this.avatarUrl,
    required this.worldviewPrompt,
    this.typingSpeedMultiplier = 1.0,
    required this.affectionStages,
    this.isPublished = false,
  });

  factory CharacterModel.fromJson(Map<String, dynamic> json) {
    return CharacterModel(
      id: json['id'] as String,
      creatorId: json['creator_id'] as String,
      name: json['name'] as String,
      statusMessage: json['status_message'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      worldviewPrompt: json['worldview_prompt'] as String? ?? '',
      typingSpeedMultiplier:
          (json['typing_speed_multiplier'] as num?)?.toDouble() ?? 1.0,
      affectionStages: [
        for (final stage in json['affection_stages'] as List? ?? const [])
          AffectionStage.fromJson(stage as Map<String, dynamic>),
      ],
      isPublished: json['is_published'] == true || json['is_published'] == 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'creator_id': creatorId,
        'name': name,
        'status_message': statusMessage,
        'avatar_url': avatarUrl,
        'worldview_prompt': worldviewPrompt,
        'typing_speed_multiplier': typingSpeedMultiplier,
        'affection_stages': [for (final stage in affectionStages) stage.toJson()],
        'is_published': isPublished,
      };

  /// 점수가 속한 호감도 단계 (구간 밖이면 가장 가까운 단계)
  AffectionStage? stageFor(int score) {
    for (final stage in affectionStages) {
      if (stage.contains(score)) return stage;
    }
    if (affectionStages.isEmpty) return null;
    return score < affectionStages.first.minScore
        ? affectionStages.first
        : affectionStages.last;
  }

  AffectionStage? stageNamed(String? label) {
    if (label == null) return null;
    return affectionStages.where((s) => s.stageLabel == label).firstOrNull;
  }
}

/// 3. 동일 제작자 캐릭터 간 관계도 모델 (DB 테이블: character_relations)
class CharacterRelationModel {
  final String id;
  final String creatorId;
  final String fromCharacterId;
  final String toCharacterId;
  final String relationLabel;
  final int targetMinAffection;
  final String reactionHint;

  const CharacterRelationModel({
    required this.id,
    required this.creatorId,
    required this.fromCharacterId,
    required this.toCharacterId,
    required this.relationLabel,
    required this.targetMinAffection,
    required this.reactionHint,
  });
}

/// 이벤트 종류 (DB의 event_type 문자열과 대응)
class ScenarioEventType {
  ScenarioEventType._();

  static const String autoStory = 'auto_story'; // AI가 자동 생성한 호감도 이벤트
  static const String custom = 'custom'; // 제작자가 직접 만든 호감도 이벤트
  static const String intrusion = 'intrusion'; // 2단계: 타 캐릭터 난입/단톡
  static const String ending = 'ending'; // 공략 완료 후 재생되는 엔딩
  /// 호감도 이벤트 사이사이에 끼는 일상 대화 (공략 완료 판정에는 안 들어감)
  static const String daily = 'daily';
}

/// 4. 시나리오 이벤트 모델 (DB 테이블: scenario_events)
class ScenarioEventModel {
  final String id;
  final String characterId;
  final int chapterOrder;
  final String eventType;
  final String title;
  /// 이벤트 시작 전에 대화방 가운데 뜨는 시간 안내 (예: '그날 밤', '다음 날 점심')
  final String? timeNotice;
  final int requiredAffection;
  final List<String> requiredFlags;
  final String? cutscenePhotoTitle;
  final String? cutsceneImageUrl; // 실제 CG 이미지 경로 (없으면 제목만 있는 자리표시 카드로 보여줌)
  final int? cutsceneTriggerStep; // 이 단계(stepOrder)의 대사가 끝나면 컷씬(CG)이 전체 화면으로 뜸
  final List<String> participantCharacterIds;
  /// 이 대화가 속한 호감도 단계 이름 (캐릭터의 affectionStages 중 하나)
  /// 이벤트는 그 단계에 도달하면 열리고, 일상 대화는 그 단계에 머무는 동안에만 나옵니다.
  final String? stageLabel;
  /// 이 점수를 넘으면 더는 안 나옴 (주로 일상 대화용, 비우면 제한 없음)
  final int? maxAffection;

  const ScenarioEventModel({
    required this.id,
    required this.characterId,
    required this.chapterOrder,
    required this.eventType,
    required this.title,
    this.timeNotice,
    this.requiredAffection = 0,
    this.requiredFlags = const [],
    this.cutscenePhotoTitle,
    this.cutsceneImageUrl,
    this.cutsceneTriggerStep,
    this.participantCharacterIds = const [],
    this.stageLabel,
    this.maxAffection,
  });

  bool get hasCutscene => cutsceneTriggerStep != null;
  bool get isEnding => eventType == ScenarioEventType.ending;
  bool get isDaily => eventType == ScenarioEventType.daily;

  /// 공략 완료 판정에 들어가는 '호감도 이벤트'인지 (엔딩·난입 이벤트는 제외)
  bool get isAffectionEvent =>
      eventType == ScenarioEventType.autoStory ||
      eventType == ScenarioEventType.custom;

  factory ScenarioEventModel.fromJson(Map<String, dynamic> json) {
    final unlock = json['unlock_condition'] as Map<String, dynamic>? ?? const {};
    return ScenarioEventModel(
      id: json['id'] as String,
      characterId: json['character_id'] as String,
      chapterOrder: json['chapter_order'] as int,
      eventType: json['event_type'] as String? ?? ScenarioEventType.custom,
      title: json['title'] as String,
      timeNotice: json['time_notice'] as String?,
      requiredAffection: unlock['min_affection'] as int? ?? 0,
      requiredFlags: [
        for (final flag in unlock['required_flags'] as List? ?? const [])
          flag as String,
      ],
      cutscenePhotoTitle: json['cutscene_title'] as String?,
      cutsceneImageUrl: json['cutscene_image_url'] as String?,
      cutsceneTriggerStep: json['cutscene_trigger_step'] as int?,
      participantCharacterIds: [
        for (final id in json['participants'] as List? ?? const []) id as String,
      ],
      stageLabel: json['stage'] as String?,
      maxAffection: unlock['max_affection'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'character_id': characterId,
        'chapter_order': chapterOrder,
        'event_type': eventType,
        'title': title,
        if (timeNotice != null) 'time_notice': timeNotice,
        if (stageLabel != null) 'stage': stageLabel,
        'unlock_condition': {
          'min_affection': requiredAffection,
          if (maxAffection != null) 'max_affection': maxAffection,
          if (requiredFlags.isNotEmpty) 'required_flags': requiredFlags,
        },
        if (cutscenePhotoTitle != null) 'cutscene_title': cutscenePhotoTitle,
        if (cutsceneImageUrl != null) 'cutscene_image_url': cutsceneImageUrl,
        if (cutsceneTriggerStep != null) 'cutscene_trigger_step': cutsceneTriggerStep,
        if (participantCharacterIds.isNotEmpty) 'participants': participantCharacterIds,
      };
}

/// 5. 말풍선 한 줄 단위 모델 (타자 속도 조절 & 사진 첨부 지원)
class ScriptBubblePiece {
  final String text;
  /// 이 말풍선을 칠 때 타자 빠르기 (0.6: 급하게 빨리 침, 1.0: 보통, 1.5: 망설이며 느리게 침)
  final double speedFactor;
  /// 대화방에 사진을 찍어 올리는 말풍선일 경우 사진 제목/경로
  final String? photoLabel;

  const ScriptBubblePiece({
    required this.text,
    this.speedFactor = 1.0,
    this.photoLabel,
  });

  bool get hasPhoto => photoLabel != null && photoLabel!.isNotEmpty;

  factory ScriptBubblePiece.fromJson(Map<String, dynamic> json) {
    return ScriptBubblePiece(
      text: json['text'] as String? ?? '',
      speedFactor: (json['speed'] as num?)?.toDouble() ?? 1.0,
      photoLabel: json['photo'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        if (speedFactor != 1.0) 'speed': speedFactor,
        if (hasPhoto) 'photo': photoLabel,
      };
}

/// 6. 선택지 모델 (내가 선택지를 눌렀을 때도 짧게 여러 마디로 끊어서 보내거나 사진을 찍어 보낼 수 있음!)
class ChoiceOption {
  final String id;
  final String buttonLabel; // 선택지 버튼에 보이는 요약 텍스트
  final List<ScriptBubblePiece> userBubbles; // 선택 시 내가 연속으로 보내는 말풍선들
  final int affectionDelta; // 내부에서만 계산 (화면에 표시 안 함!)
  final String? addFlag;
  final String? nextNodeId;

  const ChoiceOption({
    required this.id,
    required this.buttonLabel,
    required this.userBubbles,
    required this.affectionDelta,
    this.addFlag,
    this.nextNodeId,
  });

  factory ChoiceOption.fromJson(Map<String, dynamic> json) {
    return ChoiceOption(
      id: json['choice_id'] as String,
      buttonLabel: json['label'] as String,
      userBubbles: [
        for (final bubble in json['user_messages'] as List? ?? const [])
          ScriptBubblePiece.fromJson(bubble as Map<String, dynamic>),
      ],
      affectionDelta: json['affection_delta'] as int? ?? 0,
      addFlag: json['add_flag'] as String?,
      nextNodeId: json['next_node_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'choice_id': id,
        'label': buttonLabel,
        'user_messages': [for (final b in userBubbles) b.toJson()],
        'affection_delta': affectionDelta,
        if (addFlag != null) 'add_flag': addFlag,
        if (nextNodeId != null) 'next_node_id': nextNodeId,
      };
}

/// 7. 대사 및 선택지 분기 노드 모델 (DB 테이블: script_nodes)
class ScriptNodeModel {
  final String id;
  final String eventId;
  final int stepOrder;
  final String speakerCharacterId;
  final List<ScriptBubblePiece> characterBubbles; // 캐릭터가 끊어서 치는 말풍선 배열
  final List<ChoiceOption> choices;

  const ScriptNodeModel({
    required this.id,
    required this.eventId,
    required this.stepOrder,
    required this.speakerCharacterId,
    required this.characterBubbles,
    required this.choices,
  });

  factory ScriptNodeModel.fromJson(Map<String, dynamic> json) {
    return ScriptNodeModel(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      stepOrder: json['step_order'] as int,
      speakerCharacterId: json['speaker_character_id'] as String,
      characterBubbles: [
        for (final bubble in json['messages'] as List? ?? const [])
          ScriptBubblePiece.fromJson(bubble as Map<String, dynamic>),
      ],
      choices: [
        for (final choice in json['choices'] as List? ?? const [])
          ChoiceOption.fromJson(choice as Map<String, dynamic>),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'event_id': eventId,
        'step_order': stepOrder,
        'speaker_character_id': speakerCharacterId,
        'messages': [for (final b in characterBubbles) b.toJson()],
        if (choices.isNotEmpty) 'choices': [for (final c in choices) c.toJson()],
      };
}

/// 시나리오 묶음: 캐릭터 1명 + 이벤트 목록 + 대사 노드 목록
/// assets/scenarios/*.json 파일 하나가 이 모양이고, 4단계에서는 서버 API가 같은 모양으로 내려줄 예정입니다.
class ScenarioBundle {
  final CharacterModel character;
  final List<ScenarioEventModel> events; // chapterOrder 순으로 정렬됨
  final Map<String, ScriptNodeModel> nodes; // 노드 ID로 바로 찾기

  const ScenarioBundle({
    required this.character,
    required this.events,
    required this.nodes,
  });

  factory ScenarioBundle.fromJson(Map<String, dynamic> json) {
    final events = [
      for (final event in json['events'] as List)
        ScenarioEventModel.fromJson(event as Map<String, dynamic>),
    ]..sort((a, b) => a.chapterOrder.compareTo(b.chapterOrder));
    return ScenarioBundle(
      character: CharacterModel.fromJson(json['character'] as Map<String, dynamic>),
      events: events,
      nodes: {
        for (final node in json['script_nodes'] as List)
          (node as Map<String, dynamic>)['id'] as String:
              ScriptNodeModel.fromJson(node),
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'format': 'mallangtalk-scenario-v1',
        'character': character.toJson(),
        'events': [for (final e in events) e.toJson()],
        'script_nodes': [for (final n in nodes.values) n.toJson()],
      };

  /// 이 이벤트가 열리는 호감도 구간. 단계 이름이 있으면 그 단계 시작 점수부터 열리고,
  /// 일상 대화는 그 단계 끝 점수까지만 나옵니다.
  ({int min, int? max}) affectionRangeOf(ScenarioEventModel event) {
    final stage = character.stageNamed(event.stageLabel);
    var min = event.requiredAffection;
    int? max = event.maxAffection;
    if (stage != null) {
      if (stage.minScore > min) min = stage.minScore;
      if (event.isDaily && (max == null || stage.maxScore < max)) max = stage.maxScore;
    }
    return (min: min, max: max);
  }

  /// 이벤트의 첫 대사 노드 (stepOrder가 가장 작은 노드, 같으면 파일에 먼저 적힌 노드)
  ScriptNodeModel? firstNodeOf(String eventId) {
    ScriptNodeModel? first;
    for (final node in nodes.values) {
      if (node.eventId != eventId) continue;
      if (first == null || node.stepOrder < first.stepOrder) first = node;
    }
    return first;
  }
}

/// 8. 실제 채팅창에 표시되는 개별 말풍선 로그 모델 (DB 테이블: chat_logs)
class ChatMessageLog {
  final String id;
  final bool isUser;
  /// 말풍선이 아니라 대화방 가운데 뜨는 안내 문구 (시간 경과, 공략 완료 등)
  final bool isSystem;
  final String speakerCharacterId;
  final String speakerName;
  final String text;
  final String? photoLabel; // 사진 말풍선일 경우 사진 설명/경로
  final bool isUnread;      // 카톡 읽음 '1' 표시 여부
  final DateTime timestamp;

  const ChatMessageLog({
    required this.id,
    required this.isUser,
    this.isSystem = false,
    required this.speakerCharacterId,
    required this.speakerName,
    required this.text,
    this.photoLabel,
    this.isUnread = false,
    required this.timestamp,
  });

  bool get hasPhoto => photoLabel != null && photoLabel!.isNotEmpty;

  /// 진행 저장용 (브라우저 저장소에 대화 기록을 남길 때 사용)
  Map<String, dynamic> toJson() => {
        'id': id,
        'is_user': isUser,
        'is_system': isSystem,
        'speaker_character_id': speakerCharacterId,
        'speaker_name': speakerName,
        'text': text,
        if (photoLabel != null) 'photo': photoLabel,
        'is_unread': isUnread,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessageLog.fromJson(Map<String, dynamic> json) {
    return ChatMessageLog(
      id: json['id'] as String,
      isUser: json['is_user'] as bool? ?? false,
      isSystem: json['is_system'] as bool? ?? false,
      speakerCharacterId: json['speaker_character_id'] as String? ?? '',
      speakerName: json['speaker_name'] as String? ?? '',
      text: json['text'] as String? ?? '',
      photoLabel: json['photo'] as String?,
      isUnread: json['is_unread'] as bool? ?? false,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }

  ChatMessageLog copyWith({bool? isUnread}) {
    return ChatMessageLog(
      id: id,
      isUser: isUser,
      isSystem: isSystem,
      speakerCharacterId: speakerCharacterId,
      speakerName: speakerName,
      text: text,
      photoLabel: photoLabel,
      isUnread: isUnread ?? this.isUnread,
      timestamp: timestamp,
    );
  }
}
