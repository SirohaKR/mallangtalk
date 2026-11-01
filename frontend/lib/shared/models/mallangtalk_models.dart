/// [초보자 노트] 기획서의 8개 데이터베이스(DB) 테이블과 1:1로 대응하는 데이터 모델 파일입니다.
/// [업데이트 반영]
/// 1. 괄호 지문 없이 실제 카톡처럼 짧게 여러 번 끊어 치는 대사(TypingPiece)와 타자 속도(typingSpeed) 지원
/// 2. 유저와 캐릭터 모두 대화방 안에 직접 사진(카메라/컷씬 사진 말풍선)을 올릴 수 있도록 photoTag / photoCaption 지원
/// 3. 호감도 점수는 화면에 노출하지 않고 내부에서만 계산
/// 4. 모든 모델에 fromJson이 있어서 시나리오 파일(나중엔 서버 DB 응답)을 그대로 읽어옴

import '../utils/korean.dart';

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

  Map<String, dynamic> toJson() =>
      {'min': minScore, 'max': maxScore, 'label': stageLabel};

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
      if ((style.multiplier - multiplier).abs() <
          (best.multiplier - multiplier).abs()) {
        best = style;
      }
    }
    return best;
  }
}

/// 캐릭터 프로필 항목 (나이: 24세 같은 것). 비밀 항목은 상세 화면엔 안 보이고 AI만 참고
class ProfileField {
  final String label;
  final String value;
  final bool isSecret;

  const ProfileField(
      {required this.label, required this.value, this.isSecret = false});

  factory ProfileField.fromJson(Map<String, dynamic> json) => ProfileField(
        label: json['label'] as String? ?? '',
        value: json['value'] as String? ?? '',
        isSecret: json['is_secret'] == true,
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'value': value,
        if (isSecret) 'is_secret': true,
      };
}

/// 성격 막대 (내향 ←30%→ 외향). right가 없으면 한쪽짜리 (신중함 80%)
class PersonalityTrait {
  final String left;
  final String? right;
  final int percent;

  const PersonalityTrait({required this.left, this.right, this.percent = 50});

  factory PersonalityTrait.fromJson(Map<String, dynamic> json) =>
      PersonalityTrait(
        left: json['left'] as String? ?? '',
        right: json['right'] as String?,
        percent: ((json['percent'] as num?)?.toInt() ?? 50).clamp(0, 100),
      );

  Map<String, dynamic> toJson() => {
        'left': left,
        if (right != null && right!.isNotEmpty) 'right': right,
        'percent': percent,
      };
}

/// 캐릭터를 보여주는 대표 대사 예시 (상황과 함께). AI 자유대화가 말투를 따라 할 때도 씀
class CharacterQuote {
  final String body;
  final String situation;

  const CharacterQuote({required this.body, this.situation = ''});

  factory CharacterQuote.fromJson(Map<String, dynamic> json) => CharacterQuote(
        body: json['body'] as String? ?? '',
        situation: json['situation'] as String? ?? '',
      );

  Map<String, dynamic> toJson() =>
      {'body': body, if (situation.isNotEmpty) 'situation': situation};
}

/// 대화에 이름이 나오는 주변 인물 (친구, 가족, 반려동물 등)
class ExtraCast {
  final String name;
  final String role;
  final String speech;

  /// 내가 만든 다른 캐릭터를 불러와 연결했으면 그 캐릭터 ID (관계도에 쓰임)
  final String? characterId;

  const ExtraCast(
      {required this.name, this.role = '', this.speech = '', this.characterId});

  factory ExtraCast.fromJson(Map<String, dynamic> json) => ExtraCast(
        name: json['name'] as String? ?? '',
        role: json['role'] as String? ?? '',
        speech: json['speech'] as String? ?? '',
        characterId: json['character_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (role.isNotEmpty) 'role': role,
        if (speech.isNotEmpty) 'speech': speech,
        if (characterId != null) 'character_id': characterId,
      };
}

/// 대화방 로어북의 기억 한 개: 몇 턴마다 AI가 그동안 대화를 요약해 남기거나 유저가 로어북 창에서 적음.
/// 저장은 '제목\n세부사항' 글자 하나로 (예전 한 줄 기억은 제목 없이 세부사항만)
class MemoryNote {
  final String title;
  final String detail;
  const MemoryNote({this.title = '', this.detail = ''});

  factory MemoryNote.parse(String text) {
    final i = text.indexOf('\n');
    if (i < 0) return MemoryNote(detail: text.trim());
    return MemoryNote(title: text.substring(0, i).trim(), detail: text.substring(i + 1).trim());
  }

  String encode() => title.trim().isEmpty ? detail.trim() : '${title.trim()}\n${detail.trim()}';

  /// AI에게 넘길 한 줄
  String get forAi => title.isEmpty ? detail : detail.isEmpty ? title : '$title: $detail';
}

/// 2. 캐릭터 기본 설정 모델 (DB 테이블: characters)
/// 설정 항목은 쨋뀨의 캐릭터 아카이브 loreshelf(인물·유저·기타 인물 카드)를 참고했어요.
/// 서비스 말랑이가 언제 무슨 톡을 보낼지
class ServiceConfig {
  /// 보내는 요일 (1 월요일 ~ 7 일요일)
  final List<int> days;

  /// 보내는 시각 'HH:MM' (24시간)
  final List<String> times;

  /// 문구 만드는 법: list(써 둔 문구 중 랜덤) / table(데이터 표 한 줄을 틀에 넣기) / ai(매번 AI가 씀)
  final String mode;
  final List<String> lines;

  /// 데이터 표: 칸 이름과 줄들
  final List<String> columns;
  final List<List<String>> rows;

  /// 데이터 표 모드의 보낼 말 틀 ({칸 이름}, {이름}, {날짜}, {요일}, {숫자})
  final String template;

  /// AI 모드: 어떤 톡을 쓸지 (예: 오늘의 운세를 짧고 다정하게)
  final String aiPrompt;

  /// 한 바퀴 돌 때까지 같은 문구·줄이 안 나오게
  final bool noRepeat;

  /// 대화방에 '한 번 더 뽑기' 버튼
  final bool reroll;

  /// 대화를 시작할 때 유저에게 물어볼 정보 (예: 띠, 생일, 별자리). 페르소나 대신 이걸 받음.
  /// 데이터 표에 같은 이름의 칸이 있으면 유저 값과 맞는 줄에서 고르고, 틀에 {띠}처럼 넣을 수도 있음
  final List<String> ask;

