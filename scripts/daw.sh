#!/usr/bin/env bash
set -euo pipefail

launcher=$(readlink -f -- "${BASH_SOURCE[0]}")
project_dir=$(cd -- "$(dirname -- "$launcher")/.." && pwd)
cd -- "$project_dir"
start=(up -d --wait --wait-timeout 300)

prepare_angular() {
    local image image_user
    image=$(docker compose --profile angular config --images angular)
    image_user=$(docker image inspect --format '{{.Config.User}}' "$image" 2>/dev/null || true)
    if [[ "$image_user" != node ]]; then
        docker compose --profile angular build angular
    fi
}

case "${0##*/}" in
    daw-start) exec docker compose "${start[@]}" --no-deps web "$@" ;;
    daw-start-db) exec docker compose "${start[@]}" db web "$@" ;;
    daw-start-all) exec docker compose "${start[@]}" "$@" ;;
    daw-start-angular)
        prepare_angular
        exec docker compose --profile angular "${start[@]}" angular "$@"
        ;;
    daw-stop) exec docker compose --profile angular stop "$@" ;;
    daw-status) exec docker compose --profile angular ps --all "$@" ;;
    daw-logs) exec docker compose --profile angular logs --tail 100 -f "$@" ;;
    daw-code) exec code --new-window "$project_dir" "$@" ;;
    daw-code-angular)
        prepare_angular
        docker compose --profile angular "${start[@]}" angular
        exec code --new-window docker/angular/DWCC-Angular.code-workspace "$@"
        ;;
    daw-code-proxecto)
        prepare_angular
        docker compose --profile angular "${start[@]}" db web angular
        exec code --new-window docker/angular/DAW-Proxecto.code-workspace "$@"
        ;;
    daw-help|daw.sh)
        printf '%s\n' 'daw-start | daw-start-db | daw-start-all | daw-start-angular' \
            'daw-stop | daw-status | daw-logs | daw-code | daw-code-angular | daw-code-proxecto'
        ;;
    *)
        printf 'Orde DAW Dev descoñecida: %s\n' "${0##*/}" >&2
        exit 2
        ;;
esac
