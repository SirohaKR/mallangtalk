# MallangTalk (말랑톡 - 가칭)

사용자가 직접 캐릭터와 세계관을 제작·배포하고, 메신저(톡) 인터페이스를 통해 캐릭터를 공략하는 **UGC 인터랙티브 캐릭터 톡 시뮬레이션 플랫폼**입니다.

[온더훅](https://namu.wiki/w/%EC%98%A8%EB%8D%94%ED%9B%85) 스타일의 선택지 기반 스토리 공략 시스템과 생성형 AI 기반 캐릭터·시나리오 빌더를 결합하여, 누구나 하나의 웹(PWA) 환경에서 캐릭터를 창작하고 플레이할 수 있도록 설계되었습니다.

## 주요 기능

| 영역 | 기능명 | 상세 설명 |
| :--- | :--- | :--- |
| **톡 플레이** | **선택지 기반 공략 모드 (기본)** | 제작된 시나리오와 선택지 분기 스크립트에 따라 메신저 대화를 진행하며 호감도 및 엔딩을 공략합니다. |
| **톡 플레이** | **실시간 AI 자유 대화 모드 (BYOK)** | 사용자가 개인 AI API 키(Gemini, Claude, OpenRouter 등)를 등록하고 상단 토글을 켜면, 선택지 외에 직접 원하는 대답을 입력하여 실시간 AI 응답과 호감도 판정을 받을 수 있습니다. |
| **톡 플레이** | **메신저 리얼리티 연출** | 읽음 표시(`1`) 사라짐, 상대방 입력 중(`···`) 인디케이터, 연속 말풍선 전송, 조건부 선톡 및 웹 푸시 알림을 지원합니다. |
| **제작 스튜디오** | **AI 보조 캐릭터·시나리오 생성** | 캐릭터의 성격·말투·세계관을 입력하면 AI가 초기 호감도 단계(0~100), 챕터 구조, 기본 이벤트 및 대화 분기 스크립트를 자동 생성합니다. |
| **제작 스튜디오** | **커스텀 이벤트 및 컷씬(CG) 배치** | 제작자가 원하는 호감도 구간이나 특정 분기 단계에 일러스트 컷씬(CG)을 지정하고, 직접 커스텀 이벤트와 대사를 추가·편집할 수 있습니다. |
| **세계관 확장** | **동일 제작자 캐릭터 관계도 연결** | 같은 제작자가 만든 캐릭터 간의 관계(친구, 라이벌, 연인 등)를 연결하여 대화 중 타 캐릭터의 안부·호감도 상태를 언급하거나, 특별 이벤트에서 타 캐릭터가 개입하는 연출을 지원합니다. |
| **플랫폼 환경** | **통합 반응형 웹 & PWA** | 단일 Flutter Web 코드베이스로 플레이와 제작 도구를 모두 제공하며, 모바일 홈 화면 추가(PWA Standalone) 시 네이티브 앱과 동일한 전체 화면 조작감을 제공합니다. |

## 시스템 아키텍처

클라이언트(Flutter Web/PWA)와 백엔드(Dart Server + DB)를 단일 언어(Dart) 기반으로 구성하여 데이터 모델과 검증 로직을 공유하며, Synology NAS의 Docker 컨테이너 환경에서 구동됩니다.

| 계층 | 구성 요소 | 역할 및 설명 |
| :--- | :--- | :--- |
| **Client** | **Flutter Web (PWA) + Riverpod** | 반응형 메신저 UI, 캐릭터 허브, 제작 스튜디오, 컷씬 앨범, 모바일 당겨서 새로고침 방지 적용 |
| **Backend** | **Dart Server (Shelf / Dart Frog)** | REST API & WebSocket 통신, 호감도·플래그 상태 검증, 선톡 스케줄러, AI 프롬프트 라우팅 |
| **Database** | **SQLite / PostgreSQL + 로컬 스토리지** | 다수 유저 계정, 배포된 캐릭터·시나리오·관계도 그래프, 유저별 플레이 세이브, 컷씬 이미지 저장 |
| **External** | **AI API & Web Push (FCM)** | 캐릭터 생성용 서버 AI 연동, 플레이어 BYOK 실시간 대화 중계, 백그라운드 선톡 알림 발송 |

## 데이터베이스 스키마 요약

| 테이블명 | 주요 컬럼 | 설명 |
| :--- | :--- | :--- |
| `users` | `id`, `username`, `password_hash`, `fcm_token` | 사용자 계정 및 웹 푸시 알림 토큰 관리 |
| `characters` | `id`, `creator_id`, `name`, `worldview_prompt`, `affection_stages_json`, `is_published` | 제작된 캐릭터 기본 정보, 세계관 프롬프트, 호감도 구간 정의 및 배포 상태 |
| `character_relations` | `id`, `creator_id`, `from_character_id`, `to_character_id`, `relation_label`, `reaction_rule_json` | 동일 제작자 캐릭터 간 관계 정의 및 타 캐릭터 호감도 조건부 반응 규칙 |
| `scenario_events` | `id`, `character_id`, `event_type`, `unlock_condition_json`, `cutscene_image_url`, `cutscene_trigger_step`, `participants_json` | 챕터/커스텀/난입 이벤트 해금 조건 및 단계별 컷씬(CG) 출력 타이밍 |
| `script_nodes` | `id`, `event_id`, `step_order`, `speaker_character_id`, `messages_json`, `choices_json` | 이벤트 내 말풍선 대사 배열, 화자 지정, 3지선다 선택지 및 분기 정보 |
| `user_play_sessions` | `id`, `user_id`, `character_id`, `current_affection`, `current_event_id`, `flags_json`, `memory_summary` | 플레이어별 캐릭터 호감도, 진행 단계, 획득 플래그 및 AI 장기기억 요약 |
| `chat_logs` | `id`, `session_id`, `sender_type`, `speaker_character_id`, `message_text`, `is_read` | 세션별 누적 대화 로그 및 읽음(`1`) 표시 상태 |
| `user_unlocked_gallery` | `id`, `user_id`, `character_id`, `event_id`, `cutscene_image_url`, `unlocked_at` | 플레이어가 해금한 이벤트 컷씬(CG) 및 엔딩 컬렉션 |

## 프로젝트 디렉토리 구조

테마 및 디자인 토큰을 `lib/core/theme` 하위에 모듈화([taskflow_example](https://github.com/SirohaKR/taskflow_example) 구조 참고)하고, 기능 단위로 상태 관리(Riverpod)와 화면을 분리한 Feature-first 아키텍처를 따릅니다.

```text
mallangtalk/
├── docker-compose.yml                # Synology NAS 배포용 통합 컨테이너 설정
├── Dockerfile                        # Flutter Web 빌드 및 Dart 서버 실행 이미지
├── web/
│   ├── index.html                    # PWA 메타태그 및 모바일 당겨서 새로고침 방지 CSS
│   └── manifest.json                 # Standalone 웹앱 설정
├── server/                           # NAS 백엔드 서버 (Dart)
│   ├── bin/server.dart
│   └── lib/
│       ├── api/                      # 유저, 캐릭터 허브, 채팅, 스튜디오 라우터
│       ├── services/                 # AI 생성기, 관계도 상태 참조기, 선톡 스케줄러
│       └── db/                       # 데이터베이스 스키마 및 스토리지 매니저
└── lib/                              # Flutter 클라이언트 (플레이 + 제작 통합 웹앱)
    ├── main.dart                     # 앱 진입점 및 ProviderScope 초기화
    ├── app.dart                      # MaterialApp.router 및 글로벌 테마 연결
    ├── core/
    │   ├── theme/
    │   │   ├── app_colors.dart       # 파스텔 톡 배경, 말풍선, 호감도 단계별 색상 상수
    │   │   ├── app_text_styles.dart  # 말풍선, 선택지, 헤더 타이포그래피 정의
    │   │   ├── app_spacing.dart      # 여백, 말풍선 곡률(Radius), 반응형 브레이크포인트
    │   │   └── app_theme.dart        # 라이트/다크/캐릭터 테마 ThemeData 조합
    │   ├── network/                  # API 클라이언트 및 BYOK 헤더 인터셉터
    │   └── router/                   # GoRouter 기반 화면 라우팅
    ├── shared/
    │   ├── models/                   # Character, ScenarioEvent, Choice, Relation 모델
    │   └── widgets/                  # 공통 버튼, 프로필 아바타, 컷씬 모달 뷰어
    └── features/
        ├── auth/                     # 로그인 및 개인 AI API 키(BYOK) 설정
        ├── hub/                      # 배포된 캐릭터 탐색 및 관계도 미리보기
        ├── chat/                     # 톡 플레이 화면, 선택지 패널, 실시간 AI 입력 토글
        ├── studio/                   # 캐릭터 생성(AI 보조), 이벤트·컷씬 배치, 관계도 에디터
        └── album/                    # 해금한 이벤트 컷씬(CG) 및 엔딩 수집함
```

## 시작하기 (로컬 개발 환경)

### 요구 사항
- Flutter SDK `>=3.24.0`
- Dart SDK `>=3.5.0`
- Docker & Docker Compose (서버 배포 시)

### 실행 방법

```bash
# 1. 저장소 클론 및 패키지 설치
git clone https://github.com/SirohaKR/mallangtalk.git
cd mallangtalk
flutter pub get

# 2. Flutter Web 로컬 개발 서버 실행
flutter run -d chrome --web-port=8080

# 3. 테스트 (샘플 전체 플레이, 일상 대화 순서, 진행 저장, 편집기 초안 변환, 특별 이벤트, AI 생성·자유대화 요청 형식, 하단 탭 흐름)
flutter test
```

### 앱 화면 구성 (하단 탭)
| 탭 | 하는 일 |
| :--- | :--- |
| **내 캐릭터** | 친구로 추가했거나 만든 캐릭터 목록. 프로필에서 캐릭터 설정 보기, 1:1 채팅, 앨범, 대화 속도, 처음부터 다시, 고치기(만든 캐릭터), 캐릭터 파일로 내보내기, 삭제 |
| **채팅** | 대화 중인 캐릭터 목록. 마지막 말풍선, '입력 중...', 안 읽은 톡 숫자 표시 |
| **캐릭터 추가** | **받아오기**: AI 챗 플랫폼처럼 캐릭터 갤러리(썸네일·한줄 소개·태그). 누르면 상세 화면에서 설정을 보고 `친구 추가` / **만들기**: 앱 안 편집기(직접 입력 + AI로 만들기) |
| **설정** | 내 프로필(기본 별명, 나에 대한 한줄 소개), 쓸 AI 회사(Claude·ChatGPT·Gemini 드롭다운)와 그 회사 키·모델(목록 또는 직접 입력) |

- **채팅 시작과 별명**: 친구로 추가한 캐릭터와 처음 대화할 때 '이 대화에서 쓸 내 별명'을 묻고(설정의 기본 별명이 미리 들어감) 정한 뒤에 톡이 오기 시작합니다. 대화방 메뉴에서 언제든 바꿀 수 있습니다. 대본과 설정의 `{{user}}`(또는 `{이름}`)는 별명으로, `{{char}}`는 캐릭터 이름으로 바뀌고, 뒤에 붙은 조사(아/야, 이/가, 은/는, 을/를, 과/와, 이랑/랑)는 받침에 맞게 바뀝니다.
- **대화 속도**: 캐릭터마다 따로 정합니다(대화방 메뉴 또는 프로필의 `대화 속도`: 리얼하게 / 조금 빠르게 / 빠르게).
- **컷씬**: 대화 중 컷씬 장면에 도달하면 팝업 없이 앨범에 바로 모입니다.

### 캐릭터 만들기
- **캐릭터 설정 항목** (캐릭터 아카이브 [loreshelf](https://github.com/SirohaKR/loreshelf) 참고): 플레이어에게는 갤러리 상세·프로필에 **캐릭터 정보**(나이·직업 등 항목, 자물쇠로 숨김 가능) / **캐릭터 설정** / **세계관 설정** / **나는 이 이야기에서** / **주변 인물**만 보입니다. 호감도 단계, 이야기 분량, 타자 스타일, 성격 막대, 대사 예시, 비밀 설정은 제작자와 AI만 씁니다(비밀은 AI 자유대화에 '서서히 드러낼 설정'으로 넘어감).
- **앱 안 편집기** (엑셀 대신): `캐릭터 추가 > 만들기`의 **캐릭터 / 호감도 단계 / 이벤트 / 대사** 탭에서 만듭니다. 캐릭터 탭은 기본 정보 → 캐릭터 정보 → 캐릭터 설정 → 세계관 설정 → 나는 이 이야기에서 → 주변 인물 → 비밀 설정 → 말투와 타자 스타일 순서로 한 화면에 한 항목씩 넘기며, 긴 설정은 화면을 채우는 넓은 칸에 쓰고 글자 수를 보여 줍니다. 이벤트 탭에서 호감도 이벤트·일상 대화·특별 이벤트·엔딩을 추가하고 순서를 바꾸며, 대사 탭에서 장면마다 캐릭터 말풍선(빠르기·사진)과 내 선택지(내가 보내는 톡, 호감도, 다음 장면)를 넣습니다. 저장할 때 빠진 곳을 알려 주고, 좋은 선택만으로 끝까지 못 가면 호감도를 자동으로 맞출지 묻습니다. 만든 캐릭터는 내 캐릭터 프로필의 `고치기`로 다시 열고, 메뉴에서 예시 캐릭터 불러오기 / 캐릭터 파일(.json) 불러오기·내보내기를 할 수 있습니다.
- **AI로 만들기**: 캐릭터 탭에 적은 설정과 호감도 단계를 토대로, 단계별 이벤트·일상 대화 수와 특별 이벤트 수를 고르면 설정에서 고른 AI가 목차와 모든 대사를 써서 편집기에 채웁니다. 비어 있는 한줄 소개·태그·세계관·캐릭터 정보도 채우고, 제작자가 적은 칸은 그대로 둡니다. 이벤트 하나만 골라 `AI로 대사 쓰기`도 됩니다(제목·줄거리 메모 참고). 지금은 설정의 내 키로 부르고, 공개할 때는 제작자 키 또는 앱 토큰 충전 방식으로 `ClaudeStudioClient`의 키 공급만 바꾸면 됩니다.
- **호감도 단계와 일상 대화**: 이벤트·일상 대화마다 호감도 단계 이름을 붙입니다. 이벤트는 그 단계가 되면 열리고, 일상 대화(`event_type: daily`)는 그 단계에 머무는 동안에만 호감도 이벤트 사이사이에 하나씩 나옵니다. 다음 이벤트 조건이 안 맞으면 남은 일상 대화로 호감도를 더 쌓을 기회를 줍니다. 일상 대화는 공략 완료 조건에 들어가지 않습니다.
- **시간 표시와 특별 이벤트**: 이벤트 앞의 안내는 실제 시계와 어긋나지 않도록 `다음 날`, `그날 밤`, `며칠 뒤`처럼 **장면 전환 문구**로만 씁니다. 시간대가 중요한 대화는 **특별 이벤트**(`event_type: special`, `real_time: {from_hour, to_hour, date}`)로 만들어, 플레이어가 실제로 그 시각(예: 밤 10시~새벽 2시, 12월 25일)에 대화방에 있을 때만 한 번 옵니다. 첫 이벤트를 끝낸 뒤부터 오고, 다시 하기를 해도 또 오지 않으며, 공략 조건에는 들어가지 않습니다. 공략을 끝낸 뒤에도 그 시간에 들어오면 옵니다.
- **타자 속도**: 캐릭터마다 타자 스타일(번개같이 0.6 ~ 한참 고민 1.7)이 있고, 말풍선마다 읽고 멈칫 → 입력 중(글자당 약 0.15초) → 망설이는 말은 치다 멈췄다 다시 치는 연출을 합니다. 캐릭터별 대화 속도가 여기에 곱해집니다.

### 사용량·플레이 시간 재 보기
`flutter test tool/measure_usage_test.dart`를 돌리면 50개 대화짜리 캐릭터를 AI로 만들 때의 모델별 토큰·금액과 예상 플레이 시간을 `build/usage_report.md`로 뽑아 줍니다. 실제 API는 부르지 않고, 예시 캐릭터 대사로 응답 길이를 어림합니다.

### 자유대화(BYOK) 써 보기
설정 탭에서 AI 회사(Claude·ChatGPT·Gemini)를 고르고 그 회사 API 키를 넣고 모델을 고른 뒤, 채팅방의 `자유대화` 스위치를 켜고 직접 입력하면 캐릭터가 AI로 답장합니다. 엔터로 보낸 뒤에도 입력창에 커서가 남아 짧게 여러 번 이어서 보낼 수 있습니다. 키는 브라우저 저장소에만 남고, 키는 회사마다 따로 저장돼요. 지금은 서버가 없어서 브라우저에서 각 회사 API를 바로 호출합니다(`lib/core/network/ai_provider.dart`)(4단계 Dart 서버가 생기면 서버 중계로 전환 예정).

### 샘플 시나리오
`assets/scenarios/sample_character.json`에 샘플 캐릭터 **윤도하**(1년 된 남사친)의 캐릭터 설정, 호감도 이벤트 6개, 단계별 일상 대화 6개, 특별 이벤트 2개(새벽, 밤), 엔딩이 들어 있습니다. 갤러리에는 예시 캐릭터 **서이준**(`example_seo_ijun.json`, `lib/features/studio/template_scenario.dart`를 고친 뒤 `dart run tool/make_example.dart`로 다시 만듦)도 있습니다. 이 파일 형식이 그대로 캐릭터 파일(.json) 내보내기/받아오기와 서버 데이터 형식의 기준입니다.

## Synology NAS (Docker) 배포 방법

GitHub에 푸시된 소스를 Synology NAS에서 클론한 뒤 Docker Compose로 빌드 및 실행합니다.

```bash
# 1. NAS SSH 접속 후 프로젝트 폴더 이동
cd /volume1/docker/mallangtalk

# 2. 환경 변수 파일(.env) 생성 및 서버용 기본 AI 키 설정
cp .env.example .env

# 3. Docker 컨테이너 빌드 및 백그라운드 실행
docker compose up -d --build
```

배포 후 Synology DSM의 **역방향 프록시(Reverse Proxy)** 설정에서 외부 HTTPS 도메인을 컨테이너 포트(기본 `8080`)로 연결하면 모바일 및 PC 브라우저에서 즉시 접속할 수 있습니다.