  /// 유저가 답장하면: 'ai' AI가 답함(기본) / 'list' [replyLines] 중 랜덤 / 'none' 읽고 답 안 함(읽씹)
  final String reply;

  /// 정해 둔 답 (reply가 'list'일 때, {이름} 등 넣을 수 있음)
  final List<String> replyLines;

  static const replyModes = ['ai', 'list', 'none'];

  const ServiceConfig({
    this.days = const [1, 2, 3, 4, 5, 6, 7],
    this.times = const ['08:00'],
    this.mode = 'list',
    this.lines = const [],
    this.columns = const [],
    this.rows = const [],
    this.template = '',
    this.aiPrompt = '',
    this.noRepeat = true,
    this.reroll = true,
    this.ask = const [],
    this.reply = 'ai',
    this.replyLines = const [],
  });

  static const modes = ['list', 'table', 'ai'];

  ServiceConfig copyWith({
    List<int>? days,
    List<String>? times,
    String? mode,
    List<String>? lines,
    List<String>? columns,
    List<List<String>>? rows,
    String? template,
    String? aiPrompt,
    bool? noRepeat,
    bool? reroll,
    List<String>? ask,
    String? reply,
    List<String>? replyLines,
  }) =>
      ServiceConfig(
        days: days ?? this.days,
        times: times ?? this.times,
        mode: mode ?? this.mode,
        lines: lines ?? this.lines,
        columns: columns ?? this.columns,
        rows: rows ?? this.rows,
        template: template ?? this.template,
        aiPrompt: aiPrompt ?? this.aiPrompt,
        noRepeat: noRepeat ?? this.noRepeat,
        reroll: reroll ?? this.reroll,
        ask: ask ?? this.ask,
        reply: reply ?? this.reply,
        replyLines: replyLines ?? this.replyLines,
      );

  factory ServiceConfig.fromJson(Map<String, dynamic> json) => ServiceConfig(
        days: [
          for (final d in json['days'] as List? ?? const [1, 2, 3, 4, 5, 6, 7])
            (d as num).toInt()
        ],
        times: [
          for (final t in json['times'] as List? ?? const ['08:00']) t as String
        ],
        mode: json['mode'] as String? ?? 'list',
        lines: [
          for (final l in json['lines'] as List? ?? const []) l as String
        ],
        columns: [
          for (final c in json['columns'] as List? ?? const []) c as String
        ],
        rows: [
          for (final r in json['rows'] as List? ?? const [])
            [for (final v in r as List) '$v'],
        ],
        template: json['template'] as String? ?? '',
        aiPrompt: json['ai_prompt'] as String? ?? '',
        noRepeat: json['no_repeat'] != false,
        reroll: json['reroll'] != false,
        ask: [for (final a in json['ask'] as List? ?? const []) '$a'],
        reply: replyModes.contains(json['reply']) ? json['reply'] as String : 'ai',
        replyLines: [for (final l in json['reply_lines'] as List? ?? const []) '$l'],
      );

  Map<String, dynamic> toJson() => {
        'days': days,
        'times': times,
        'mode': mode,
        if (lines.isNotEmpty) 'lines': lines,
        if (columns.isNotEmpty) 'columns': columns,
        if (rows.isNotEmpty) 'rows': rows,
        if (template.isNotEmpty) 'template': template,
        if (aiPrompt.isNotEmpty) 'ai_prompt': aiPrompt,
        'no_repeat': noRepeat,
        'reroll': reroll,
        if (ask.isNotEmpty) 'ask': ask,
        if (reply != 'ai') 'reply': reply,
        if (replyLines.isNotEmpty) 'reply_lines': replyLines,
      };

  /// 물어볼 정보 중 데이터 표에도 있는 칸이면 그 칸의 값들 (고르기 버튼으로 보여 줌)
  List<String> choicesFor(String field) {
    final c = columns.indexWhere((x) => x.trim() == field.trim());
    if (c < 0) return const [];
    return {
      for (final r in rows)
        if (c < r.length && r[c].trim().isNotEmpty) r[c].trim()
    }.toList();
  }
}

class CharacterModel {
  final String id;
  final String creatorId;
  final String name;
  final String statusMessage; // 카톡 프로필 상태메시지
  /// 프로필·썸네일 이미지 (앱 안 이미지 경로, 인터넷 주소, 또는 직접 올린 사진의 data: 주소). 비우면 이름 첫 글자 카드
  final String avatarUrl;

  /// 대표 사진: 말랑이 찾기 카드와 상세 화면 맨 위 커버. 비우면 프로필 사진을 씀
  final String coverUrl;

  /// 받아오기 갤러리에 보이는 한줄 소개
  final String tagline;

  /// 갤러리 태그 (예: 남사친, 고양이집사)
  final List<String> tags;

  /// 캐릭터 설정 (성격·말투·습관·취미). 상세 화면에 보이고 AI 생성과 자유대화의 핵심 설정
  final String worldviewPrompt;

  /// 세계관 설정 요약 (배경이 되는 곳·시대·분위기). 상세 화면에 보임
  final String worldSetting;

  /// 대표 대사 한 줄 (상세 화면 맨 위)
  final String quote;

  /// 프로필 항목 (나이, 직업, 생일, MBTI 등)
  final List<ProfileField> profileFields;

  /// 성격 막대
  final List<PersonalityTrait> traits;

  /// 대사 예시
  final List<CharacterQuote> sampleQuotes;

  /// 비밀 설정 (화면엔 안 보이고, 이야기와 AI가 천천히 드러내는 것)
  final String secret;

  /// 유저 설정: 이 이야기에서 나는 누구인지 (예: {이름} · 1년 전 팀플에서 만난 친구)
  final String userRole;

  /// 주변 인물
  final List<ExtraCast> extraCast;

  /// 캐릭터 대표 색 (#RRGGBB, 비우면 기본 분홍)
  final String themeColor;

  /// 성별: 'male' / 'female' / 'none'(미정 → AI가 성별을 드러내지 않게 씀) / ''(안 고름)
  final String gender;

  /// 말랑이 찾기에 안 올림 (내 말랑이에서만 보임)
  final bool unlisted;

  /// 말랑이 종류: '' = 이야기 말랑이, 'service' = 서비스 말랑이 (정해진 때 먼저 톡, 호감도·엔딩 없음)
  final String kind;

