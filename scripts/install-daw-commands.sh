#!/usr/bin/env bash
# Instala ou desinstala os lanzadores daw-* en Linux/macOS desde a lista única de scripts/daw.sh.
#
# Uso:
#   ./scripts/install-daw-commands.sh [--bin-dir DIR] [--no-shell-config]
#   ./scripts/install-daw-commands.sh --uninstall [--bin-dir DIR] [--no-shell-config]
#
# Non substitúe ficheiros normais existentes nin un publicador persoal (daw-publicar).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DAW_SH="$SCRIPT_DIR/daw.sh"
BIN_DIR="${DAW_BIN_DIR:-$HOME/.local/bin}"
UNINSTALL=0
UPDATE_SHELL=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --uninstall)
            UNINSTALL=1
            shift
            ;;
        --bin-dir)
            [[ $# -ge 2 ]] || { echo "Falta o argumento de --bin-dir" >&2; exit 2; }
            BIN_DIR="$2"
            shift 2
            ;;
        --no-shell-config)
            UPDATE_SHELL=0
            shift
            ;;
        -h|--help)
            sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Opción descoñecida: $1 (usa --help)" >&2
            exit 2
            ;;
    esac
done

update_shell_configs() {
    local mode=$1
    shift
    python3 - "$mode" "$BIN_DIR" "$@" <<'CONFIG'
from pathlib import Path
import re, sys

mode = sys.argv[1]
bin_dir = sys.argv[2]
names = [n for n in sys.argv[3:] if n.startswith('daw-')]
home = Path.home()
begin = '# >>> DAW DEV LINUX >>>'
end = '# <<< DAW DEV LINUX <<<'
block_re = re.compile(r'\n*' + re.escape(begin) + r'.*?' + re.escape(end) + r'\n?', re.S)
path_expr = '$HOME/.local/bin' if Path(bin_dir).resolve() == (home / '.local' / 'bin').resolve() else bin_dir

for rc_name in ('.bashrc', '.zshrc'):
    p = home / rc_name
    if not p.exists():
        continue
    s = p.read_text(encoding='utf-8')
    if mode == 'install':
        if names:
            s = re.sub(r'^alias (?:' + '|'.join(map(re.escape, names)) + r')=.*\n?', '', s, flags=re.M)
        s = block_re.sub('\n', s).rstrip()
        block = (
            f'{begin}\n'
            f'export PATH="{path_expr}:$PATH"\n'
            f'unalias {" ".join(names)} 2>/dev/null || true\n'
            f'{end}\n'
        )
        p.write_text((s + '\n\n' if s else '') + block, encoding='utf-8')
    else:
        if begin in s:
            cleaned = block_re.sub('\n', s).rstrip()
            p.write_text((cleaned + '\n') if cleaned else '', encoding='utf-8')

fish_dir = home / '.config/fish'
fish_file = fish_dir / 'conf.d/my_aliases.fish'
if mode == 'install' and fish_dir.exists():
    fish_file.parent.mkdir(parents=True, exist_ok=True)
    s = fish_file.read_text(encoding='utf-8') if fish_file.exists() else ''
    if names:
        s = re.sub(r'^alias (?:' + '|'.join(map(re.escape, names)) + r') .*\n?', '', s, flags=re.M)
    s = block_re.sub('\n', s).rstrip()
    block = (
        f'{begin}\n'
        f'fish_add_path "{path_expr}"\n'
        f'functions -e {" ".join(names)}\n'
        f'{end}\n'
    )
    fish_file.write_text((s + '\n\n' if s else '') + block, encoding='utf-8')
elif mode == 'uninstall' and fish_file.exists():
    s = fish_file.read_text(encoding='utf-8')
    if begin in s:
        cleaned = block_re.sub('\n', s).rstrip()
        fish_file.write_text((cleaned + '\n') if cleaned else '', encoding='utf-8')
CONFIG
}

if [[ $UNINSTALL -eq 1 ]]; then
    removed=0
    if [[ -d $BIN_DIR ]]; then
        daw_real=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$DAW_SH")
        while IFS= read -r target; do
            [[ -n $target && -L $target ]] || continue
            target_real=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$target")
            if [[ $target_real == "$daw_real" ]]; then
                rm -f -- "$target"
                removed=$((removed + 1))
            fi
        done < <(find "$BIN_DIR" -maxdepth 1 -type l \( -name 'daw' -o -name 'daw-*' \) | sort)
    fi
    if [[ $UPDATE_SHELL -eq 1 ]]; then
        update_shell_configs uninstall
    fi
    printf 'Retiráronse %d lanzadores DAW Dev de %s\n' "$removed" "$BIN_DIR"
    exit 0
fi

chmod +x "$DAW_SH" "$SCRIPT_DIR/setup-angular.sh"
[[ -f "$SCRIPT_DIR/check.sh" ]] && chmod +x "$SCRIPT_DIR/check.sh"
[[ -f "$SCRIPT_DIR/install-linux.sh" ]] && chmod +x "$SCRIPT_DIR/install-linux.sh"

COMMANDS=()
while IFS= read -r cmd; do
    [[ -n $cmd ]] || continue
    COMMANDS+=("$cmd")
done < <("$DAW_SH" --list-commands)

if [[ ${#COMMANDS[@]} -eq 0 ]]; then
    echo "Erro: daw.sh --list-commands non devolveu ningún comando." >&2
    exit 1
fi

daw_real=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$DAW_SH")
CONFLICTS=()
TO_INSTALL=()
SHELL_NAMES=()
PRESERVED_PUBLICAR=0

# Comprobación previa de todos os destinos antes de modificar nada.
for cmd in "${COMMANDS[@]}"; do
    target="$BIN_DIR/$cmd"
    if [[ $cmd == daw-publicar && ( -e "$target" || -L "$target" ) ]]; then
        if [[ ! -L "$target" ]]; then
            PRESERVED_PUBLICAR=1
            continue
        fi
        target_real=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$target")
        if [[ $target_real != "$daw_real" ]]; then
            PRESERVED_PUBLICAR=1
            continue
        fi
    elif [[ -e "$target" && ! -L "$target" ]]; then
        CONFLICTS+=("$target")
        continue
    fi
    TO_INSTALL+=("$cmd")
    [[ $cmd == daw-* ]] && SHELL_NAMES+=("$cmd")
done

if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
    for path in "${CONFLICTS[@]}"; do
        printf 'Non se substitúe o ficheiro existente: %s\n' "$path" >&2
    done
    exit 1
fi

mkdir -p "$BIN_DIR"
for cmd in "${TO_INSTALL[@]}"; do
    ln -sfn "$DAW_SH" "$BIN_DIR/$cmd"
done

if [[ $UPDATE_SHELL -eq 1 ]]; then
    update_shell_configs install "${SHELL_NAMES[@]}"
fi

if [[ $PRESERVED_PUBLICAR -eq 1 ]]; then
    printf 'Conservouse o publicador persoal existente: %s/daw-publicar\n' "$BIN_DIR"
fi
printf 'Comandos DAW Dev instalados en %s (%d lanzadores)\n' "$BIN_DIR" "${#TO_INSTALL[@]}"
