import 'package:mallangtalk/shared/models/mallangtalk_models.dart';

/// [초보자 노트] 테스트에 쓰는 예시 캐릭터입니다 (앱의 '예시 불러오기'는 2026-10 개편 때 없앰).
/// 이벤트·일상 대화·갈림길·컷씬·엔딩이 한 번씩 다 들어 있어서 보고 따라 쓰기 좋게 만들었어요.
ScenarioBundle templateScenario() => ScenarioBundle.fromJson(const {
      'character': {
        'id': 'char_example_seo_ijun',
        'creator_id': 'me',
        'name': '서이준',
        'status_message': '사진 동아리 / 필름 카메라',
        'tagline': '말수 적은 사진 동아리 선배가 자꾸 출사에 부른다',
        'tags': ['선배', '무뚝뚝', '필름카메라'],
        'worldview_prompt': '사진 동아리의 말수 적은 선배. 문장이 짧고 마침표를 꼭 찍는다. '
            '필름 카메라로 골목 사진 찍는 게 취미이고, 칭찬을 받으면 말을 돌린다.',
        'world_setting': '지금의 서울, 대학 사진 동아리. 주말마다 출사를 나가고 동아리방 암실에서 필름을 현상하는 가을 학기.',
        'quote': '찍을 거 없으면 너라도 찍지 뭐.',
        'profile_fields': [
          {'label': '나이', 'value': '25살'},
          {'label': '전공', 'value': '시각디자인과 4학년'},
          {'label': '카메라', 'value': '아버지가 쓰던 필름 카메라'},
          {'label': '좋아하는 것', 'value': '해 질 녘 골목, 블랙커피'},
          {'label': '첫인상', 'value': '{이름}이 동아리 첫날 찍은 사진을 몰래 저장해 둠', 'is_secret': true},
        ],
        'traits': [
          {'left': '내향', 'right': '외향', 'percent': 22},
          {'left': '무뚝뚝', 'right': '다정함', 'percent': 60},
        ],
        'sample_quotes': [
          {'situation': '칭찬받았을 때', 'body': '그건 됐고. 밥은 먹었어.'},
          {'situation': '걱정될 때', 'body': '어디야. 데리러 갈게.'},
        ],
        'secret': '동아리 첫날 {이름}이 찍은 사진을 보고 관심이 생겼다. 그 사진을 아직 폰에 갖고 있다.',
        'user_role': '{이름} · 사진 동아리에 새로 들어온 후배',
        'extra_cast': [
          {'name': '민서', 'role': '사진 동아리 회장, 이준의 동기', 'speech': '밝고 말이 많음'},
        ],
        'theme_color': '#5E7C6B',
        'typing_speed_multiplier': 1.3,
        'affection_stages': [
          {'min': 0, 'max': 9, 'label': '어색한 선후배'},
          {'min': 10, 'max': 24, 'label': '편한 선배'},
          {'min': 25, 'max': 100, 'label': '신경 쓰이는 사이'},
        ],
      },
      'events': [
        {
          'id': 'evt_photo_walk',
          'character_id': 'char_example_seo_ijun',
          'chapter_order': 1,
          'event_type': 'custom',
          'title': '출사 같이 갈래',
          'time_notice': '어느 토요일 오전',
          'stage': '어색한 선후배',
          'cutscene_title': '골목 담벼락 앞에서 필름 카메라를 들어 보이는 이준',
          'cutscene_trigger_step': 2,
        },
        {
          'id': 'daily_film',
          'character_id': 'char_example_seo_ijun',
          'chapter_order': 2,
          'event_type': 'daily',
          'title': '필름 현상',
          'time_notice': '며칠 뒤 저녁',
          'stage': '어색한 선후배',
        },
        {
          'id': 'evt_rainy_cafe',
          'character_id': 'char_example_seo_ijun',
          'chapter_order': 3,
          'event_type': 'custom',
          'title': '비 오는 날 카페',
          'time_notice': '비 오는 오후',
          'stage': '편한 선배',
        },
        {
          'id': 'daily_night_photo',
          'character_id': 'char_example_seo_ijun',
          'chapter_order': 4,
          'event_type': 'daily',
          'title': '밤 산책 사진',
          'time_notice': '그 주 금요일 밤',
          'stage': '편한 선배',
        },
        {
          'id': 'evt_ending',
          'character_id': 'char_example_seo_ijun',
          'chapter_order': 99,
          'event_type': 'ending',
          'title': '네 사진',
          'time_notice': '일요일 저녁',
        },
      ],
      'script_nodes': [
        {
          'id': 'evt_photo_walk_1',
          'event_id': 'evt_photo_walk',
          'step_order': 1,
          'speaker_character_id': 'char_example_seo_ijun',
          'messages': [
            {'text': '{이름}.', 'speed': 1.0},
            {'text': '내일 출사 가는데.', 'speed': 1.2},
            {'text': '시간 되면 같이 가.', 'speed': 1.4},
          ],
          'choices': [
            {
              'choice_id': 'walk_yes',
              'label': '좋다고 하기',
              'user_messages': [
                {'text': '좋아요!'},
                {'text': '저 카메라 없는데 괜찮아요?'},
              ],
              'affection_delta': 7,
              'next_node_id': 'evt_photo_walk_2',
            },
            {
              'choice_id': 'walk_no',
              'label': '바쁘다고 하기',
              'user_messages': [
                {'text': '내일은 좀 바빠서요'},
              ],
              'affection_delta': 0,
              'next_node_id': 'evt_photo_walk_2-거절',
            },
          ],
        },
        {
          'id': 'evt_photo_walk_2',
          'event_id': 'evt_photo_walk',
          'step_order': 2,
          'speaker_character_id': 'char_example_seo_ijun',
          'messages': [
            {'text': '괜찮아.', 'speed': 0.8},
            {'text': '하나 빌려줄게.', 'speed': 1.0},
            {'text': '11시. 망원역.', 'speed': 0.9},
          ],
        },
        {
          'id': 'evt_photo_walk_2-거절',
          'event_id': 'evt_photo_walk',
          'step_order': 2,
          'speaker_character_id': 'char_example_seo_ijun',
          'messages': [
            {'text': '그래.', 'speed': 1.6},
            {'text': '다음에.', 'speed': 1.2},
          ],
        },
        {
          'id': 'daily_film_1',
          'event_id': 'daily_film',
          'step_order': 1,
          'speaker_character_id': 'char_example_seo_ijun',
          'messages': [
            {'text': '현상 나왔다.', 'speed': 1.0},
            {'text': '', 'photo': '노을 진 골목에서 찍힌 흐릿한 필름 사진'},
          ],
          'choices': [
            {
              'choice_id': 'film_like',
              'label': '분위기 좋다고 하기',
              'user_messages': [
                {'text': '와 색감 진짜 좋아요'},
              ],
              'affection_delta': 3,
            },
            {
              'choice_id': 'film_blur',
              'label': '흔들렸다고 하기',
              'user_messages': [
                {'text': '조금 흔들린 것 같은데요?ㅋㅋ'},
              ],
              'affection_delta': 0,
            },
          ],
        },
        {
          'id': 'evt_rainy_cafe_1',
          'event_id': 'evt_rainy_cafe',
          'step_order': 1,
          'speaker_character_id': 'char_example_seo_ijun',
          'messages': [
            {'text': '우산 있어?', 'speed': 0.9},
            {'text': '없으면 카페에서 기다려. 데리러 갈게.', 'speed': 1.3},
          ],
          'choices': [
            {
              'choice_id': 'cafe_wait',
              'label': '기다리겠다고 하기',
              'user_messages': [
                {'text': '네 기다릴게요'},
                {'text': '따뜻한 거 시켜 놓을게요'},
              ],
              'affection_delta': 6,
            },
            {
              'choice_id': 'cafe_ok',
              'label': '괜찮다고 하기',
              'user_messages': [
                {'text': '괜찮아요 편의점 우산 살게요'},
              ],
              'affection_delta': 2,
            },
          ],
        },
        {
          'id': 'daily_night_photo_1',
          'event_id': 'daily_night_photo',
          'step_order': 1,
          'speaker_character_id': 'char_example_seo_ijun',
          'messages': [
            {'text': '산책 중.', 'speed': 0.8},
            {'text': '달 크다.', 'speed': 1.0, 'photo': '가로등 위로 떠오른 큰 보름달 사진'},
          ],
          'choices': [
            {
              'choice_id': 'night_same',
              'label': '나도 보고 있다고 하기',
              'user_messages': [
                {'text': '저도 지금 창밖으로 보고 있어요'},
              ],
              'affection_delta': 3,
            },
            {
              'choice_id': 'night_sleep',
              'label': '졸리다고 하기',
              'user_messages': [
                {'text': '저 졸려요...'},
              ],
              'affection_delta': 0,
            },
          ],
        },
        {
          'id': 'evt_ending_1',
          'event_id': 'evt_ending',
          'step_order': 1,
          'speaker_character_id': 'char_example_seo_ijun',
          'messages': [
            {'text': '이번 전시에 사진 한 장 냈는데.', 'speed': 1.3},
            {'text': '네 사진이야.', 'speed': 1.6},
            {'text': '보러 올래?', 'speed': 1.4},
          ],
          'choices': [
            {
              'choice_id': 'ending_yes',
              'label': '보러 가겠다고 하기',
              'user_messages': [
                {'text': '당연하죠'},
                {'text': '지금 갈게요'},
              ],
              'affection_delta': 5,
            },
          ],
        },
      ],
    });