  /// 서비스 말랑이의 보내기 설정 (이야기 말랑이는 null)
  final ServiceConfig? service;

  /// 톡방 배경: '' = 대표색 연하게, 'white' = 흰색, 'photo' = [chatBackgroundImage] 사진
  final String chatBackground;

  /// 톡방 배경 사진 (data: 주소 또는 서버 사진 주소)
  final String chatBackgroundImage;

  /// 내 말풍선 색: '' = 대표색, 'pink' = 기본 분홍
  final String bubbleStyle;

  /// 작가 코멘트: 제작자가 플레이어에게 남기는 한마디 (상세 화면 맨 아래)
  final String authorComment;

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
    this.coverUrl = '',
    this.tagline = '',
    this.tags = const [],
    required this.worldviewPrompt,
    this.worldSetting = '',
    this.quote = '',
    this.profileFields = const [],
    this.traits = const [],
    this.sampleQuotes = const [],
    this.secret = '',
    this.userRole = '',
    this.extraCast = const [],
    this.themeColor = '',
    this.gender = '',
    this.unlisted = false,
    this.kind = '',
    this.service,
    this.chatBackground = '',
    this.chatBackgroundImage = '',
    this.bubbleStyle = '',
    this.authorComment = '',
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
      coverUrl: json['cover_url'] as String? ?? '',
      tagline: json['tagline'] as String? ?? '',
      tags: [for (final t in json['tags'] as List? ?? const []) t as String],
      worldviewPrompt: json['worldview_prompt'] as String? ?? '',
      worldSetting: json['world_setting'] as String? ?? '',
      quote: json['quote'] as String? ?? '',
      profileFields: [
        for (final f in json['profile_fields'] as List? ?? const [])
          ProfileField.fromJson(f as Map<String, dynamic>),
      ],
      traits: [
        for (final t in json['traits'] as List? ?? const [])
          PersonalityTrait.fromJson(t as Map<String, dynamic>),
      ],
      sampleQuotes: [
        for (final q in json['sample_quotes'] as List? ?? const [])
          CharacterQuote.fromJson(q as Map<String, dynamic>),
      ],
      secret: json['secret'] as String? ?? '',
      userRole: json['user_role'] as String? ?? '',
      extraCast: [
        for (final e in json['extra_cast'] as List? ?? const [])
          ExtraCast.fromJson(e as Map<String, dynamic>),
      ],
      themeColor: json['theme_color'] as String? ?? '',
      gender: json['gender'] as String? ?? '',
      unlisted: json['unlisted'] == true,
      kind: json['kind'] as String? ?? '',
      service: json['service'] is Map
          ? ServiceConfig.fromJson(
              Map<String, dynamic>.from(json['service'] as Map))
          : null,
      chatBackground: json['chat_background'] as String? ?? '',
      chatBackgroundImage: json['chat_background_image'] as String? ?? '',
      bubbleStyle: json['bubble_style'] as String? ?? '',
      authorComment: json['author_comment'] as String? ?? '',
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
        if (coverUrl.isNotEmpty) 'cover_url': coverUrl,
        if (tagline.isNotEmpty) 'tagline': tagline,
        if (tags.isNotEmpty) 'tags': tags,
        'worldview_prompt': worldviewPrompt,
        if (worldSetting.isNotEmpty) 'world_setting': worldSetting,
        if (quote.isNotEmpty) 'quote': quote,
        if (profileFields.isNotEmpty)
          'profile_fields': [for (final f in profileFields) f.toJson()],
        if (traits.isNotEmpty) 'traits': [for (final t in traits) t.toJson()],
        if (sampleQuotes.isNotEmpty)
          'sample_quotes': [for (final q in sampleQuotes) q.toJson()],
        if (secret.isNotEmpty) 'secret': secret,
        if (userRole.isNotEmpty) 'user_role': userRole,
        if (extraCast.isNotEmpty)
          'extra_cast': [for (final e in extraCast) e.toJson()],
        if (themeColor.isNotEmpty) 'theme_color': themeColor,
        if (gender.isNotEmpty) 'gender': gender,
        if (unlisted) 'unlisted': true,
        if (kind.isNotEmpty) 'kind': kind,
        if (service != null) 'service': service!.toJson(),
        if (chatBackground.isNotEmpty) 'chat_background': chatBackground,
        if (chatBackgroundImage.isNotEmpty) 'chat_background_image': chatBackgroundImage,
        if (bubbleStyle.isNotEmpty) 'bubble_style': bubbleStyle,
        if (authorComment.isNotEmpty) 'author_comment': authorComment,
        'typing_speed_multiplier': typingSpeedMultiplier,
        'affection_stages': [
          for (final stage in affectionStages) stage.toJson()
        ],
        'is_published': isPublished,
      };

