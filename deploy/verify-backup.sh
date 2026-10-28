#!/bin/sh
# Restore to an isolated temporary database, never over the application DB.
set -eu
cd "$(dirname "$0")/.."
test "$#" -eq 1 || { echo 'Usage: sh deploy/verify-backup.sh BACKUP.dump'; exit 64; }
test -f "$1"
restore_db="restore_check_$(date +%Y%m%d%H%M%S)_$$"
docker compose exec -T db createdb -U mallangtalk "$restore_db"
cleanup() { docker compose exec -T db dropdb -U mallangtalk "$restore_db"; }
trap cleanup EXIT HUP INT TERM
docker compose exec -T db pg_restore -U mallangtalk --exit-on-error --single-transaction -d "$restore_db" < "$1"
docker compose exec -T db psql -U mallangtalk -d "$restore_db" -v ON_ERROR_STOP=1 -c \
  'SELECT (SELECT count(*) FROM users) AS users, (SELECT count(*) FROM characters) AS characters, (SELECT count(*) FROM images) AS images, (SELECT count(*) FROM user_state) AS state_items;'
