#!/usr/bin/env bash
# Acceso Angular local en Linux/macOS:
# - Sen opcións: prepara a chave do usuario (~/.ssh/dwcc_angular), copia a pública ao proxecto
#   e xestiona o bloque dwcc-angular de ~/.ssh/config con HostKeyAlias e UserKnownHostsFile propio.
# - --sync-host-key [--key "ssh-ed25519 ..."]: garda a chave pública do contedor frontend en
#   ~/.ssh/known_hosts.d/dwcc-angular para evitar bloqueos tras reinstalar o volume angular_claves.
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
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
        HOST_KEY="$("$PROJECT_DIR/scripts/daw.sh" frontend-host-key)"
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

python3 - "$SSH_DIR" "$KEY" "$PROJECT_DIR/.env" <<'PY'
from pathlib import Path
import re, subprocess, sys

ssh_dir, key, env = map(Path, sys.argv[1:])
config = ssh_dir / 'config'
use_tilde = ssh_dir.resolve() == (Path.home() / '.ssh').resolve()

def ssh_path(path: Path, rel: str) -> str:
    value = f'~/.ssh/{rel}' if use_tilde else str(path)
    return f'"{value}"' if ' ' in value else value

port = '2222'
for line in (env.read_text(encoding='utf-8').splitlines() if env.exists() else []):
    stripped = line.strip()
    if stripped.startswith('ANGULAR_SSH_PORT='):
        port = stripped.partition('=')[2].strip().strip('"\'').rsplit(':', 1)[-1]
if not port.isdigit():
    raise SystemExit('ANGULAR_SSH_PORT non válido')

begin = '# >>> DAW DEV ANGULAR >>>'
end = '# <<< DAW DEV ANGULAR <<<'
block = (
    f'{begin}\n'
    f'Host dwcc-angular\n'
    f'    HostName 127.0.0.1\n'
    f'    Port {port}\n'
    f'    User node\n'
    f'    IdentityFile {ssh_path(key, "dwcc_angular")}\n'
    f'    IdentitiesOnly yes\n'
    f'    HostKeyAlias dwcc-angular\n'
    f'    UserKnownHostsFile {ssh_path(ssh_dir / "known_hosts.d" / "dwcc-angular", "known_hosts.d/dwcc-angular")}\n'
    f'{end}\n'
)

old = config.read_text(encoding='utf-8') if config.exists() else ''
marker_re = re.compile(re.escape(begin) + r'\r?\n.*?' + re.escape(end) + r'\r?\n?', re.S)

def is_legacy_daw_block(text: str) -> bool:
    opts = {}
    for line in text.splitlines()[1:]:
        s = line.strip()
        if not s or s.startswith('#'):
            continue
        parts = s.split(None, 1)
        if len(parts) == 2:
            opts[parts[0].lower()] = parts[1].strip().strip('"')
    return (
        opts.get('hostname') == '127.0.0.1'
        and opts.get('user') == 'node'
        and opts.get('identityfile', '').endswith('dwcc_angular')
    )

def replace_legacy_block(text: str):
    lines = text.splitlines(keepends=True)
    for i, line in enumerate(lines):
        if re.match(r'^\s*Host\s+dwcc-angular\s*$', line, re.I):
            j = i + 1
            while j < len(lines):
                s = lines[j].strip()
                if s and not s.startswith('#') and re.match(r'^(Host|Match)\s+', s, re.I):
                    break
                j += 1
            # Conserva liñas en branco ou comentarios finais que pertencen ao bloque seguinte
            end_idx = j
            while end_idx > i + 1 and (not lines[end_idx - 1].strip() or lines[end_idx - 1].lstrip().startswith('#')):
                end_idx -= 1
            section = ''.join(lines[i:end_idx])
            if is_legacy_daw_block(section):
                return ''.join(lines[:i]) + block + ''.join(lines[end_idx:]), True
            return text, False
    return None, False

if marker_re.search(old):
    new = marker_re.sub(lambda _: block, old, count=1)
else:
    upgraded, matched = replace_legacy_block(old)
    if upgraded is not None:
        new = upgraded
    else:
        # Se non hai entrada en config, comprobamos se vén dun Include (só co ~/.ssh real)
        skip = False
        if use_tilde:
            resolved = subprocess.run(['ssh', '-G', 'dwcc-angular'], capture_output=True, text=True, check=True).stdout
            skip = 'hostname dwcc-angular\n' not in resolved
        new = old if skip else (block + ('\n' if old and not old.startswith('\n') else '') + old)

if new != old or not config.exists():
    config.write_text(new, encoding='utf-8')
    config.chmod(0o600)
PY
