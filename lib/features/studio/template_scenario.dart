import '../../shared/models/mallangtalk_models.dart';

/// [초보자 노트] '템플릿 받기'로 내려받는 엑셀에 미리 채워 두는 예시 캐릭터입니다.
/// 이벤트·일상 대화·갈림길·컷씬·엔딩이 한 번씩 다 들어 있어서 보고 따라 쓰기 좋게 만들었어요.
ScenarioBundle templateScenario() => ScenarioBundle.fromJson(const {
      'character': {
        'id': 'char_example_seo_ijun',
        'creator_id': 'me',
        'name': '서이준',
        'status_message': '사진 동아리 / 필름 카메라',
        'tagline': '말수 적은 사진 동아리 선배가 자꾸 출사에 부른다',
        'tags': ['선배', '무뚝뚝', '필름카메라'],
        'worldview_prompt': '서이준, 25살, 사진 동아리 선배. 말수가 적고 문장이 짧다. 마침표를 꼭 찍는다. '
            '필름 카메라로 골목 사진 찍는 게 취미. 칭찬을 받으면 말을 돌린다.',
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
          'time_notice': '토요일 오전 11:02',
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
          'time_notice': '월요일 저녁 7:40',
          'stage': '어색한 선후배',
        },
        {
          'id': 'evt_rainy_cafe',
          'character_id': 'char_example_seo_ijun',
          'chapter_order': 3,
          'event_type': 'custom',
          'title': '비 오는 날 카페',
          'time_notice': '목요일 오후 4:15',
          'stage': '편한 선배',
        },
        {
          'id': 'daily_night_photo',
          'character_id': 'char_example_seo_ijun',
          'chapter_order': 4,
          'event_type': 'daily',
          'title': '밤 산책 사진',
          'time_notice': '금요일 밤 11:20',
          'stage': '편한 선배',
        },
        {
          'id': 'evt_ending',
          'character_id': 'char_example_seo_ijun',
          'chapter_order': 99,
          'event_type': 'ending',
          'title': '네 사진',
          'time_notice': '일요일 저녁 6:30',
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
