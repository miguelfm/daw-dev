#!/usr/bin/env bash
# Acceso Angular local en Linux; non substitúe chaves nin conexións existentes.
set -euo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
KEY="$HOME/.ssh/dwcc_angular"
if [[ ! -e "$KEY" ]]; then
    ssh-keygen -q -t ed25519 -N '' -C 'daw-dev Angular local' -f "$KEY"
fi
if [[ ! -s "$KEY.pub" ]]; then
    ssh-keygen -y -f "$KEY" > "$KEY.pub"
fi
cp -- "$KEY.pub" "$PROJECT_DIR/docker/angular/chave.pub"
python3 - "$HOME/.ssh/config" "$KEY" "$PROJECT_DIR/.env" <<'PY'
from pathlib import Path
import subprocess, sys
config, key, env = map(Path, sys.argv[1:])
port = '2222'
for line in (env.read_text().splitlines() if env.exists() else []):
    if line.startswith('ANGULAR_SSH_PORT='):
        port = line.partition('=')[2].strip().strip('\"\'').rsplit(':', 1)[-1]
if not port.isdigit():
    raise SystemExit('ANGULAR_SSH_PORT non válido')
resolved = subprocess.run(['ssh', '-G', 'dwcc-angular'], capture_output=True, text=True, check=True).stdout
if 'hostname dwcc-angular\n' in resolved:
    old = config.read_text() if config.exists() else ''
    block = f'Host dwcc-angular\n    HostName 127.0.0.1\n    Port {port}\n    User node\n    IdentityFile {key}\n    IdentitiesOnly yes\n'
    config.write_text(block + '\n' + old)
    config.chmod(0o600)
PY