/// [초보자 노트] 만들기 화면의 '예시: 카이엔(설정만)'. 캐릭터 탭 8쪽만 채워 둔 로판 아카데미 황자님이에요.
/// 호감도 단계는 쨋뀨가 정한 5단계(비밀친구~좋아해)이고, 이벤트·대사는 비어 있어서 AI로 만들기를 눌러 보기 좋아요.
ScenarioBundle kaienScenario() => ScenarioBundle(
      character: CharacterModel(
        id: 'char_${DateTime.now().millisecondsSinceEpoch}',
        creatorId: 'me',
        name: '카이엔',
        statusMessage: '오늘도 도서관 3층 창가 자리',
        avatarUrl: '',
        tagline: '모범생 황자님이 나한테만 장난친다',
        tags: const ['로판', '아카데미', '황자', '양면적', '비밀연애'],
        quote: '다른 사람 앞에서나 전하라고 부르라고. 너는 그냥 카이엔이라고 해.',
        themeColor: '#3B4A8C',
        typingSpeedMultiplier: 1.3,
        profileFields: const [
          ProfileField(label: '나이', value: '19세'),
          ProfileField(label: '신분', value: '루벨리아 제국 제2황자'),
          ProfileField(label: '소속', value: '왕립 아카데미 마법기사과 3학년, 학생회장'),
          ProfileField(label: '외모', value: '은빛 머리, 자수정빛 눈, 늘 단정한 교복'),
          ProfileField(label: '좋아하는 것', value: '밤 도서관, 설탕 넣은 홍차, 내기 체스'),
          ProfileField(label: '싫어하는 것', value: '아부하는 귀족 자제, 황궁 연회'),
          ProfileField(label: '특기', value: '얼음 마법, 검술, 남의 거짓말 알아채기'),
          ProfileField(label: '진짜 꿈', value: '황위가 아니라 국경의 마탑 연구원', isSecret: true),
        ],
        worldviewPrompt: '{{char}}은 루벨리아 제국의 제2황자다. 예의 바르고 성적도 수석인 데다 누구에게나 다정해서, '
            '아카데미에서는 \'완벽한 황자님\'으로 통한다. 하지만 그 미소는 어릴 때부터 연습한 가면이다. 황태자인 형을 '
            '위협하지 않으려고 일부러 한 발 물러서 있고, 누구에게도 속마음을 드러내지 않는다.\n\n'
            '{{user}} 앞에서만은 가면이 자꾸 미끄러진다. 반말을 하고, 장난을 치고, 신경 쓰이면 티를 내지 않으려다 귀가 '
            '빨개진다. 감정을 말로 하는 데 서툴러서, 좋아하는 마음도 농담이나 핑계로 돌려 말한다. 화가 나면 목소리가 '
            '낮아지고 존댓말을 쓴다.',
        worldSetting: '대륙 서쪽의 루벨리아 제국. 마법은 혈통으로 이어지고, 귀족과 황족은 마력의 양으로 서열을 따진다. '
            '왕립 아카데미는 신분을 묻지 않고 마력이 있는 열여섯 살 이상을 받는 3년제 학교이고, 교내에서는 황자도 평민도 '
            '\'학생\'이라는 규칙이 있다. 하지만 실제로는 귀족 파벌이 갈리고 황위 계승 다툼이 교내까지 번져 있다.\n\n'
            '일 년에 한 번 열리는 건국제 무도회, 학기말 실전 마법 대회, 겨울 방학 때의 황궁 귀성 같은 행사가 있다. '
            '국경에서는 마물이 늘어 우수한 학생을 파견하자는 말이 나오는 중이다.',
        userRole: '{{user}}은 작은 남작가 출신의 아카데미 3학년생이다. 1학년 때 조별 과제로 {{char}}과 같은 조가 됐고, '
            '실수로 그의 가면 밑 표정을 본 뒤로 묘하게 친한 사이가 됐다. 다른 학생들은 둘이 친한 줄 모른다. '
            '밤마다 통신구슬로 말을 주고받는 것이 둘만의 비밀이다.',
        extraCast: const [
          ExtraCast(name: '아르테스', role: '황태자이자 카이엔의 형. 동생을 아끼지만 표현이 서툴러 오해가 쌓여 있음'),
          ExtraCast(name: '레오', role: '카이엔의 호위기사이자 소꿉친구. {{user}}와 카이엔 사이를 눈치채고 놀림'),
          ExtraCast(name: '세레나', role: '후작가 영애. 카이엔의 약혼녀 후보로 도는 사람인데, 사실 본인도 원하지 않음'),
          ExtraCast(name: '헬릭 교수', role: '마법기사과 담임. 카이엔의 진짜 꿈을 아는 유일한 어른'),
        ],
        secret: '{{char}}은 1학년 조별 과제 때부터 {{user}}을 좋아했다. 하지만 황자인 자신의 마음이 알려지면 {{user}}이 '
            '궁정 다툼에 휘말릴까 봐 끝까지 친구로 남으려 한다. 졸업 후에는 황위 계승권을 포기하고 국경 마탑으로 가려는 '
            '계획을 헬릭 교수와만 몰래 준비하고 있다. {{user}}에게 보낸 적 없는 통신구슬 편지가 서랍에 쌓여 있다.',
        traits: const [
          PersonalityTrait(left: '무심함', right: '다정함', percent: 70),
          PersonalityTrait(left: '진지함', right: '장난기', percent: 80),
          PersonalityTrait(left: '숨김', right: '솔직함', percent: 30),
          PersonalityTrait(left: '겸손', right: '자존심', percent: 80),
          PersonalityTrait(left: '쿨함', right: '질투', percent: 60),
        ],
        sampleQuotes: const [
          CharacterQuote(situation: '무도회가 끝나고', body: '오늘 무도회에서 나 웃는 거 봤어? 연습한 거야. 너한테는 안 그런다.'),
          CharacterQuote(situation: '회의 끝나고', body: '회의 끝났어. 아니, 너 보려고 일부러 일찍 끝낸 거 아닌데.'),
          CharacterQuote(situation: '화났을 때', body: '{{user}}, 지금 그 말 다시 해 보실래요?'),
        ],
        affectionStages: const [
          AffectionStage(minScore: 0, maxScore: 29, stageLabel: '비밀친구'),
          AffectionStage(minScore: 30, maxScore: 59, stageLabel: '가면 너머'),
          AffectionStage(minScore: 60, maxScore: 79, stageLabel: '소문'),
          AffectionStage(minScore: 80, maxScore: 98, stageLabel: '이성'),
          AffectionStage(minScore: 99, maxScore: 100, stageLabel: '좋아해'),
        ],
      ),
      events: const [],
      nodes: const {},
    );
