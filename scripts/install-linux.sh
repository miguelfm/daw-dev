#!/usr/bin/env bash
# Configura unha instalación local en Linux reproducindo a disposición da aula:
# - código web en ~/html (coa configuración de Dev Container e VS Code xerada desde overlay/)
# - datos das tarefas fóra da raíz web en ~/data
# - .env e compose.override.yaml na raíz do proxecto (ignorados en git)
# - lanzadores daw-* en ~/.local/bin
#
# Uso:
#   ./scripts/install-linux.sh [--html-dir DIR] [--data-dir DIR] [--no-commands] [--force]
#
# Seguro para repetir: non sobrescribe o código de ~/html, os datos de ~/data nin un .env existente.
# --force rexenera só os ficheiros de configuración derivados (compose.override.yaml, .devcontainer e .vscode).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
OVERLAY_DIR="$PROJECT_DIR/windows/classroom/overlay"

HTML_DIR="$HOME/html"
DATA_DIR="$HOME/data"
INSTALL_COMMANDS=1
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --html-dir)
            [[ $# -ge 2 ]] || { echo "Falta o argumento de --html-dir" >&2; exit 2; }
            HTML_DIR="$2"
            shift 2
            ;;
        --data-dir)
            [[ $# -ge 2 ]] || { echo "Falta o argumento de --data-dir" >&2; exit 2; }
            DATA_DIR="$2"
            shift 2
            ;;
        --no-commands)
            INSTALL_COMMANDS=0
            shift
            ;;
        --force)
            FORCE=1
            shift
            ;;
        -h|--help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Opción descoñecida: $1 (usa --help)" >&2
            exit 2
            ;;
    esac
done

[[ -d $OVERLAY_DIR ]] || { echo "Erro: falta o directorio de referencia $OVERLAY_DIR" >&2; exit 1; }

mkdir -p "$HTML_DIR" "$DATA_DIR" "$HTML_DIR/.devcontainer" "$HTML_DIR/.vscode"
HTML_DIR="$(cd -- "$HTML_DIR" && pwd)"
DATA_DIR="$(cd -- "$DATA_DIR" && pwd)"

copy_if_missing() {
    local src=$1 dst=$2
    if [[ ! -e $dst ]]; then
        cp -- "$src" "$dst"
        printf 'Creado: %s\n' "$dst"
    fi
}

copy_config() {
    local src=$1 dst=$2
    if [[ ! -e $dst || $FORCE -eq 1 ]]; then
        cp -- "$src" "$dst"
        printf 'Actualizado: %s\n' "$dst"
    fi
}

# Ficheiros iniciais (só se faltan: nunca sobrescribe traballo do usuario)
copy_if_missing "$PROJECT_DIR/www/index.php" "$HTML_DIR/index.php"
copy_if_missing "$PROJECT_DIR/www/info.php" "$HTML_DIR/info.php"
copy_if_missing "$OVERLAY_DIR/data/README.txt" "$DATA_DIR/README.txt"

# .env local (creado só se non existe)
ENV_FILE="$PROJECT_DIR/.env"
if [[ ! -e $ENV_FILE ]]; then
    umask_old=$(umask)
    umask 077
    {
        printf 'WWW_DIR=%s\n' "$HTML_DIR"
        printf 'USER_UID=%s\n' "$(id -u)"
        printf 'USER_GID=%s\n' "$(id -g)"
        printf 'WEB_PORT=127.0.0.1:80\n'
        printf 'DB_PORT=127.0.0.1:3306\n'
        printf 'PMA_PORT=127.0.0.1:8081\n'
    } > "$ENV_FILE"
    umask "$umask_old"
    printf 'Creado: %s\n' "$ENV_FILE"
else
    current_www=$(sed -n 's/^WWW_DIR=//p' "$ENV_FILE" | tail -n 1 | tr -d "\"'")
    if [[ -n $current_www && $current_www != "$HTML_DIR" ]]; then
        printf 'Aviso: %s xa define WWW_DIR=%s (distinto de %s); consérvase sen cambios.\n' \
            "$ENV_FILE" "$current_www" "$HTML_DIR" >&2
    fi
fi

# compose.override.yaml e ~/html/.devcontainer/devcontainer.json derivados do overlay
python3 - "$PROJECT_DIR" "$OVERLAY_DIR" "$HTML_DIR" "$DATA_DIR" "$FORCE" <<'PY'
from pathlib import Path
import json, os, sys

project, overlay, html_dir, data_dir = map(Path, sys.argv[1:5])
force = sys.argv[5] == '1'

override_path = project / 'compose.override.yaml'
if not override_path.exists() or force:
    data_yaml = json.dumps(str(data_dir))
    override_text = (
        '# Instalación local: dúas rutas ao mesmo código e datos fóra da raíz web.\n'
        'services:\n'
        '  backend:\n'
        '    volumes:\n'
        '      - type: bind\n'
        '        source: ${WWW_DIR:-./www}\n'
        '        target: /home/ad/html\n'
        '      - type: bind\n'
        f'        source: {data_yaml}\n'
        '        target: /home/ad/data\n'
    )
    override_path.write_text(override_text, encoding='utf-8')
    print(f'Actualizado: {override_path}')

dev_target = html_dir / '.devcontainer' / 'devcontainer.json'
if not dev_target.exists() or force:
    template = (overlay / 'html' / '.devcontainer' / 'devcontainer.json').read_text(encoding='utf-8')
    # Se a contorna está en ~/.daw ao lado de ~/html, consérvanse as rutas relativas; se non, úsase a ruta real.
    default_env = (html_dir.parent / '.daw').resolve()
    if project.resolve() == default_env:
        rendered = template
    else:
        proj_str = str(project.resolve())
        rendered = template.replace(
            '["../../.daw/compose.yaml", "../../.daw/compose.override.yaml", "compose.devcontainer.yaml"]',
            json.dumps([f'{proj_str}/compose.yaml', f'{proj_str}/compose.override.yaml', 'compose.devcontainer.yaml']),
        ).replace(
            '"bash \\"${localWorkspaceFolder}/../.daw/scripts/daw.sh\\" prepare-devcontainer || exit 0"',
            json.dumps(f'bash "{proj_str}/scripts/daw.sh" prepare-devcontainer || exit 0'),
        )
    dev_target.write_text(rendered, encoding='utf-8')
    print(f'Actualizado: {dev_target}')
PY

copy_config "$OVERLAY_DIR/html/.devcontainer/compose.devcontainer.yaml" "$HTML_DIR/.devcontainer/compose.devcontainer.yaml"
copy_config "$OVERLAY_DIR/html/.vscode/launch.json" "$HTML_DIR/.vscode/launch.json"
copy_config "$PROJECT_DIR/.vscode/settings.json" "$HTML_DIR/.vscode/settings.json"

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    docker compose -f "$PROJECT_DIR/compose.yaml" -f "$PROJECT_DIR/compose.override.yaml" config --quiet
fi

if [[ $INSTALL_COMMANDS -eq 1 ]]; then
    bash "$SCRIPT_DIR/install-daw-commands.sh"
fi

printf '\nInstalación local preparada:\n'
printf '  Contorna:   %s\n' "$PROJECT_DIR"
printf '  Código web: %s\n' "$HTML_DIR"
printf '  Datos:      %s\n' "$DATA_DIR"
printf 'Comproba a contorna con: %s/scripts/check.sh\n' "$PROJECT_DIR"
