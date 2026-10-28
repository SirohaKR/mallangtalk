# API 계약

프론트는 `frontend/`, HTTP 서버는 `server/`에서 독립적으로 실행한다.
기본 경로는 `/api`. 웹의 `API_BASE_URL`이 비어 있으면 같은 origin을 사용한다.
다른 서버를 직접 호출할 때는 origin만 지정한다. 예: `https://api.example.com`.
API 주소에 `/api`를 붙이지 않는다. 서버의 `ALLOWED_ORIGINS`에는 허용할 프론트 origin을 쉼표로 구분한다.

인증은 `Authorization: Bearer <token>`. 서버에는 토큰 해시만 보관한다.
기존 앱과의 호환을 위해 JSON 필드명과 응답 형식을 유지한다.
실패 응답은 `{"error":"설명"}`, 재로그인이 필요하면 `needLogin: true`를 포함한다.

| 메서드 | 경로 | 기능 |
|---|---|---|
| GET | /api/health | API 기능 및 가동 확인. 비밀키는 반환하지 않음 |
| GET | /api/ready | DB 연결까지 확인. 실패 시 503 |
| POST | /api/auth/signup | username, password, nickname으로 가입 |
| POST | /api/auth/login | username, password로 로그인 |
| POST | /api/auth/logout | 현재 토큰 폐기 |
| GET | /api/me | 현재 계정 |
| PUT | /api/my/profile | nickname, avatar_url, intro 수정 |
| GET, PUT | /api/my/state | 계정별 기기 연동. PUT items는 key/value/updated_at 배열 |
| GET | /api/characters | 공개 캐릭터 목록 |
| GET | /api/my/characters | 내 캐릭터 목록 |
| GET, PUT, DELETE | /api/characters/:id | 캐릭터 조회·저장·삭제. 수정·삭제는 소유자만 가능 |
| POST, DELETE | /api/characters/:id/friend | 친구 추가·해제 |
| GET | /api/images/:id | 내용 해시로 식별하는 이미지 |
| POST | /api/ai/json | 서버 AI 키 사용이 활성화된 경우 AI 중계 |

현재 user_state는 기존 프론트 저장 형식을 그대로 유지한다. `updated_at`이 큰 값이 우선하며
삭제는 value=null인 tombstone으로 전달한다. 계정 변경 시 이전 계정의 전송 대기열은 비운다.
이미지의 `/api/images/...` 상대 주소는 API origin을 기준으로 해석한다.

DB 접근은 `Repository`, PostgreSQL 구현은 `database/postgres_repository.dart`,
기존 SQLite 구현은 `store.dart`, 인증 해시는 `security/credentials.dart`에 위치한다.
데이터 포맷 변경은 마이그레이션과 프론트 호환 정책을 함께 검토한다.

## 자유대화 사진

`POST /api/ai/json`의 선택적 `images`는 JPEG/PNG/WebP base64 data URL 배열이다.
최대 3장, 한 URL은 1,400,000자 이하로 제한하며 서버가 외부 이미지 URL을 가져오지 않는다.
직접 호출과 서버 중계 모두 제공사별 이미지 입력 형식으로 전달한다.
프론트는 기기 사진 선택·편집 후 사진을 말풍선의 photo_image에 저장하고 최근 첨부 최대 3장을 AI에 전달한다.
이 사용자 첨부는 진행 상태 JSON에 포함되므로 계정 동기화 및 DB 백업에도 함께 포함된다.
서버에 등록된 공유 키나 사용자 API 키가 없으면 전송을 막고 등록 안내를 표시한다.

## 자유대화 장면과 인용

메시지는 선택적으로 reply_to_id/reply_to_name/reply_to_text를 저장한다. 구버전 기록에는 없어도 된다.
수동 대화 종료는 기존 is_conversation_break 형식을 사용하므로 DB 스키마 변경이 필요하지 않다.
구분선 전후는 AI 요청에서 종료된 과거와 현재 장면으로 나눠 전달하고 사진은 현재 장면에서만 선택한다.
전체를 괄호 또는 별표로 감싼 사용자 입력은 행동·상황 지시로 구분하며 저장 원문은 유지한다.
침묵 선택지는 사용자 메시지를 생성하지 않는다. 자유대화 침묵 지시는 is_hidden=true인 문맥용
메시지로 보존하지만 말풍선과 채팅 목록 미리보기에서 제외한다. 구버전 메시지는 is_hidden 없이 읽힌다.
romance_ 접두사의 캐릭터별 설정은 계정 동기화 대상이다. 성인 확인은 자체 선언이며 신원 인증이 아니다.
