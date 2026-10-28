#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export PORT=5200
dc() { docker compose -p mallangtalk "$@"; }
case "${1:-}" in
  build) dc config --quiet; dc build api frontend ;;
  copy-trial-db) sh deploy/copy-trial-db.sh ;;
  start) dc up -d api frontend; dc ps ;;
  status) dc ps ;;
  logs) dc logs --tail=100 api frontend ;;
  frontend) dc build frontend; dc up -d --no-deps frontend ;;
  stop) dc stop api frontend ;;
  *) echo 'Usage: sh deploy/production.sh build|copy-trial-db|start|status|logs|frontend|stop'; exit 64 ;;
esac
