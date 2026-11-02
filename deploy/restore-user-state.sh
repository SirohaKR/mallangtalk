#!/bin/sh
# 한 사람의 앱 저장값(user_state: 채팅방·캐릭터 목록·대화 기록·앨범·프로필…)을 예전 값으로 되돌립니다.
# 다른 사람 데이터와 캐릭터·사진 표는 건드리지 않습니다. --apply 없이 돌리면 비교만 보여 줍니다.
#
#   sh deploy/restore-user-state.sh list <아이디>
#       최근에 바뀐 기록(user_state_history)과 백업 파일 목록을 보여 줌
#   sh deploy/restore-user-state.sh dump <아이디> data/backups/postgres-YYYYMMDD-HHMMSS.dump [--apply]
#       백업 파일에 있던 그 사람 값으로 되돌림
#   sh deploy/restore-user-state.sh history <아이디> "2026-11-02 12:00" [--apply]
#       그 시각(한국 시간) 바로 전 값으로 되돌림 (2026-11-02 기록 기능을 넣은 뒤 바뀐 것만 가능)
#   맨 뒤에 --only=항목1,항목2 를 붙이면 그 항목만 비교·되돌림 (예: --only=run_char_serena_astin)
#
# 되돌린 값은 지금 시각으로 저장돼서, 폰·PC가 다음에 열 때 이 값을 받아 갑니다.
# --apply 전에 deploy/backup.sh로 전체 백업을 먼저 남깁니다.
set -eu
cd "$(dirname "$0")/.."

# 시험할 때만 바꿈: PSQL="psql -h ... -U ..." PG_RESTORE="pg_restore -h ..." DB=... SHARED_DIR=/tmp
PSQL="${PSQL:-docker compose exec -T db psql -U mallangtalk}"
PG_RESTORE="${PG_RESTORE:-docker compose exec -T db pg_restore -U mallangtalk}"
DB="${DB:-mallangtalk}"
RESTORE_DB="${DB}_restore"
SHARED_DIR="${SHARED_DIR:-/tmp}" # db 컨테이너 안 경로 (CSV를 잠깐 둠)
SKIP_BACKUP="${SKIP_BACKUP:-}"

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
}

mode="${1:-}"
user="${2:-}"
[ -n "$mode" ] && [ -n "$user" ] || usage
case "$user" in *"'"*) echo '아이디에 작은따옴표는 쓸 수 없어요.'; exit 64 ;; esac

apply=""
only=""
for arg in "${4:-}" "${5:-}"; do
  case "$arg" in
    --apply) apply=1 ;;
    --only=*) only="${arg#--only=}" ;;
    "") ;;
    *) echo "알 수 없는 옵션: $arg"; usage ;;
  esac
done

q() { $PSQL -v ON_ERROR_STOP=1 -X -q "$@"; }

user_id=$(q -d "$DB" -At -v u="$user" <<'SQL'
SELECT id FROM users WHERE lower(username) = lower(:'u');
SQL
)
[ -n "$user_id" ] || { echo "아이디 '$user'를 찾지 못했어요."; exit 1; }

# 되돌릴 값(user_state_restore: key, value, updated_at)을 지금 값과 비교해서 보여 줌
show_compare() {
  if [ -n "$only" ]; then
    q -d "$DB" -v only="$only" <<'SQL'
DELETE FROM user_state_restore WHERE NOT (key = ANY (string_to_array(:'only', ',')));
SQL
  fi
  q -d "$DB" -v uid="$user_id" <<'SQL'
\pset footer off
SELECT r.key AS "항목",
       coalesce(octet_length(s.value), 0) AS "지금 크기",
       coalesce(octet_length(r.value), 0) AS "되돌릴 크기",
       to_char(to_timestamp(s.updated_at / 1000.0) AT TIME ZONE 'Asia/Seoul', 'MM-DD HH24:MI') AS "지금 값 시각",
       to_char(to_timestamp(r.updated_at / 1000.0) AT TIME ZONE 'Asia/Seoul', 'MM-DD HH24:MI') AS "되돌릴 값 시각"
FROM user_state_restore r
LEFT JOIN user_state s ON s.user_id = :uid AND s.key = r.key
WHERE s.value IS DISTINCT FROM r.value
ORDER BY coalesce(octet_length(r.value), 0) - coalesce(octet_length(s.value), 0) DESC, r.key;
SELECT count(*) AS "바뀌는 항목 수" FROM user_state_restore r
LEFT JOIN user_state s ON s.user_id = :uid AND s.key = r.key
WHERE s.value IS DISTINCT FROM r.value;
SQL
}

