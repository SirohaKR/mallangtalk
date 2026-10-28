# 시험 서버를 유지하면서 본서버 개편하기

사용자가 선택한 최종 운영 방식이다. 시험 프로젝트를 이름만 바꾸거나 DB 볼륨을 공유하지 않는다.

| 구분 | 소스 폴더 | Compose 프로젝트 | 포트 | DB 볼륨 |
|---|---|---|---|---|
| 시험 | /volume1/docker/mallangtalk/mallangtalk-trial | mallangtalk-trial | 5201 | mallangtalk-trial_postgres_data |
| 본서버 | /volume1/docker/mallangtalk | mallangtalk | 5200 | mallangtalk_postgres_data |

## 준비

1. 최신 소스 ZIP을 본서버 폴더에 풀어 코드만 갱신한다. 기존 data와 하위 mallangtalk-trial은 삭제하지 않는다.
2. 본서버의 기존 .env를 data/backups에 별도 보관하고, 시험 폴더 .env를 본서버 .env로 복사한다.
3. 본서버 .env는 PORT=5200, 시험 .env는 PORT=5201로 지정한다. POSTGRES_PASSWORD는 시험에서
   정상 사용 중인 값을 그대로 복사할 수 있다. 파일은 채팅이나 Git에 올리지 않는다.
4. 이전에 NAS 시험 스크립트 기본값을 5200으로 바꿨다면 5201로 돌린다.
   본서버 실행은 production.sh, 시험 실행은 trial.sh를 사용한다.

본서버 폴더에서 아래를 실행한다. build/copy 단계까지는 5200 포트를 잡지 않는다.

```sh
sudo sh deploy/production.sh build
sudo sh deploy/production.sh copy-trial-db
```

copy-trial-db는 실행 중인 시험 PostgreSQL에서 일관된 pg_dump 스냅샷을 만들고, 본서버의
빈 DB에 단일 트랜잭션으로 복원한다. 공유 볼륨을 먼저 검사하고 본서버 API가 이미 동작 중이거나
애플리케이션 데이터가 있으면 덮어쓰지 않고 중단한다. API가 초기화한 테이블만 있는 경우에는
6개 데이터 테이블이 모두 비고 알려진 테이블만 존재하는지 확인한다. schema_migrations의 버전 기록은
초기화 메타데이터로 취급한다. 대상 구조도 먼저 백업한 뒤 --clean --if-exists와 단일 트랜잭션으로
복원하므로 별도의 볼륨 삭제나 수동 DROP이 필요하지 않다. 성공 후 반복 실행하지 않는다.
스냅샷 이후 시험에서 변경한 데이터는 본서버에 자동 반영되지 않는다.
pg_dump 파일은 본서버 data/backups에도 보관한다. 기존 SQLite 가져오기를 다시 실행하지 않는다.

## 포트와 서비스 전환

시험 서버를 5201로 되돌리는 명령은 시험 폴더에서 실행한다.

```sh
cd /volume1/docker/mallangtalk/mallangtalk-trial
sudo env TRIAL_PORT=5201 sh deploy/trial.sh start
```

그다음 이전 SQLite 단일 컨테이너를 중지하고 본서버 폴더에서 새 서버를 시작한다.
기존 mallangtalk_server가 이미 중지 상태여도 stop은 데이터 삭제를 하지 않는다.

```sh
sudo docker stop mallangtalk_server
cd /volume1/docker/mallangtalk
sudo sh deploy/production.sh start
sudo sh deploy/production.sh status
```

기존 5200 주소에서 시험 당시의 최신 캐릭터·대화·사진이 복사돼 있는지 확인한다.
5201에서도 시험 서버가 계속 열리는지 확인한다. 이후 두 DB는 독립적으로 변경된다.

## 이후 유지보수

- 본서버 프론트: `sudo sh deploy/production.sh frontend`
- 본서버 백업: 본서버 폴더에서 `sudo sh deploy/backup.sh`
- 시험 서버 프론트: 시험 폴더에서 `sudo sh deploy/trial.sh frontend`
- 시험 DB를 본서버로 자동 동기화하거나, 업데이트할 때마다 다시 가져오지 않는다.
- `down -v`, DB 볼륨 삭제, DB 데이터 폴더의 직접 파일 복사는 이 전환 절차에 포함되지 않는다.

## 초기 전환 실패 시

새 본서버에서 쓰기를 시작하기 전이라면 production.sh stop으로 새 API/프론트만 중지하고
보관한 기존 컨테이너를 다시 시작하는 방식으로 복구할 수 있다. 어느 DB에도 새 쓰기가 발생했다면
양쪽을 보존하고 그 이후 데이터 차이를 확인한 뒤 복구한다. 기존 SQLite 파일·시험 DB는 삭제하지 않는다.
