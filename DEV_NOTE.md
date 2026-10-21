# 말랑톡(가칭) 개발자 노트 & 초보자용 마스터 가이드

이 문서는 GitHub 공식 `README.md`와 분리된 **개인용 개발 노트이자 상세 설계 해설서**입니다. Flutter와 서버 개발을 공부하면서 언제든 프로젝트를 다시 열었을 때 **"내가 왜 이렇게 구조를 짰고, 다음에 뭘 만져야 하는지"** 바로 이해할 수 있도록 작성되었습니다.

> **보관 팁**: GitHub에 비공개로 두고 싶다면 프로젝트 루트의 `.gitignore` 파일 맨 아래에 `DEV_NOTE.md` 한 줄만 추가해 두면 깃허브에는 올라가지 않고 내 컴퓨터에만 안전하게 남습니다.

## 1. 내가 만들려는 게임의 핵심 원리 (고민 해결 정리)

### 1.1 왜 '기본 스크립트 모드 + 내 AI 키(BYOK) 버튼' 하이브리드인가?

다수의 유저가 접속해서 플레이하는 게임에서 모든 대화를 내 서버의 AI API로 돌리면 **요금 폭탄**이 발생합니다. 반대로 [온더훅](https://namu.wiki/w/%EC%98%A8%EB%8D%94%ED%9B%85)처럼 정해진 선택지 3개만 누르게 하면 **"아, 난 여기서 이렇게 대답하고 싶은데!"** 하는 답답함이 생깁니다.

이 두 가지를 한 번에 해결하는 구조가 바로 **하이브리드 대화 모드**입니다.

| 모드 구분 | 작동 방식 | 누가 비용을 내나? | 플레이어 경험 |
| :--- | :--- | :--- | :--- |
| **기본 스토리 모드 (AI 버튼 OFF)** | 캐릭터 제작 시 AI가 미리 짜둔(그리고 제작자가 다듬은) **선택지 분기 스크립트**대로만 진행 | **0원** (이미 저장된 대사만 DB에서 꺼내옴) | [온더훅](https://namu.wiki/w/%EC%98%A8%EB%8D%94%ED%9B%85)처럼 빠른 템포로 호감도 공략과 컷씬 수집 가능 |
| **실시간 자유 대화 모드 (AI 버튼 ON)** | 유저가 자신의 AI API 키(Gemini 무료 키, Claude, OpenRouter 등)를 입력하고 상단 `[AI 자유대화 ON]` 버튼을 켬 | **플레이어 본인 API 키** 사용 (내 서버 비용 0원) | 선택지 3개 밑에 **직접 입력창**이 열리고, 내가 친 대사에 맞춰 캐릭터가 실시간 반응 + 호감도 변화 + 원래 시나리오 목표 쪽으로 자연스럽게 유도 |

**핵심 구현 포인트**:

* 유저가 입력한 API 키는 내 NAS 서버 DB에 저장하지 않고, 유저 스마트폰 브라우저(`FlutterSecureStorage` 또는 `SharedPreferences`)에만 저장합니다.
* AI 버튼을 켜고 자유 대화를 보낼 때만 그 키를 거쳐 AI를 호출하되, 프롬프트에 "현재 챕터 목표, 현재 호감도, 다음에 이어져야 할 이벤트 조건"을 같이 넣어주어 대화가 산으로 가지 않고 원래 제작자가 만든 이벤트/컷씬으로 자연스럽게 합류하게 만듭니다.

### 1.2 맥(Mac) 없이 아이폰(iOS) 유저에게 앱처럼 배포하는 법 + 새로고침 방지

Mac과 연 $99 애플 개발자 계정이 없으면 iOS 앱스토어에 앱을 올릴 수 없습니다. 대신 **하나의 Flutter Web 프로젝트**로 플레이 화면과 제작 도구를 모두 만들고, 모바일 유저는 브라우저의 **[홈 화면에 추가 (PWA)]** 기능을 쓰게 합니다.

이때 가장 걱정하셨던 "모바일 웹에서 화면을 위로 당기면 새로고침(Pull-to-refresh)이 되어서 게임이 깨지는 현상"은 아래 두 가지 설정으로 **100% 막을 수 있습니다.**

1. **`web/manifest.json` 설정**: `"display": "standalone"`으로 지정하면 사파리(iOS)나 크롬(Android)의 상단 주소창과 하단 뒤로가기 바가 완전히 사라져서 진짜 네이티브 앱처럼 실행됩니다.
2. **`web/index.html`에 당겨서 새로고침 방지 CSS 추가**:
   ```html
   <style>
     html, body {
       /* 위로 당겨서 새로고침(Pull-to-refresh) 및 고무줄 바운스 현상 완전 차단 */
       overscroll-behavior-y: none;
       overflow: hidden;
       position: fixed;
       width: 100%;
       height: 100%;
       touch-action: pan-x pan-y;
       user-select: none;
       -webkit-user-select: none;
     }
   </style>
   ```
   이렇게 하면 채팅창 안에서 스크롤을 아무리 세게 위아래로 당겨도 브라우저가 절대 새로고침되지 않습니다.

### 1.3 동일 제작자 캐릭터 간 '관계도 연결' 구조 (1단계 필수 ~ 2단계 확장)

같은 제작자가 만든 캐릭터 A와 B의 관계를 연결할 때, 처음부터 코드를 복잡하게 고치지 않아도 되도록 **데이터 구조(JSON/DB)를 2단계까지 미리 열어두는 방식**입니다.

| 단계 | 기능 범위 | 작동 원리 (초보자용 설명) |
| :--- | :--- | :--- |
| **1단계 (초기 필수 구현)** | **타 캐릭터 상태 인지 및 대사 언급** | 제작자가 A와 B를 `'소꿉친구'`로 연결해 두면, 유저가 A와 톡할 때 서버가 **"이 유저가 지금 B와 호감도가 몇인지, 어떤 이벤트를 봤는지"**를 같이 읽어옵니다. 덕분에 스크립트 조건 분기(`B 호감도 50 이상일 때 해금되는 대사`)나 AI 대화에서 A가 *"너 요즘 B랑 자주 연락한다며?"*라고 자연스럽게 말할 수 있습니다. |
| **2단계 (추후 이벤트 확장)** | **타 캐릭터 톡 난입 & 단톡방 이벤트** | 제작 스튜디오의 이벤트 에디터에서 각 메시지 줄마다 `화자(speakerCharacterId)`를 지정할 수 있게 만듭니다. 평소엔 A만 말하지만, 제작자가 특별 이벤트에서 화자를 B로 지정하면 **갑자기 B가 톡방에 끼어들거나 단톡방 이벤트가 열리는 연출**을 DB 구조 변경 없이 그대로 만들 수 있습니다. |

## 2. 데이터베이스(DB) 상세 구조 설계 (총 8개 핵심 테이블)

시놀로지 NAS의 SQLite(또는 PostgreSQL)에 들어갈 **8개 핵심 테이블 구조**입니다. 다수 유저의 캐릭터 배포, 컷씬 타이밍 지정, 캐릭터 관계도 연결이 모두 이 테이블들로 돌아갑니다.

### 2.1 전체 테이블 한눈에 보기

| 분류 | 테이블 이름 | 어떤 데이터를 저장하나요? (초보자용 설명) |
| :--- | :--- | :--- |
| **계정** | `users` | 가입한 유저들의 아이디, 닉네임, 푸시 알림 토큰 (개인 AI API 키는 보안을 위해 서버 DB가 아닌 유저 폰에만 저장!) |
| **창작(캐릭터)** | `characters` | 유저들이 만든 캐릭터의 기본 설정(이름, 프사, 성격 프롬프트, 호감도 구간 정의, 공개 배포 여부) |
| **창작(관계도)** | `character_relations` | **같은 제작자(`creator_id`)가 만든 캐릭터끼리의 관계 연결표** (소꿉친구, 라이벌 등 호칭과 조건부 반응 설정) |
| **창작(이벤트)** | `scenario_events` | AI가 자동 생성했거나 제작자가 직접 만든 **이벤트 목록** + **어느 단계에서 어떤 컷씬(CG) 이미지를 띄울지** 저장 |
| **창작(대본)** | `script_nodes` | 각 이벤트 안에서 실제로 주고받는 **말풍선 대사들과 3지선다 선택지**, 선택지별 호감도 증감 점수 |
| **플레이(세이브)** | `user_play_sessions` | 유저가 특정 캐릭터와 몇 호감도까지 쌓았는지, 현재 어느 이벤트를 진행 중인지, AI 장기기억 요약본이 뭔지 저장 |
| **플레이(대화창)** | `chat_logs` | 카톡창에 실제로 찍힌 말풍선 대화 내역과 읽음(`1`) 표시 상태 |
| **수집(앨범)** | `user_unlocked_gallery` | 유저가 플레이하며 해금한 **이벤트 컷씬(CG) 일러스트와 엔딩 수집 목록** |

### 2.2 테이블별 상세 컬럼 구조

#### ① `users` (유저 계정)
| 컬럼명 | 타입 | 역할 및 설명 |
| :--- | :--- | :--- |
| `id` | `TEXT (PK)` | 유저 고유 ID (UUID) |
| `username` | `TEXT (Unique)` | 닉네임 (제작자 이름 및 플레이어 이름으로 표시) |
| `password_hash` | `TEXT` | 암호화된 비밀번호 |
| `fcm_token` | `TEXT (Nullable)` | 앱/웹을 닫았을 때 캐릭터 선톡 푸시 알림을 보내기 위한 토큰 |
| `created_at` | `DATETIME` | 가입 일시 |

#### ② `characters` (캐릭터 기본 설정)
| 컬럼명 | 타입 | 역할 및 설명 |
| :--- | :--- | :--- |
| `id` | `TEXT (PK)` | 캐릭터 고유 ID |
| `creator_id` | `TEXT (FK -> users.id)` | **만든 사람 ID** (이 값이 같아야만 캐릭터 관계도 연결 가능!) |
| `name` | `TEXT` | 캐릭터 이름 |
| `avatar_url` | `TEXT` | 프로필 사진 경로 (NAS `/data/uploads/avatars/...`) |
| `worldview_prompt` | `TEXT` | 캐릭터 성격·말투·배경 세계관 설정 (AI 시나리오 생성 및 실시간 대화 시 사용) |
| `affection_stages_json` | `TEXT (JSON)` | 호감도 단계 설정 (예: `0~29: 지인`, `30~69: 썸`, `70~100: 연인`) |
| `is_published` | `INTEGER (0/1)` | 허브 공개 배포 여부 (`0`: 제작 중/비공개, `1`: 다른 유저에게 배포됨) |

#### ③ `character_relations` (동일 제작자 캐릭터 관계도 연결)
| 컬럼명 | 타입 | 역할 및 설명 |
| :--- | :--- | :--- |
| `id` | `TEXT (PK)` | 관계 고유 ID |
| `creator_id` | `TEXT (FK -> users.id)` | 제작자 ID |
| `from_character_id` | `TEXT (FK -> characters.id)` | 기준 캐릭터 A (현재 유저와 톡하고 있는 캐릭터) |
| `to_character_id` | `TEXT (FK -> characters.id)` | 연결된 캐릭터 B (언급되거나 대화에 난입할 캐릭터) |
| `relation_label` | `TEXT` | A에게 B는 어떤 존재인지 (예: `'소꿉친구'`, `'앙숙'`, `'친형'`) |
| `reaction_rule_json` | `TEXT (JSON)` | **1단계 핵심**: 유저와 B의 호감도가 높을 때 A가 어떻게 반응할지 정의 (예: `{"b_min_affection": 50, "prompt_hint": "유저가 B와 친해져서 은근히 질투함"}`) |

#### ④ `scenario_events` (이벤트 및 컷씬 타이밍 지정)
| 컬럼명 | 타입 | 역할 및 설명 |
| :--- | :--- | :--- |
| `id` | `TEXT (PK)` | 이벤트 고유 ID |
| `character_id` | `TEXT (FK -> characters.id)` | 어떤 캐릭터의 이벤트인지 |
| `chapter_order` | `INTEGER` | 챕터/이벤트 진행 순서 번호 |
| `event_type` | `TEXT` | `'auto_story'`(AI 자동 생성), `'custom'`(제작자 수동 제작), `'intrusion'`(2단계 타 캐릭터 난입/단톡), `'ending'`(엔딩) |
| `title` | `TEXT` | 이벤트 제목 (예: `'첫 데이트 신청'`, `'비 오는 날의 우산'`) |
| `unlock_condition_json` | `TEXT (JSON)` | 발동 조건 (필요 호감도 `min_affection`, 필요 플래그, 또는 **연결된 타 캐릭터 B의 호감도 조건**) |
| `cutscene_image_url` | `TEXT (Nullable)` | **이벤트 중 띄울 컷씬(CG) 이미지 경로** (NAS `/data/uploads/cutscenes/...`) |
| `cutscene_trigger_step` | `INTEGER (Nullable)` | **제작자가 지정한 컷씬 등장 단계** (예: `3`이면 이 이벤트의 3번째 대사 노드가 끝날 때 컷씬 팝업!) |
| `participants_json` | `TEXT (JSON)` | 대화 참여 캐릭터 목록 (기본은 `["char_A"]`, 2단계 단톡/난입 이벤트면 `["char_A", "char_B"]`) |

#### ⑤ `script_nodes` (온더훅 방식 말풍선 대사 & 선택지 분기)
| 컬럼명 | 타입 | 역할 및 설명 |
| :--- | :--- | :--- |
| `id` | `TEXT (PK)` | 대사 노드 고유 ID |
| `event_id` | `TEXT (FK -> scenario_events.id)` | 소속된 이벤트 ID |
| `step_order` | `INTEGER` | 이벤트 안에서의 대사 순서 (`cutscene_trigger_step`과 비교해 컷씬을 띄움) |
| `speaker_character_id` | `TEXT (FK -> characters.id)` | **누가 말하는지** (평소엔 A지만, 2단계 난입 이벤트에서는 B의 ID를 넣어 B가 톡을 보냄!) |
| `messages_json` | `TEXT (JSON)` | 연속으로 날아올 말풍선 대사들과 답장 대기 시간(ms) 배열 |
| `choices_json` | `TEXT (JSON)` | 플레이어가 고를 3개 선택지 (대답 내용, 호감도 변화량 `+3`/`-2`, 획득 플래그, 다음 이어질 노드 ID) |

#### ⑥ `user_play_sessions` & `chat_logs` & `user_unlocked_gallery` (플레이어 진행 데이터)
| 테이블명 | 핵심 컬럼 구성 | 역할 및 설명 |
| :--- | :--- | :--- |
| **`user_play_sessions`** | `id`, `user_id`, `character_id`, `current_affection`, `current_event_id`, `current_node_id`, `flags_json`, `memory_summary` | 유저가 캐릭터별로 어디까지 공략했는지 저장. **A와 톡할 때 같은 제작자의 B 세션(`current_affection`)을 함께 조회해 관계도 대사에 반영!** |
| **`chat_logs`** | `id`, `session_id`, `sender_type`, `speaker_character_id`, `message_text`, `affection_delta`, `is_read`, `created_at` | 실제 채팅창에 쌓이는 말풍선 로그. `sender_type`으로 선택지 대답인지 BYOK 자유 입력인지 구분 |
| **`user_unlocked_gallery`** | `id`, `user_id`, `character_id`, `event_id`, `cutscene_image_url`, `unlocked_at` | 유저가 특정 이벤트 단계에 도달해 컷씬을 보면 자동으로 여기에 등록되어 **[앨범]** 탭에서 언제든 다시 감상 가능 |

### 2.3 초보자를 위한 JSON 컬럼 실제 예시 (`script_nodes.choices_json`)
SQLite에서는 복잡한 선택지 목록을 아래처럼 깔끔한 JSON 문자열로 한 칸에 저장하고, Dart에서 바로 꺼내 씁니다.
```json
[
  {
    "choice_id": "c1",
    "text": "나도 오늘 네 생각 많이 났어! 지금 만날까?",
    "affection_delta": 5,
    "add_flag": "야간산책_수락",
    "next_node_id": "node_04_happy"
  },
  {
    "choice_id": "c2",
    "text": "미안, 오늘은 좀 피곤해서 먼저 자볼게.",
    "affection_delta": -2,
    "add_flag": null,
    "next_node_id": "node_04_normal"
  }
]
```

## 3. Flutter + Riverpod & `lib/core/theme` 구조 쉽게 이해하기

참고하신 [taskflow_example](https://github.com/SirohaKR/taskflow_example) 저장소처럼 `lib/core/theme` 폴더에 색상과 글자 스타일을 모아두면, 나중에 파스텔 핑크 테마를 다크 모드나 다른 캐릭터 전용 테마로 바꿀 때 파일 하나만 고치면 앱 전체가 바뀝니다.

### 3.1 `lib/core/theme/` 4총사 역할

* **`app_colors.dart`**: 앱에서 쓰는 모든 색상표를 이름표로 붙여둔 파일입니다. 코드 중간에 `Color(0xFFFFE4E1)`처럼 암호 같은 숫자를 쓰지 않고 `AppColors.myBubble`(내 말풍선 색), `AppColors.partnerBubble`(상대 말풍선 색), `AppColors.affectionPink`(호감도 게이지 색)처럼 부르기 위해 만듭니다.
* **`app_text_styles.dart`**: 말풍선 글씨 크기, 읽음 표시 `1`의 작은 노란 글씨, 선택지 버튼 글씨체 등을 미리 정의해 둔 파일입니다.
* **`app_spacing.dart`**: 말풍선 모서리 둥글기(`radius`), 채팅창 좌우 여백(`padding`), 그리고 화면이 넓을 때(PC 스튜디오 모드)와 좁을 때(모바일 톡 모드) 기준이 되는 가로 길이를 모아둡니다.
* **`app_theme.dart`**: 위 세 개를 합쳐서 Flutter의 `MaterialApp`에 꽂아주는 최종 테마 설정 파일입니다.

### 3.2 Riverpod, 초보자는 딱 이 3가지만 기억하면 됩니다!

Flutter를 공부할 때 Riverpod이 어렵게 느껴지는 이유는 종류가 많아 보여서인데, 우리 프로젝트에서는 딱 3가지만 씁니다.

1. **`Provider` (읽기 전용 보관함)**: 변하지 않는 도구(예: NAS 서버와 통신하는 API 클라이언트)를 넣어두고 어디서든 꺼내 쓸 때 씁니다.
2. **`NotifierProvider` (상태 관리 매니저)**: 채팅방의 메시지 목록, 현재 호감도 점수, `[AI 자유대화 ON/OFF]` 버튼 상태처럼 **화면에서 실시간으로 바뀌는 데이터**를 관리합니다. 데이터가 바뀌면 화면을 알아서 새로 그려줍니다.
3. **`FutureProvider` (서버에서 불러오기)**: 캐릭터 목록이나 컷씬 앨범처럼 서버에서 데이터를 가져오는 동안 자동으로 '로딩 중 -> 완료 -> 에러' 화면을 처리해 줍니다.

## 4. 시놀로지 NAS & Docker 배포 구조 (왜 이렇게 도나요?)

내 컴퓨터에서 작업한 코드를 GitHub에 올리면(`git push`), 시놀로지 NAS가 GitHub에서 코드를 내려받아(`git pull`) Docker 컨테이너 하나로 실행합니다.

| 구성 요소 | 역할 | 왜 이걸 쓰나요? |
| :--- | :--- | :--- |
| **Flutter Web 빌드 파일** | 유저 스마트폰/PC 브라우저에 뜨는 화면 | 별도 웹서버 없이 내 Dart 서버가 화면 파일까지 같이 보내주면 컨테이너 1개로 끝납니다. |
| **Dart 서버 (`server/`)** | 캐릭터 저장, 호감도 계산, AI 대신 호출, 선톡 타이머 | Flutter와 똑같은 **Dart 언어**를 써서, 새로운 서버 언어를 따로 공부할 필요가 없고 `Character`, `Message` 데이터 클래스 코드를 앱과 서버가 그대로 복사해서 같이 씁니다. |
| **SQLite (초기) / PostgreSQL** | 유저 계정, 캐릭터 시나리오, 대화 기록 저장소 | 시놀로지 NAS의 `/volume1/docker/mallangtalk/data` 폴더에 파일로 연결(볼륨 마운트)해 두면, 컨테이너를 껐다 켜거나 업데이트해도 데이터가 절대 날아가지 않습니다. |

## 5. 사적인 개발 단계 로드맵 (이 순서대로만 따라가세요!)

처음부터 서버·DB·AI를 다 한꺼번에 만들려고 하면 지칩니다. 눈에 바로 보이는 화면부터 하나씩 완성해 나가는 **5단계 로드맵**입니다.

### Step 1: 뼈대 세우기 & `lib/core/theme` 완성 (1주차)
* Flutter 프로젝트 생성 및 Riverpod, GoRouter 패키지 설치
* `lib/core/theme/app_colors.dart`, `app_text_styles.dart`, `app_theme.dart` 작성
* 모바일 웹 당겨서 새로고침 방지(`web/index.html`, `manifest.json`) 적용
* **확인 목표**: 크롬 브라우저에서 파스텔 톤 메인 화면이 예쁘게 뜨는지 확인

### Step 2: [온더훅](https://namu.wiki/w/%EC%98%A8%EB%8D%94%ED%9B%85) 스타일 톡 플레이 화면 만들기 (2주차)
* 가짜 데이터(JSON) 하나를 넣어두고 카톡/메신저 UI 구현
* 읽음 `1` 사라짐 연출 -> 상대방 입력 중(`···`) -> 말풍선 순차 등장 애니메이션 구현
* 하단 선택지 3개 버튼 클릭 시 호감도 게이지 증가 및 특정 단계 도달 시 **컷씬(CG) 전체 화면 팝업** 구현
* 상단에 `[내 AI 키로 자유대화 ON/OFF]` 토글 스위치 및 직접 입력창 UI 추가
* **확인 목표**: 서버 없이도 샘플 캐릭터 1명을 선택지로 공략하고 컷씬을 볼 수 있음

### Step 3: 캐릭터 & 이벤트 제작 스튜디오 화면 만들기 (3주차)
* 같은 웹 안에서 `[제작 스튜디오]` 탭으로 이동하는 화면 구현
* 캐릭터 기본 설정(이름, 성격, 말투, 프로필 사진) 입력 폼 작성
* **AI 자동 생성 버튼**: 설정을 바탕으로 AI가 호감도 단계별 목표와 기본 이벤트·선택지 대본을 짜주는 기능 연결
* **수동 이벤트 & 컷씬 지정기**: 제작자가 "호감도 30 달성 시 이 컷씬 이미지를 띄워라", "직접 대사와 선택지 3개를 추가한다"를 클릭으로 편집하는 화면 구현
* **내 캐릭터 관계도 연결**: 내가 만든 다른 캐릭터를 선택해 관계(예: 소꿉친구)와 호감도 조건부 대사를 지정하는 UI 추가

### Step 4: Dart 미니 서버 & DB 연결 (4주차)
* `server/` 폴더에 Dart 서버 생성 및 위 2번 섹션의 **8개 SQLite 테이블** 자동 생성 스크립트 연결
* 회원가입/로그인, 캐릭터 배포(공개/비공개), 유저별 플레이 진행도 저장 API 연결
* 컷씬 이미지 업로드 시 NAS 폴더에 저장하는 기능 추가

### Step 5: GitHub 업로드 & 시놀로지 NAS Docker 가동 (5주차)
* `Dockerfile`과 `docker-compose.yml` 작성 후 GitHub에 푸시
* 시놀로지 NAS에 접속해 컨테이너 실행 및 역방향 프록시(HTTPS 도메인) 연결
* 내 스마트폰으로 접속해 홈 화면에 추가(PWA)하고 실제 플레이 및 캐릭터 제작 테스트!