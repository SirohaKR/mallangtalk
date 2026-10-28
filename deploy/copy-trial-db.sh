#!/bin/sh
# Run from the NEW production source folder. Copy a snapshot, never share a volume.
set -eu
cd "$(dirname "$0")/.."
source_container=mallangtalk-trial-db-1
dc() { docker compose -p mallangtalk "$@"; }

dc config --quiet
source_project=$(docker inspect "$source_container" --format '{{index .Config.Labels "com.docker.compose.project"}}')
test "$source_project" = mallangtalk-trial || { echo 'Unexpected source project; stopped.'; exit 1; }
source_volume=$(docker inspect "$source_container" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}')
test "$source_volume" = mallangtalk-trial_postgres_data || { echo 'Unexpected source DB volume; stopped.'; exit 1; }
running_api=$(dc ps -q --status running api)
test -z "$running_api" || { echo 'Production API is running. Stop it before importing.'; exit 1; }

dc create db
target_container=$(dc ps -a -q db)
test -n "$target_container"
target_volume=$(docker inspect "$target_container" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}')
test "$target_volume" = mallangtalk_postgres_data || { echo 'Unexpected production volume; stopped before starting it.'; exit 1; }
test "$target_volume" != "$source_volume" || { echo 'Source and target must be separate volumes.'; exit 1; }
dc up -d db
attempt=0
until dc exec -T db pg_isready -U mallangtalk -d mallangtalk > /dev/null 2>&1; do
  attempt=$((attempt+1))
  test "$attempt" -lt 90 || { echo 'Production database did not become ready.'; exit 1; }
  sleep 1
done
scalar() {
  result=$(dc exec -T db psql -U mallangtalk -d mallangtalk -At -v ON_ERROR_STOP=1 -c "$1") || return 1
  printf '%s' "$result" | tr -d '[:space:]'
}
tables=$(scalar "SELECT count(*) AS table_count FROM pg_tables WHERE schemaname='public';")
if test "$tables" != 0; then
  # A previous API start may have created tables but no application data.
  # Migration version rows are metadata, not a reason to discard a valid copy.
  unknown=$(scalar "SELECT count(*) AS unexpected_tables FROM pg_tables WHERE schemaname='public' AND tablename NOT IN ('users','sessions','characters','images','user_state','character_friends','schema_migrations');")
  test "$unknown" = 0 || { echo 'Unexpected production tables. Nothing overwritten.'; exit 1; }
  rows=$(scalar 'SELECT ((SELECT count(*) FROM users)+(SELECT count(*) FROM sessions)+(SELECT count(*) FROM characters)+(SELECT count(*) FROM images)+(SELECT count(*) FROM user_state)+(SELECT count(*) FROM character_friends)) AS app_rows;')
  test "$rows" = 0 || { echo 'Production DB contains application data. Nothing overwritten.'; exit 1; }
  echo 'Production schema exists, but all six application tables are empty.'
fi

mkdir -p data/backups
umask 077
backup="data/backups/trial-to-production-$(date +%Y%m%d-%H%M%S).dump"
partial="${backup}.partial"
trap 'rm -f "$partial"' EXIT HUP INT TERM
# Preserve even the empty target schema before the transactional replacement.
target_backup="data/backups/production-before-copy-$(date +%Y%m%d-%H%M%S).dump"
dc exec -T db pg_dump -U mallangtalk -d mallangtalk -Fc > "$partial"
test -s "$partial"
dc exec -T db pg_restore --list < "$partial" > /dev/null
mv "$partial" "$target_backup"
docker exec "$source_container" pg_dump -U mallangtalk -d mallangtalk -Fc > "$partial"
test -s "$partial"
docker exec -i "$source_container" pg_restore --list < "$partial" > /dev/null
mv "$partial" "$backup"
dc exec -T db pg_restore -U mallangtalk --clean --if-exists --exit-on-error --single-transaction -d mallangtalk < "$backup"
dc exec -T db psql -U mallangtalk -d mallangtalk -v ON_ERROR_STOP=1 -c \
  'SELECT (SELECT count(*) FROM users) AS users, (SELECT count(*) FROM characters) AS characters, (SELECT count(*) FROM images) AS images, (SELECT count(*) FROM user_state) AS state_items;'
printf 'Copied trial snapshot to independent production DB. Backup: %s\n' "$backup"
echo 'Trial remains unchanged. Changes after this snapshot are independent.'