  CharacterModel copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? coverUrl,
    String? tagline,
    List<String>? tags,
    String? quote,
    List<ProfileField>? profileFields,
    List<PersonalityTrait>? traits,
    List<CharacterQuote>? sampleQuotes,
    String? secret,
    String? userRole,
    List<ExtraCast>? extraCast,
    String? themeColor,
    String? gender,
    bool? unlisted,
    String? chatBackground,
    String? chatBackgroundImage,
    String? bubbleStyle,
    String? authorComment,
  }) {
    return CharacterModel(
      id: id ?? this.id,
      creatorId: creatorId,
      name: name ?? this.name,
      statusMessage: statusMessage,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      tagline: tagline ?? this.tagline,
      tags: tags ?? this.tags,
      worldviewPrompt: worldviewPrompt,
      worldSetting: worldSetting,
      quote: quote ?? this.quote,
      profileFields: profileFields ?? this.profileFields,
      traits: traits ?? this.traits,
      sampleQuotes: sampleQuotes ?? this.sampleQuotes,
      secret: secret ?? this.secret,
      userRole: userRole ?? this.userRole,
      extraCast: extraCast ?? this.extraCast,
      themeColor: themeColor ?? this.themeColor,
      gender: gender ?? this.gender,
      unlisted: unlisted ?? this.unlisted,
      kind: kind,
      service: service,
      chatBackground: chatBackground ?? this.chatBackground,
      chatBackgroundImage: chatBackgroundImage ?? this.chatBackgroundImage,
      bubbleStyle: bubbleStyle ?? this.bubbleStyle,
      authorComment: authorComment ?? this.authorComment,
      typingSpeedMultiplier: typingSpeedMultiplier,
      affectionStages: affectionStages,
      isPublished: isPublished,
    );
  }

  /// 커버로 쓸 사진: 대표 사진, 없으면 프로필 사진
  String get coverOrAvatar => coverUrl.isNotEmpty ? coverUrl : avatarUrl;

  /// 서비스 말랑이인지 (호감도 처음부터 100, 단계·엔딩 없음)
  bool get isService => kind == serviceKind;
  static const serviceKind = 'service';

  /// 화면·AI에 쓰는 성별 이름 (미정이면 빈 문자열)
  String get genderLabel => switch (gender) {
        'male' => '남성',
        'female' => '여성',
        'none' => '미정',
        _ => ''
      };

  /// AI에게 넘길 캐릭터 설정 전체 (비밀 포함)
  String get aiCharacterSheet {
    final lines = <String>[
      if (gender == 'none') '성별: 미정 (대사·설정에서 캐릭터 성별을 드러내지 않는다)',
      if (genderLabel.isNotEmpty && gender != 'none') '성별: $genderLabel',
      worldviewPrompt.trim(),
      if (worldSetting.trim().isNotEmpty) '세계관: ${worldSetting.trim()}',
      if (profileFields.isNotEmpty)
        '프로필: ${profileFields.map((f) => '${f.label} ${f.value}${f.isSecret ? '(비밀)' : ''}').join(', ')}',
      if (traits.isNotEmpty)
        '성격: ${traits.map((t) => t.right == null ? '${t.left} ${t.percent}%' : '${t.left}↔${t.right} ${t.percent}%(오른쪽 쪽으로)').join(', ')}',
      if (quote.isNotEmpty) '대표 대사: "$quote"',
      if (sampleQuotes.isNotEmpty)
        '대사 예시:\n${sampleQuotes.map((q) => '- ${q.situation.isNotEmpty ? '(${q.situation}) ' : ''}${q.body}').join('\n')}',
      if (userRole.isNotEmpty) '유저 설정: $userRole',
      if (extraCast.isNotEmpty)
        '주변 인물:\n${extraCast.map((e) => '- ${e.name}${e.role.isNotEmpty ? ' (${e.role})' : ''}${e.speech.isNotEmpty ? ' 말투: ${e.speech}' : ''}').join('\n')}',
      if (secret.isNotEmpty) '비밀(유저는 아직 모름, 서서히 드러냄): $secret',
    ];
    return fillCharName(lines.where((l) => l.isNotEmpty).join('\n'));
  }

  /// 대사·설정 속 이름 자리를 채움 (AI 챗 플랫폼과 같은 표기도 씀)
  /// - {{user}} 또는 {이름} → 내 별명 (제작자가 {{user}}라고 쓰면 플레이어마다 다르게 불림)
  /// - {{char}} → 캐릭터 이름 (charName을 줄 때만)
  /// 바로 뒤 조사는 이름 받침에 맞게 바꿈: {{user}}아 → 쨋뀨야 / 서연아, {{char}}이 → 카이엔이 / 도하가
  static String fillUserName(String text, String nickname, {String? charName}) {
    var out = text.replaceAllMapped(
        _userPattern, (m) => _withParticle(nickname, m.group(1)));
    if (charName != null) {
      out = out.replaceAllMapped(
          _charPattern, (m) => _withParticle(charName, m.group(1)));
    }
    return out;
  }

  /// {{char}}만 이 캐릭터 이름으로 채움 ({{user}}는 그대로 둠, AI에게 넘기는 설정용)
  String fillCharName(String text) => text.replaceAllMapped(
      _charPattern, (m) => _withParticle(name, m.group(1)));

  static String _withParticle(String name, String? particle) {
    if (particle == null) return name;
    final pair = _particlePairs.firstWhere((p) => p.contains(particle));
    return josa(name, pair[0], pair[1]);
  }

  static const _particles = r'(이랑|랑|이야|아|야|이|가|은|는|을|를|과|와)?';
  static final _userPattern = RegExp(
      r'(?:\{\{\s*user\s*\}\}|\{이름\})' + _particles,
      caseSensitive: false);
  static final _charPattern =
      RegExp(r'\{\{\s*char\s*\}\}' + _particles, caseSensitive: false);
  static const _particlePairs = [
    ['아', '야'],
    ['이랑', '랑'],
    ['이야', '야'],
    ['이', '가'],
    ['은', '는'],
    ['을', '를'],
    ['과', '와'],
  ];

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

  /// 실제 시각(밤 11시~새벽 2시, 12월 25일 등)에 대화방에 있을 때만 한 번 오는 특별한 톡 (공략 조건 아님)
  static const String special = 'special';

  /// 엔딩을 본 뒤 차례대로 오는 '공략 후 이야기' (공략 조건 아님)
  static const String afterEnding = 'after_ending';
}

/// 특별 이벤트가 열리는 실제 시간 (시각 구간, 날짜는 둘 중 하나만 있어도 됨)
class RealTimeWindow {
  /// 시작 시각 (0~23). toHour와 같이 씀. 22 → 2 처럼 자정을 넘겨도 됨
  final int? fromHour;

  /// 끝 시각 (이 시각 전까지, 0~24)
  final int? toHour;

  /// 날짜 'MM-DD' (예: 12-25)
  final String? date;

  const RealTimeWindow({this.fromHour, this.toHour, this.date});

  bool get hasHours => fromHour != null && toHour != null && fromHour != toHour;

  bool contains(DateTime now) {
    if (date != null && date!.isNotEmpty) {
      final md =
          '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      if (md != date) return false;
    }
    if (!hasHours) return date != null && date!.isNotEmpty;
    final h = now.hour;
    return fromHour! < toHour!
        ? h >= fromHour! && h < toHour!
        : h >= fromHour! || h < toHour!;
  }

  /// 화면·편집기용 설명 (예: 12월 25일 밤 10시~새벽 2시)
  String get label {
    String hour(int h) {
      final hh = h % 24;
      final part = hh < 5
          ? '새벽'
          : hh < 12
              ? '오전'
              : hh < 18
                  ? '오후'
                  : '밤';
      final shown = hh == 0 ? 12 : (hh > 12 ? hh - 12 : hh);
      return '$part $shown시';
    }

    final parts = <String>[
      if (date != null && date!.isNotEmpty)
        '${int.tryParse(date!.split('-').first) ?? date}월 ${int.tryParse(date!.split('-').last) ?? ''}일',
      if (hasHours) '${hour(fromHour!)}~${hour(toHour!)}',
    ];
    return parts.isEmpty ? '시간 미정' : parts.join(' ');
  }

