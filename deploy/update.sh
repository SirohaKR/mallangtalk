#!/bin/sh
# Run only after reviewing the desired commit. Does not automatically git pull.
set -eu
cd "$(dirname "$0")/.."
case "${1:-}" in
  frontend) docker compose build frontend; docker compose up -d --no-deps frontend ;;
  api)
    sh deploy/backup.sh
    docker compose build api
    docker compose up -d --no-deps api
    ;;
  *) echo 'Usage: sh deploy/update.sh frontend|api'; exit 64 ;;
esac
docker compose ps
