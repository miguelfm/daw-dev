#!/usr/bin/env bash
# Instala os lanzadores Linux sen substituír o publicador persoal.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
chmod +x "$SCRIPT_DIR/daw.sh" "$SCRIPT_DIR/setup-angular.sh"
for cmd in daw daw-start daw-star daw-start-all daw-start-db daw-start-frontend daw-start-angular daw-start-doc daw-code daw-web-root daw-stop daw-stop-all daw-stop-doc daw-status daw-logs daw-web-shell daw-shell daw-help; do
    target="$BIN_DIR/$cmd"
    if [[ -e "$target" && ! -L "$target" ]]; then
        printf 'Non se substitúe o ficheiro existente: %s\n' "$target" >&2
        exit 1
    fi
    ln -sfn "$SCRIPT_DIR/daw.sh" "$target"
done
python3 - <<'CONFIG'
from pathlib import Path
import re
home = Path.home()
names = 'daw-start daw-start-all daw-start-db daw-start-frontend daw-start-angular daw-start-doc daw-code daw-web-root daw-stop daw-stop-all daw-stop-doc daw-status daw-logs daw-web-shell daw-shell daw-help'.split()
for name in ['.bashrc', '.zshrc']:
    p = home / name
    if not p.exists():
        continue
    s = p.read_text()
    s = re.sub(r'^alias (?:' + '|'.join(map(re.escape, names)) + r')=.*\n?', '', s, flags=re.M)
    begin = '# >>> DAW DEV LINUX >>>'
    end = '# <<< DAW DEV LINUX <<<'
    s = re.sub(re.escape(begin) + r'.*?' + re.escape(end) + r'\n?', '', s, flags=re.S)
    block = begin + '\nexport PATH="$HOME/.local/bin:$PATH"\nunalias ' + ' '.join(names) + ' 2>/dev/null || true\n' + end + '\n'
    p.write_text(s.rstrip() + '\n\n' + block)
p = home / '.config/fish/conf.d/my_aliases.fish'
if (home / '.config/fish').exists():
    p.parent.mkdir(parents=True, exist_ok=True)
    s = p.read_text() if p.exists() else ''
    s = re.sub(r'^alias (?:' + '|'.join(map(re.escape, names)) + r') .*\n?', '', s, flags=re.M)
    marker = '# >>> DAW DEV LINUX >>>'
    s = re.sub(re.escape(marker) + r'.*?# <<< DAW DEV LINUX <<<\n?', '', s, flags=re.S)
    s = s.rstrip() + '\n\n' + marker + '\nfish_add_path "$HOME/.local/bin"\nfunctions -e ' + ' '.join(names) + '\n# <<< DAW DEV LINUX <<<\n'
    p.write_text(s)
CONFIG
printf 'Comandos DAW Dev instalados en %s\n' "$BIN_DIR"