  factory RealTimeWindow.fromJson(Map<String, dynamic> json) => RealTimeWindow(
        fromHour: (json['from_hour'] as num?)?.toInt(),
        toHour: (json['to_hour'] as num?)?.toInt(),
        date: json['date'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (fromHour != null) 'from_hour': fromHour,
        if (toHour != null) 'to_hour': toHour,
        if (date != null && date!.isNotEmpty) 'date': date,
      };
}

/// 사진함 사진 하나에 붙이는 '보낼 때' (자유대화에서 AI가 이 조건이 맞을 때만 이 사진을 보냄)
class PhotoTrigger {
  /// 사진 설명 (앨범·AI가 보는 이름. 비우면 같은 사진을 쓰는 말풍선·컷씬 설명)
  final String caption;

  /// 감정 (예: 기쁨, 설렘, 장난, 서운함)
  final String mood;

  /// 상황 (예: 유저가 보고 싶다고 할 때, 밤늦게 잠 안 올 때)
  final String situation;

  /// 대화에 나오면 보낼 만한 낱말들
  final List<String> keywords;

  /// 스토리에만 쓰는 사진 (적어 둔 감정·상황이 있어도 자유대화에서는 안 보냄)
  final bool storyOnly;

  const PhotoTrigger(
      {this.caption = '',
      this.mood = '',
      this.situation = '',
      this.keywords = const [],
      this.storyOnly = false});

  /// 감정·상황·키워드 중 하나라도 있으면 자유대화에서 보낼 수 있음
  bool get isSet =>
      !storyOnly &&
      (mood.trim().isNotEmpty ||
          situation.trim().isNotEmpty ||
          keywords.isNotEmpty);

  /// 저장할 내용이 있는지 (설명만 있어도 남김)
  bool get hasData =>
      caption.trim().isNotEmpty ||
      mood.trim().isNotEmpty ||
      situation.trim().isNotEmpty ||
      keywords.isNotEmpty;

  PhotoTrigger copyWith(
          {String? caption,
          String? mood,
          String? situation,
          List<String>? keywords,
          bool? storyOnly}) =>
      PhotoTrigger(
          caption: caption ?? this.caption,
          mood: mood ?? this.mood,
          situation: situation ?? this.situation,
          keywords: keywords ?? this.keywords,
          storyOnly: storyOnly ?? this.storyOnly);

  /// AI에게 보여 주는 한 줄
  String get summary => [
        if (mood.trim().isNotEmpty) '감정: ${mood.trim()}',
        if (situation.trim().isNotEmpty) '상황: ${situation.trim()}',
        if (keywords.isNotEmpty) '키워드: ${keywords.join(', ')}',
      ].join(' / ');

  factory PhotoTrigger.fromJson(Map<String, dynamic> json) => PhotoTrigger(
        caption: json['caption'] as String? ?? '',
        mood: json['mood'] as String? ?? '',
        situation: json['situation'] as String? ?? '',
        keywords: [
          for (final k in json['keywords'] as List? ?? const []) k as String
        ],
        storyOnly: json['story_only'] == true,
      );

  Map<String, dynamic> toJson() => {
        if (caption.trim().isNotEmpty) 'caption': caption.trim(),
        if (mood.trim().isNotEmpty) 'mood': mood.trim(),
        if (situation.trim().isNotEmpty) 'situation': situation.trim(),
        if (keywords.isNotEmpty) 'keywords': keywords,
        if (storyOnly) 'story_only': true,
      };
}

/// 4. 시나리오 이벤트 모델 (DB 테이블: scenario_events)
class ScenarioEventModel {
  final String id;
  final String characterId;
  final int chapterOrder;
  final String eventType;
  final String title;

  /// 이벤트 시작 전에 대화방 가운데 뜨는 장면 전환 문구 (예: '그날 밤', '다음 날 점심', '며칠 뒤').
  /// 실제 시계와 어긋나지 않게 '목요일 밤 9:15' 같은 정확한 시각은 쓰지 않습니다.
  final String? timeNotice;

  /// 제작자만 보는 줄거리 메모 (AI가 대사를 쓸 때 참고)
  final String synopsis;

  /// 특별 이벤트가 열리는 실제 시간
  final RealTimeWindow? realTime;
  final int requiredAffection;
  final List<String> requiredFlags;
  final String? cutscenePhotoTitle;
  final String? cutsceneImageUrl; // 실제 CG 이미지 경로 (없으면 제목만 있는 자리표시 카드로 보여줌)
  final int? cutsceneTriggerStep; // 이 단계(stepOrder)의 대사가 끝나면 컷씬(CG)이 전체 화면으로 뜸
  /// 이 이벤트에 올려 둔 사진들 ('img:번호'). 컷씬과 사진 말풍선이 이 중에서 골라 씀
  final List<String> photoRefs;

  /// 사진함 사진별 '보낼 때' (사진 번호 → 감정·상황·키워드). 자유대화에서 씀
  final Map<String, PhotoTrigger> photoTriggers;
  final List<String> participantCharacterIds;

  /// 이 대화가 속한 호감도 단계 이름 (캐릭터의 affectionStages 중 하나)
  /// 이벤트는 그 단계에 도달하면 열리고, 일상 대화는 그 단계에 머무는 동안에만 나옵니다.
  final String? stageLabel;

  /// 이 점수를 넘으면 더는 안 나옴 (주로 일상 대화용, 비우면 제한 없음)
  final int? maxAffection;

