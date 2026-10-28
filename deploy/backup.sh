#!/bin/sh
# Run from any directory; schedule this through DSM Task Scheduler.
set -eu
cd "$(dirname "$0")/.."
mkdir -p data/backups
umask 077
backup="data/backups/postgres-$(date +%Y%m%d-%H%M%S).dump"
tmp="${backup}.partial"
trap 'rm -f "$tmp"' EXIT HUP INT TERM
docker compose exec -T db pg_dump -U mallangtalk -d mallangtalk -Fc > "$tmp"
test -s "$tmp"
# Check that the dump archive is readable before publishing it.
docker compose exec -T db pg_restore --list < "$tmp" > /dev/null
mv "$tmp" "$backup"
printf 'Backup saved: %s\n' "$backup"
