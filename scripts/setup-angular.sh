#!/usr/bin/env bash
# Acceso Angular local en Linux/macOS:
# - Sen opcións: prepara a chave do usuario (~/.ssh/dwcc_angular), copia a pública ao proxecto
#   e xestiona o bloque dwcc-angular de ~/.ssh/config con HostKeyAlias e UserKnownHostsFile propio.
# - --sync-host-key [--key "ssh-ed25519 ..."]: garda a chave pública do contedor frontend en
#   ~/.ssh/known_hosts.d/dwcc-angular para evitar bloqueos tras reinstalar o volume angular_claves.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SSH_DIR="${DAW_SSH_DIR:-$HOME/.ssh}"
MODE="prepare"
HOST_KEY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sync-host-key)
            MODE="sync-host-key"
            shift
            ;;
        --key)
            [[ $# -ge 2 ]] || { echo "Falta o valor de --key" >&2; exit 2; }
            HOST_KEY="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Opción descoñecida: $1 (usa --help)" >&2
            exit 2
            ;;
    esac
done

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [[ $MODE == sync-host-key ]]; then
    if [[ -z $HOST_KEY ]]; then
        HOST_KEY="$("$SCRIPT_DIR/daw.sh" frontend-host-key)"
    fi
    if [[ ! $HOST_KEY =~ ^(ssh-ed25519)[[:space:]]+([A-Za-z0-9+/=]+)([[:space:]].*)?$ ]]; then
        echo "Erro: formato non válido para a chave pública do servidor frontend." >&2
        exit 1
    fi
    KNOWN_DIR="$SSH_DIR/known_hosts.d"
    mkdir -p "$KNOWN_DIR"
    chmod 700 "$KNOWN_DIR"
    KNOWN_FILE="$KNOWN_DIR/dwcc-angular"
    TMP_FILE=$(mktemp "$KNOWN_DIR/.dwcc-angular.XXXXXX")
    trap 'rm -f -- "$TMP_FILE"' EXIT
    printf 'dwcc-angular %s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" > "$TMP_FILE"
    chmod 600 "$TMP_FILE"
    mv -f -- "$TMP_FILE" "$KNOWN_FILE"
    trap - EXIT
    exit 0
fi

KEY="$SSH_DIR/dwcc_angular"
if [[ ! -e "$KEY" ]]; then
    ssh-keygen -q -t ed25519 -N '' -C 'daw-dev Angular local' -f "$KEY"
fi
if [[ ! -s "$KEY.pub" ]]; then
    ssh-keygen -y -f "$KEY" > "$KEY.pub"
fi
mkdir -p "$PROJECT_DIR/docker/angular"
cp -- "$KEY.pub" "$PROJECT_DIR/docker/angular/ssh-key.pub"

python3 "$SCRIPT_DIR/daw_helpers.py" update-ssh-config "$SSH_DIR" "$KEY" "$PROJECT_DIR/.env"