  /// 이어지는 대화: 이 ID의 대화가 끝나면 바로 이어서 나옴 (일상 대화를 무작위 순서에서 빼서 붙여 둘 때)
  final String? followsEventId;

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
    this.photoRefs = const [],
    this.photoTriggers = const {},
    this.participantCharacterIds = const [],
    this.stageLabel,
    this.maxAffection,
    this.synopsis = '',
    this.realTime,
    this.followsEventId,
  });

  bool get hasCutscene => cutsceneTriggerStep != null;

  /// 컷씬 단계만 바꾼 사본
  ScenarioEventModel withCutsceneStep(int? step) => ScenarioEventModel(
        id: id,
        characterId: characterId,
        chapterOrder: chapterOrder,
        eventType: eventType,
        title: title,
        timeNotice: timeNotice,
        requiredAffection: requiredAffection,
        requiredFlags: requiredFlags,
        cutscenePhotoTitle: cutscenePhotoTitle,
        cutsceneImageUrl: cutsceneImageUrl,
        cutsceneTriggerStep: step,
        photoRefs: photoRefs,
        photoTriggers: photoTriggers,
        participantCharacterIds: participantCharacterIds,
        stageLabel: stageLabel,
        maxAffection: maxAffection,
        synopsis: synopsis,
        realTime: realTime,
        followsEventId: followsEventId,
      );
  bool get isEnding => eventType == ScenarioEventType.ending;
  bool get isDaily => eventType == ScenarioEventType.daily;
  bool get isSpecial => eventType == ScenarioEventType.special;
  bool get isAfterEnding => eventType == ScenarioEventType.afterEnding;

  /// 공략 완료 판정에 들어가는 '호감도 이벤트'인지 (엔딩·난입 이벤트는 제외)
  bool get isAffectionEvent =>
      eventType == ScenarioEventType.autoStory ||
      eventType == ScenarioEventType.custom;

  factory ScenarioEventModel.fromJson(Map<String, dynamic> json) {
    final unlock =
        json['unlock_condition'] as Map<String, dynamic>? ?? const {};
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
      photoRefs: [
        for (final ref in json['photos'] as List? ?? const []) ref as String,
      ],
      photoTriggers: {
        for (final entry
            in (json['photo_triggers'] as Map? ?? const {}).entries)
          if (entry.value is Map)
            entry.key as String: PhotoTrigger.fromJson(
                Map<String, dynamic>.from(entry.value as Map)),
      },
      participantCharacterIds: [
        for (final id in json['participants'] as List? ?? const [])
          id as String,
      ],
      stageLabel: json['stage'] as String?,
      maxAffection: unlock['max_affection'] as int?,
      synopsis: json['synopsis'] as String? ?? '',
      realTime: json['real_time'] is Map
          ? RealTimeWindow.fromJson(json['real_time'] as Map<String, dynamic>)
          : null,
      followsEventId: json['follows'] as String?,
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
        if (cutsceneTriggerStep != null)
          'cutscene_trigger_step': cutsceneTriggerStep,
        if (photoRefs.isNotEmpty) 'photos': photoRefs,
        if (photoTriggers.values.any((t) => t.isSet))
          'photo_triggers': {
            for (final e in photoTriggers.entries)
              if (e.value.isSet) e.key: e.value.toJson(),
          },
        if (participantCharacterIds.isNotEmpty)
          'participants': participantCharacterIds,
        if (synopsis.isNotEmpty) 'synopsis': synopsis,
        if (realTime != null) 'real_time': realTime!.toJson(),
        if (followsEventId != null) 'follows': followsEventId,
      };
}

/// 5. 말풍선 한 줄 단위 모델 (타자 속도 조절 & 사진 첨부 지원)
class ScriptBubblePiece {
  final String text;

  /// 이 말풍선을 칠 때 타자 빠르기 (0.6: 급하게 빨리 침, 1.0: 보통, 1.5: 망설이며 느리게 침)
  final double speedFactor;

  /// 대화방에 사진을 찍어 올리는 말풍선일 경우 사진 제목/경로
  final String? photoLabel;

  /// 진짜 사진 (캐릭터 파일의 images 안 번호. 없으면 설명만 있는 사진 카드)
  final String? photoImage;

  /// 답장이 늦게 오는 연출: 이 말풍선을 치기 전에 '1'이 안 사라진 채 기다리는 시간(초). 0이면 보통
  final int delaySeconds;

  const ScriptBubblePiece({
    required this.text,
    this.speedFactor = 1.0,
    this.photoLabel,
    this.photoImage,
    this.delaySeconds = 0,
  });

  bool get hasPhoto => photoLabel != null && photoLabel!.isNotEmpty;