apply_restore() {
  if [ -z "$SKIP_BACKUP" ]; then sh deploy/backup.sh; fi
  q -d "$DB" -v uid="$user_id" <<'SQL'
BEGIN;
INSERT INTO user_state (user_id, key, value, updated_at)
SELECT :uid, r.key, r.value,
       (extract(epoch FROM clock_timestamp()) * 1000)::bigint + 1000
FROM user_state_restore r
LEFT JOIN user_state s ON s.user_id = :uid AND s.key = r.key
WHERE s.value IS DISTINCT FROM r.value
ON CONFLICT (user_id, key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;
COMMIT;
SQL
  echo '되돌렸어요. 폰·PC에서 말랑톡을 새로고침하면 이 값을 받아 가요.'
}

prepare_table() {
  q -d "$DB" <<'SQL'
DROP TABLE IF EXISTS user_state_restore;
CREATE TABLE user_state_restore (key TEXT PRIMARY KEY, value TEXT, updated_at BIGINT NOT NULL);
SQL
}

drop_table() { q -d "$DB" -c 'DROP TABLE IF EXISTS user_state_restore'; }

case "$mode" in
  list)
    q -d "$DB" -v uid="$user_id" <<'SQL'
\pset footer off
\echo '최근에 바뀐 기록 (바뀌기 직전 값, 최근 40개)'
SELECT to_char(replaced_at AT TIME ZONE 'Asia/Seoul', 'YYYY-MM-DD HH24:MI:SS') AS "바뀐 시각(한국)",
       key AS "항목", coalesce(octet_length(value), 0) AS "그때 크기"
FROM user_state_history WHERE user_id = :uid ORDER BY id DESC LIMIT 40;
SQL
    echo '백업 파일:'
    ls -1 data/backups/*.dump 2>/dev/null || echo '  (data/backups에 백업 파일이 없어요)'
    ;;
  dump)
    dump="${3:-}"
    [ -n "$dump" ] && [ -s "$dump" ] || { echo "백업 파일을 찾지 못했어요: $dump"; exit 1; }
    q -d "$DB" -c "DROP DATABASE IF EXISTS $RESTORE_DB" -c "CREATE DATABASE $RESTORE_DB"
    trap 'q -d "$DB" -c "DROP DATABASE IF EXISTS $RESTORE_DB" >/dev/null 2>&1 || true' EXIT
    $PG_RESTORE --no-owner -d "$RESTORE_DB" < "$dump"
    prepare_table
    q -d "$RESTORE_DB" -v u="$user" -v out="$SHARED_DIR/user_state_restore.csv" <<'SQL'
\set copy_cmd '\\copy (SELECT s.key, s.value, s.updated_at FROM user_state s JOIN users u ON u.id = s.user_id WHERE lower(u.username) = lower(' :'u' ')) TO ' :'out' ' WITH (FORMAT csv)'
:copy_cmd
SQL
    q -d "$DB" -v in="$SHARED_DIR/user_state_restore.csv" <<'SQL'
\set copy_cmd '\\copy user_state_restore FROM ' :'in' ' WITH (FORMAT csv)'
:copy_cmd
SQL
    show_compare
    if [ -n "$apply" ]; then apply_restore; else echo '비교만 했어요. 되돌리려면 맨 뒤에 --apply를 붙여 다시 실행하세요.'; fi
    drop_table
    ;;
  history)
    at="${3:-}"
    [ -n "$at" ] || usage
    prepare_table
    # 그 시각 뒤에 처음 바뀌기 직전 값 = 그 시각의 값
    q -d "$DB" -v uid="$user_id" -v at="$at" <<'SQL'
INSERT INTO user_state_restore (key, value, updated_at)
SELECT DISTINCT ON (key) key, value, updated_at FROM user_state_history
WHERE user_id = :uid AND replaced_at >= (:'at'::timestamp AT TIME ZONE 'Asia/Seoul')
ORDER BY key, id ASC;
SQL
    show_compare
    if [ -n "$apply" ]; then apply_restore; else echo '비교만 했어요. 되돌리려면 맨 뒤에 --apply를 붙여 다시 실행하세요.'; fi
    drop_table
    ;;
  *) usage ;;
esac
