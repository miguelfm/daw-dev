#!/usr/bin/env bash
# Mantén WSL aberto mentres haxa servizos deste proxecto en marcha.
set -euo pipefail
cd "$(dirname "$0")/.."

COMPOSE_ARGS=(-f compose.yaml)
if [[ -f compose.override.yaml ]]; then
    COMPOSE_ARGS+=(-f compose.override.yaml)
fi

# Bloqueo illado por usuario e proxecto para evitar colisións entre copias ou contas.
LOCK_BASE="${XDG_RUNTIME_DIR:-/tmp}"
[[ -d $LOCK_BASE && -w $LOCK_BASE ]] || LOCK_BASE=/tmp
PROJ_HASH=$(printf '%s' "$PWD" | cksum | awk '{print $1}')
LOCK_FILE="$LOCK_BASE/daw-dev-keep-alive-$(id -u)-${PROJ_HASH}.lock"

# Os arranques repetidos comparten unha única sesión de mantemento.
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0
while docker compose "${COMPOSE_ARGS[@]}" --profile frontend --profile doc ps --status running -q | grep -q .; do
    sleep 20
done