  factory ScriptBubblePiece.fromJson(Map<String, dynamic> json) {
    return ScriptBubblePiece(
      text: json['text'] as String? ?? '',
      speedFactor: (json['speed'] as num?)?.toDouble() ?? 1.0,
      photoLabel: json['photo'] as String?,
      photoImage: json['photo_image'] as String?,
      delaySeconds: (json['delay'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        if (speedFactor != 1.0) 'speed': speedFactor,
        if (delaySeconds > 0) 'delay': delaySeconds,
        if (hasPhoto) 'photo': photoLabel,
        if (hasPhoto && photoImage != null) 'photo_image': photoImage,
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

  /// 선톡: 이 장면이 시작되면 캐릭터보다 먼저 내가 보내는 톡 (비우면 캐릭터가 먼저)
  final List<ScriptBubblePiece> userFirst;

  const ScriptNodeModel({
    required this.id,
    required this.eventId,
    required this.stepOrder,
    required this.speakerCharacterId,
    required this.characterBubbles,
    required this.choices,
    this.userFirst = const [],
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
      userFirst: [
        for (final bubble in json['user_first'] as List? ?? const [])
          ScriptBubblePiece.fromJson(bubble as Map<String, dynamic>),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'event_id': eventId,
        'step_order': stepOrder,
        'speaker_character_id': speakerCharacterId,
        'messages': [for (final b in characterBubbles) b.toJson()],
        if (choices.isNotEmpty)
          'choices': [for (final c in choices) c.toJson()],
        if (userFirst.isNotEmpty)
          'user_first': [for (final b in userFirst) b.toJson()],
      };
}

/// 시나리오 묶음: 캐릭터 1명 + 이벤트 목록 + 대사 노드 목록
/// 캐릭터 파일(.json) 하나가 이 모양이고, 4단계에서는 서버 API가 같은 모양으로 내려줄 예정입니다.
class ScenarioBundle {
  final CharacterModel character;
  final List<ScenarioEventModel> events; // chapterOrder 순으로 정렬됨
  final Map<String, ScriptNodeModel> nodes; // 노드 ID로 바로 찾기
  /// 제작자가 올린 사진 (번호 → data: 주소). 사진 말풍선과 컷씬이 'img:번호'로 가리킴.
  /// 같은 사진을 대화 기록마다 또 저장하지 않으려고 한곳에 모아 둠
  final Map<String, String> images;

  /// 캐릭터 사진함: 이 캐릭터에 올린 사진 전부 ('img:번호'). 컷씬·사진 말풍선이 여기서 골라 씀
  final List<String> photoRefs;

  /// 사진함 사진별 설명·'보낼 때' (사진 번호 → 설명·감정·상황·키워드)
  final Map<String, PhotoTrigger> photoTriggers;

  const ScenarioBundle({
    required this.character,
    required this.events,
    required this.nodes,
    this.images = const {},
    this.photoRefs = const [],
    this.photoTriggers = const {},
  });

  static const imagePrefix = 'img:';

  /// 'img:번호'면 images에서 찾은 주소, 그 밖의 주소(http·data·assets)는 그대로
  String? resolveImage(String? ref) {
    if (ref == null || ref.isEmpty) return null;
    if (ref.startsWith(imagePrefix))
      return images[ref.substring(imagePrefix.length)];
    return ref;
  }

  /// 같은 설명을 단 컷씬과 사진 말풍선은 한쪽에만 사진을 올려도 같이 씀 (설명 → 사진 번호)
  static final _sharedPhotos = Expando<Map<String, String>>();
  Map<String, String> get _photosByLabel => _sharedPhotos[this] ??= () {
        final map = <String, String>{};
        void add(String? label, String? ref) {
          final key = label?.trim() ?? '';
          if (key.isNotEmpty && ref != null && ref.isNotEmpty)
            map.putIfAbsent(key, () => ref);
        }

        for (final e in events) {
          add(e.cutscenePhotoTitle, e.cutsceneImageUrl);
        }
        for (final n in nodes.values) {
          for (final b in [
            ...n.characterBubbles,
            ...n.userFirst,
            for (final c in n.choices) ...c.userBubbles
          ]) {
            add(b.photoLabel, b.photoImage);
          }
        }
        // 사진함에 설명을 달아 둔 사진: 같은 설명의 말풍선·컷씬에 저절로 나옴
        for (final e in [
          ...photoTriggers.entries,
          for (final ev in events) ...ev.photoTriggers.entries
        ]) {
          add(e.value.caption, e.key);
        }
        return map;
      }();

  /// 사진 말풍선의 사진. 자기 사진이 없으면 설명이 같은 컷씬·사진 말풍선의 사진
  String? photoFor(String? ref, String? label) =>
      resolveImage(ref) ?? resolveImage(_photosByLabel[label?.trim() ?? '']);

  /// 컷씬 사진. 컷씬에 사진이 없으면 설명이 같은 사진 말풍선의 사진
  String? cutsceneImageFor(ScenarioEventModel event) =>
      photoFor(event.cutsceneImageUrl, event.cutscenePhotoTitle);

  /// 자유대화에서 AI가 골라 보낼 수 있는 사진: 사진함 사진 중 '보낼 때'를 적어 둔 것
  static final _freeCache = Expando<List<FreeTalkPhoto>>();
  List<FreeTalkPhoto> get freeTalkPhotos => _freeCache[this] ??= () {
        final byRef = <String, String>{
          for (final e in _photosByLabel.entries) e.value: e.key
        };
        final list = <FreeTalkPhoto>[];
        final seen = <String>{};
        void add(MapEntry<String, PhotoTrigger> entry,
            ScenarioEventModel? event) {
          final t = entry.value;
          if (!t.isSet || !seen.add(entry.key)) return;
          final label = t.caption.trim().isNotEmpty
              ? t.caption.trim()
              : byRef[entry.key] ??
                  '${event?.title ?? character.name} 사진 ${list.length + 1}';
          list.add(FreeTalkPhoto(
              id: 'p${list.length + 1}',
              ref: entry.key,
              label: label,
              trigger: t,
              event: event));
        }

        for (final entry in photoTriggers.entries) {
          add(entry, null);
        }
        // 예전 파일: 이벤트마다 사진함이 따로 있었음
        for (final event in events) {
          for (final entry in event.photoTriggers.entries) {
            add(entry, event);
          }
        }
        return List<FreeTalkPhoto>.unmodifiable(list);
      }();

  /// 앨범에 들어가는 사진 전부: 캐릭터가 보내는 사진 말풍선 + 컷씬 (구분 없이 한 앨범).
  /// 이벤트 순서대로, 설명이 같으면 같은 사진이라 한 번만 넣음
  static final _albumCache = Expando<List<AlbumPhoto>>();
  List<AlbumPhoto> get albumPhotos => _albumCache[this] ??= () {
        final list = <AlbumPhoto>[];
        final seen = <String>{};
        void add(ScenarioEventModel event, String? label, String? ref) {
          final key = label?.trim() ?? '';
          if (key.isEmpty || !seen.add(key)) return;
          final group = event.stageLabel ??
              character.stageFor(affectionRangeOf(event).min)?.stageLabel ??
              '그 밖의 사진';
          list.add(AlbumPhoto(
              label: key,
              event: event,
              image: photoFor(ref, key),
              group: group));
        }

        for (final event in events) {
          final eventNodes = nodes.values
              .where((n) => n.eventId == event.id)
              .toList()
            ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
          for (final n in eventNodes) {
            for (final b in n.characterBubbles) {
              if (b.hasPhoto) add(event, b.photoLabel, b.photoImage);
            }
          }
          if (event.hasCutscene)
            add(event, event.cutscenePhotoTitle, event.cutsceneImageUrl);
        }
        // 이야기에는 안 나오고 자유대화에서만 오는 사진
        for (final p in freeTalkPhotos) {
          if (!seen.add(p.label)) continue;
          list.add(AlbumPhoto(
              label: p.label,
              event: p.event,
              image: resolveImage(p.ref),
              group: '자유대화에서 받은 사진'));
        }
        return List<AlbumPhoto>.unmodifiable(list);
      }();

  factory ScenarioBundle.fromJson(Map<String, dynamic> json) {
    final events = [
      for (final event in json['events'] as List)
        ScenarioEventModel.fromJson(event as Map<String, dynamic>),
    ]..sort((a, b) => a.chapterOrder.compareTo(b.chapterOrder));
    return ScenarioBundle(
      character:
          CharacterModel.fromJson(json['character'] as Map<String, dynamic>),
      events: events,
      nodes: {
        for (final node in json['script_nodes'] as List)
          (node as Map<String, dynamic>)['id'] as String:
              ScriptNodeModel.fromJson(node),
      },
      images: {
        for (final entry in (json['images'] as Map? ?? const {}).entries)
          if (entry.value is String) entry.key as String: entry.value as String,
      },
      photoRefs: [
        for (final ref in json['photos'] as List? ?? const []) ref as String,
      ],
      photoTriggers: {
        for (final entry in (json['photo_triggers'] as Map? ?? const {}).entries)
          entry.key as String: PhotoTrigger.fromJson(
              Map<String, dynamic>.from(entry.value as Map)),
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'format': 'mallangtalk-scenario-v1',
        'character': character.toJson(),
        'events': [for (final e in events) e.toJson()],
        'script_nodes': [for (final n in nodes.values) n.toJson()],
        if (images.isNotEmpty) 'images': images,
        if (photoRefs.isNotEmpty) 'photos': photoRefs,
        if (photoTriggers.values.any((t) => t.hasData))
          'photo_triggers': {
            for (final e in photoTriggers.entries)
              if (e.value.hasData) e.key: e.value.toJson(),
          },
      };

  ScenarioBundle copyWithCharacter(CharacterModel character) => ScenarioBundle(
      character: character,
      events: events,
      nodes: nodes,
      images: images,
      photoRefs: photoRefs,
      photoTriggers: photoTriggers);

  /// 이 이벤트가 열리는 호감도 구간. 단계 이름이 있으면 그 단계 시작 점수부터 열리고,
  /// 일상 대화는 그 단계 끝 점수까지만 나옵니다.
  ({int min, int? max}) affectionRangeOf(ScenarioEventModel event) {
    final stage = character.stageNamed(event.stageLabel);
    var min = event.requiredAffection;
    int? max = event.maxAffection;
    if (stage != null) {
      if (stage.minScore > min) min = stage.minScore;
      if (event.isDaily && (max == null || stage.maxScore < max))
        max = stage.maxScore;
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

/// 자유대화에서 보낼 수 있는 사진 한 장
class FreeTalkPhoto {
  /// AI가 고를 때 쓰는 짧은 이름 (p1, p2 …)
  final String id;

  /// 사진 번호 ('img:번호')
  final String ref;
  final String label;
  final PhotoTrigger trigger;

  /// 예전 이벤트 사진함에서 온 사진이면 그 이벤트 (캐릭터 사진함 사진은 null)
  final ScenarioEventModel? event;

  const FreeTalkPhoto(
      {required this.id,
      required this.ref,
      required this.label,
      required this.trigger,
      this.event});
}

/// 앨범 사진 한 장 (설명 = 사진을 구분하는 이름)
class AlbumPhoto {
  final String label;

  /// 이 사진이 나오는 대화 (자유대화에서만 오는 캐릭터 사진함 사진은 null)
  final ScenarioEventModel? event;

  /// 진짜 사진 주소 (아직 안 올렸으면 null → 설명 카드)
  final String? image;

  /// 앨범에서 묶어 보여 주는 이름: 이 사진이 오는 호감도 단계
  final String group;

  const AlbumPhoto(
      {required this.label,
      this.event,
      this.image,
      required this.group});
}

/// 8. 실제 채팅창에 표시되는 개별 말풍선 로그 모델 (DB 테이블: chat_logs)
class ChatMessageLog {
  final String id;
  final bool isUser;
  final bool isHidden;

  /// 말풍선이 아니라 대화방 가운데 뜨는 안내 문구 (시간 경과, 공략 완료 등)
  final bool isSystem;

  /// 10분 이상 쉬었다가 시작한 새 대화. 기록·기억을 지우지 않는 장면 경계.
  final bool isConversationBreak;
  final String speakerCharacterId;
  final String speakerName;
  final String text;
  final String? photoLabel; // 사진 말풍선일 경우 사진 설명/경로
  final String? photoImage; // 진짜 사진 번호 (캐릭터 파일의 images에서 찾음. 기록에는 번호만 저장)
  final String? replyToId;
  final String? replyToText;
  final String? replyToName;
  final bool isUnread; // 카톡 읽음 '1' 표시 여부
  final DateTime timestamp;

  const ChatMessageLog({
    required this.id,
    required this.isUser,
    this.isHidden = false,
    this.isSystem = false,
    this.isConversationBreak = false,
    required this.speakerCharacterId,
    required this.speakerName,
    required this.text,
    this.photoLabel,
    this.photoImage,
    this.replyToId,
    this.replyToText,
    this.replyToName,
    this.isUnread = false,
    required this.timestamp,
  });

  bool get hasPhoto => photoLabel != null && photoLabel!.isNotEmpty;

  /// 진행 저장용 (브라우저 저장소에 대화 기록을 남길 때 사용)
  Map<String, dynamic> toJson() => {
        'id': id,
        'is_user': isUser,
        if (isHidden) 'is_hidden': true,
        'is_system': isSystem,
        if (isConversationBreak) 'is_conversation_break': true,
        'speaker_character_id': speakerCharacterId,
        'speaker_name': speakerName,
        'text': text,
        if (photoLabel != null) 'photo': photoLabel,
        if (photoImage != null) 'photo_image': photoImage,
        if (replyToId != null) 'reply_to_id': replyToId,
        if (replyToText != null) 'reply_to_text': replyToText,
        if (replyToName != null) 'reply_to_name': replyToName,
        'is_unread': isUnread,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessageLog.fromJson(Map<String, dynamic> json) {
    return ChatMessageLog(
      id: json['id'] as String,
      isUser: json['is_user'] as bool? ?? false,
      isHidden: json['is_hidden'] as bool? ?? false,
      isSystem: json['is_system'] as bool? ?? false,
      isConversationBreak: json['is_conversation_break'] as bool? ?? false,
      speakerCharacterId: json['speaker_character_id'] as String? ?? '',
      speakerName: json['speaker_name'] as String? ?? '',
      text: json['text'] as String? ?? '',
      photoLabel: json['photo'] as String?,
      photoImage: json['photo_image'] as String?,
      replyToId: json['reply_to_id'] as String?,
      replyToText: json['reply_to_text'] as String?,
      replyToName: json['reply_to_name'] as String?,
      isUnread: json['is_unread'] as bool? ?? false,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  ChatMessageLog copyWith({bool? isUnread}) {
    return ChatMessageLog(
      id: id,
      isUser: isUser,
      isHidden: isHidden,
      isSystem: isSystem,
      isConversationBreak: isConversationBreak,
      speakerCharacterId: speakerCharacterId,
      speakerName: speakerName,
      text: text,
      photoLabel: photoLabel,
      photoImage: photoImage,
      replyToId: replyToId,
      replyToText: replyToText,
      replyToName: replyToName,
      isUnread: isUnread ?? this.isUnread,
      timestamp: timestamp,
    );
  }
}
