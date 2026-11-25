#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
launcher="$script_dir/daw.sh"
bin_dir="$HOME/.local/bin"
commands=(
    daw-start daw-start-db daw-start-all daw-start-angular daw-stop
    daw-status daw-logs daw-code daw-code-angular daw-code-proxecto daw-help
)

for command_name in "${commands[@]}"; do
    link="$bin_dir/$command_name"
    if [[ -e "$link" || -L "$link" ]]; then
        if [[ ! -L "$link" || "$(readlink -- "$link")" != "$launcher" ]]; then
            printf 'Xa existe %s. Resolve ese conflito antes de instalar.\n' "$link" >&2
            exit 1
        fi
    fi
done

mkdir -p -- "$bin_dir"
chmod u+x -- "$launcher"
for command_name in "${commands[@]}"; do
    link="$bin_dir/$command_name"
    [[ -L "$link" ]] || ln -s -- "$launcher" "$link"
done

printf 'Ordes DAW Dev instaladas en %s.\n' "$bin_dir"
printf '%s\n' 'Se o cartafol aínda non está no PATH, executa:' \
    'export PATH="$HOME/.local/bin:$PATH"'
