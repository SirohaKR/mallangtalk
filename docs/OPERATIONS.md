# NAS 배포 및 데이터 운영

## 구성

한 Private Git 저장소에서 frontend(Flutter/nginx), api(Dart), db(PostgreSQL)를 독립 관리한다.
NAS 외부 5200 포트는 프론트에 연결되고 /api 요청은 Docker 내부 API로 전달된다.
API와 DB 포트는 호스트에 공개하지 않는다. 기존 NAS HTTPS 역방향 프록시는
대상을 NAS의 HTTP 5200으로 유지할 수 있다. HTTPS 인증서 설정은 별도 확인해야 한다.

## 첫 전환: 운영 서버에 바로 덮어쓰지 않기

1. 기존 소스의 Git 커밋, Docker 이미지 ID, `.env`, Compose 파일, 중지 상태의 data 백업을 보관한다.
2. 새 코드는 별도 NAS 폴더에 준비한다. 기존 data는 수정하거나 이동하지 않는다.
3. `.env.example`을 `.env`로 복사한다. 기존 AI 설정은 필요한 항목만 옮긴다.
   POSTGRES_PASSWORD에는 길고 무작위인 영문·숫자를 사용한다(URL 예약문자 처리 실수 방지).
   테스트 기간에는 PORT=5201처럼 기존 서비스와 다른 포트를 지정한다.
4. 기준 백업의 data 폴더 안 파일들을 새 폴더의 `data/import/`에 복사한다.
   `data/import/mallangtalk.db`가 존재해야 하며 WAL/SHM도 있으면 함께 둔다.
5. 아래 순서로 실행한다. 운영 중인 기존 컨테이너에는 영향을 주지 않는다.

```sh
sh deploy/trial.sh build
sh deploy/trial.sh import
sh deploy/trial.sh start
```

시험용 스크립트는 프로젝트 이름을 `mallangtalk-trial`, 공개 포트를 기본 5201로 고정한다.
다른 폴더여도 Compose의 name이 같으면 기존 프로젝트를 공유할 수 있으므로, 시험 배포에서는
반드시 이 스크립트를 사용한다. 포트가 사용 중이면 `TRIAL_PORT=5202 sh deploy/trial.sh start`처럼
모든 단계에서 같은 TRIAL_PORT를 지정한다. .env는 시험 폴더에 별도로 만든다.
진행 상태는 `sh deploy/trial.sh status`, 로그는 `sh deploy/trial.sh logs`로 확인한다.
시험 DB의 백업 명령을 직접 실행할 때도 `docker compose -p mallangtalk-trial ...`을 사용한다.
기본 backup/update 스크립트는 운영 프로젝트용이며 시험 프로젝트에 사용하지 않는다.
시험 사이트의 프론트만 수정했을 때는 `sh deploy/trial.sh frontend`로 빌드·갱신한다.
이 명령은 DB 가져오기를 다시 실행하지 않는다.

가져오기는 비어 있는 DB에만 허용한다. 전체 행과 이미지 바이트의 지문을 비교하고,
차이가 있으면 데이터 INSERT 트랜잭션을 롤백한다. 원본의 비밀번호 해시·세션·ID·시간을 보존한다.
스키마 마이그레이션은 별도 트랜잭션으로 적용되어 가져오기 실패 후에도 빈 테이블이 남을 수 있다.
실패했다고 임의로 DB 볼륨을 삭제하지 않는다. 원인을 확인하고 빈 DB에 다시 실행한다.

로그인, 캐릭터 조회/수정, 사진, 친구 추가, 진행도 저장, 다른 기기 동기화, AI 설정을 검증한다.
검증용 과거 백업 이후 운영 데이터가 바뀌면 최종 전환 전에 기존 서버를 중지하고 최신 백업으로
새로운 빈 PostgreSQL에 다시 가져온다. 테스트 DB를 그대로 운영으로 승격해 최신 데이터를 잃지 않는다.
최종 전환 후에는 기존 앱 서버를 멈추고 프론트 PORT를 5200으로 바꿔 실행한다.

## 복구

새 앱 사용 전에 문제가 발견되면 새 프론트/API를 중지하고, 보관한 기존 이미지·Compose·원본 SQLite
data 폴더로 예전 서버를 다시 시작한다. 새 앱에서 쓰기가 발생한 뒤 SQLite로 돌아가면 그 이후 기록은
자동 합쳐지지 않는다. 이 경우 양쪽 DB를 보존하고 별도 이전 계획을 세운다.
PostgreSQL의 schema_migrations에 기록된 버전보다 낮은 서버는 자동 실행하지 않는다.
기존 마이그레이션을 수정하지 말고 다음 번호로 추가한다.

## 백업과 복구 연습

```sh
sh deploy/backup.sh
sh deploy/verify-backup.sh data/backups/postgres-YYYYMMDD-HHMMSS.dump
```

이미지는 현재 DB BYTEA에 함께 보관하므로 dump에 포함된다. 이미지 경로와 해시를 보존하기 위해
이번 이전에서 외부 파일 저장소로 동시에 옮기지는 않는다. 이후 용량 때문에 옮길 경우 별도
마이그레이션·복구 검증으로 진행한다. 대화 저장값도 원본을 그대로 보존한다.

DSM 작업 스케줄러에서 매일 backup.sh를 실행하고, 백업을 다른 장치에도 복사한다.
복구 검증은 격리된 임시 DB에만 수행한다. 보관 기간/삭제는 운영자가 정하며 스크립트는 자동 삭제하지 않는다.
PostgreSQL 볼륨의 실행 중 파일을 직접 압축하는 방식 대신 pg_dump를 사용한다.
DB 조회는 `docker compose exec db psql -U mallangtalk -d mallangtalk` 또는 SSH 터널을 이용한
DBeaver/pgAdmin 접속을 사용한다. 공개 DB 포트나 공개 관리자 화면을 추가하지 않는다.
`character_overview`와 `user_state_overview` 뷰에서 캐릭터 이름·소유자·친구 수 및 계정별 저장 종류를 조회할 수 있다.

## 업데이트와 상태 확인

```sh
sh deploy/update.sh frontend
sh deploy/update.sh api
docker compose logs --tail=100 api
```

API 업데이트는 먼저 백업하고 빌드한다. `/api/health`로 API 응답을 확인하고 실제 로그인/저장을 함께 점검한다.
health는 기본 HTTP 상태 확인이며 `/api/ready`는 DB 쿼리 성공까지 확인한다.

## Private GitHub

NAS 전용 SSH 키를 만들고 GitHub Settings → Deploy keys에 공개키를 읽기 전용으로 등록한다.
비밀키는 NAS 사용자 홈의 .ssh에만 두고 저장소에 넣지 않는다. SSH 호스트 키를 검증한 뒤
`git@github.com:OWNER/REPO.git`으로 clone/pull한다. 배포 전 변경 내용을 검토하고 검증된 커밋을 사용한다.
`.env`, data, DB dump와 실제 사용자 데이터는 Git에 추가하지 않는다. GitHub Private 여부는
웹 프론트가 브라우저에 전달되는 것과 별개이므로 프론트 빌드에 비밀키를 넣지 않는다.
