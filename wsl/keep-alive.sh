#!/usr/bin/env bash
# Mantén WSL aberto mentres haxa servizos deste proxecto en marcha.
set -eu
cd "$(dirname "$0")/.."

# Os arranques repetidos comparten unha única sesión de mantemento.
exec 9>/tmp/daw-dev-keep-alive.lock
flock -n 9 || exit 0
while docker compose ps --status running -q | grep -q .; do
    sleep 20
done
