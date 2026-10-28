#!/bin/sh
# Dedicated project and volume; never reuse the running production project.
set -eu
cd "$(dirname "$0")/.."
export PORT="${TRIAL_PORT:-5201}"
dc() { docker compose -p mallangtalk-trial "$@"; }
case "${1:-}" in
  build) dc config --quiet; dc build api frontend ;;
  import) dc --profile tools build import; dc up -d db; dc --profile tools run --rm import ;;
  start) dc up -d api frontend; dc ps ;;
  frontend) dc build frontend; dc up -d --no-deps frontend ;;
  status) dc ps ;;
  logs) dc logs --tail=100 api frontend ;;
  stop) dc stop ;;
  *) echo 'Usage: sh deploy/trial.sh build|import|start|frontend|status|logs|stop'; exit 64 ;;
esac
