# 말랑톡

Flutter 프론트와 Dart API, PostgreSQL을 한 저장소에서 독립적으로 개발·배포합니다.

```text
frontend/    Flutter UI · 상태 관리 · 기기 저장 · API 클라이언트
server/      HTTP API · 인증 · Repository · DB 마이그레이션
packages/    앱/서버 공통 AI 호출 코드
deploy/      nginx · 개별 배포 · 백업/복구 검증
docs/        API 계약 · NAS 운영 절차
```

## 로컬 개발

프론트와 서버는 각각 해당 폴더에서 실행합니다.

```sh
cd server
dart pub get
dart run bin/server.dart
```

DATABASE_URL이 없으면 DATA_DIR의 SQLite를 사용합니다. PostgreSQL 사용 시 서버 환경 변수에
DATABASE_URL을 설정합니다. 서버는 기본적으로 API만 제공합니다.

```sh
cd frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:5200
```

서버의 ALLOWED_ORIGINS에 실제 Flutter 개발 서버 origin을 등록해야 합니다.
예: Flutter를 `--web-port=5300`으로 실행하고 ALLOWED_ORIGINS=http://localhost:5300을 설정합니다.
배포 시 기본 구성은 같은 origin의 /api를 프록시하므로 CORS 추가 설정이 필요 없습니다.

## 검증

```sh
cd server
dart analyze
dart test
cd ../frontend
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn
```

PostgreSQL 통합 테스트는 비어 있는 전용 DB의 URL을 TEST_DATABASE_URL로 지정합니다.
운영 DB를 테스트에 사용하지 않습니다. GitHub Actions에서는 전용 PostgreSQL 서비스로 검증합니다.

## NAS 운영

[운영·이전·복구 절차](docs/OPERATIONS.md)를 먼저 읽으세요.
기존 NAS 폴더에서 바로 compose up을 실행하지 말고, 별도 폴더/포트에서 이전 검증 후 전환합니다.

- [API 계약과 코드 위치](docs/API.md)
- [시험 서버를 유지하는 본서버 전환](docs/PRODUCTION.md)
- [누적 작업 기록](WORK_LOG.md)
- 서버 이미지: 루트 Dockerfile
- 프론트 이미지: frontend/Dockerfile (빌드 컨텍스트는 저장소 루트)
- NAS Compose: docker-compose.yml
- 개발 당시의 설계 메모: DEV_NOTE.md (현재 코드와 다를 수 있는 과거 기록)

.env, 사용자 DB와 백업은 Git에서 제외됩니다. API 키는 프론트 빌드 인자에 넣지 않습니다.
