#!/usr/bin/env bash
# Instala en Debian o VS Code Server do mesmo commit que o VS Code de Windows, desde un
# .tar.gz xa descargado. Así VS Code non ten que descargalo desde Debian ao conectar por WSL.
#   vscode-server.sh comprobar COMMIT          0 se está instalado; 3 se falta
#   vscode-server.sh instalar COMMIT ARQUIVO   0 se queda instalado; 1 se o paquete non serve
set -euo pipefail

accion=${1:-}
commit=${2:-}
[[ $commit =~ ^[[:xdigit:]]{40}$ ]] || { echo 'Non se recoñece a versión (commit) de VS Code.' >&2; exit 1; }
commit=${commit,,}
# e_machine do executable node (bytes 18-19 do ELF): o paquete debe ser desta arquitectura.
case "$(uname -m)" in
    x86_64) elf=3e00 ;;
    aarch64) elf=b700 ;;
    *) echo 'VS Code Server só se instala aquí en Debian x64 ou ARM64.' >&2; exit 1 ;;
esac
bin="$HOME/.vscode-server/bin"
destino="$bin/$commit"

instalado() {
    [[ -x "$1/node" && -x "$1/bin/code-server" ]] &&
        grep -Eq "\"commit\"[[:space:]]*:[[:space:]]*\"$commit\"" "$1/product.json" 2>/dev/null &&
        [[ $(od -An -tx1 -j18 -N2 "$1/node" | tr -d '[:space:]') == "$elf" ]]
}

case "$accion" in
    comprobar)
        if instalado "$destino"; then exit 0; fi
        exit 3
        ;;
    instalar)
        arquivo=${3:-}
        if instalado "$destino"; then exit 0; fi
        [[ -f $arquivo ]] || { echo "Non existe $arquivo." >&2; exit 1; }
        mkdir -p -- "$bin"
        # Dous daw-code-angular á vez non instalan o mesmo servidor dúas veces.
        exec 9>"$bin/.daw-$commit.lock"
        flock 9
        if instalado "$destino"; then exit 0; fi
        echo "Comprobando $arquivo..."
        temporal=$(mktemp -d "$bin/.daw-servidor.XXXXXX")
        trap 'rm -rf -- "$temporal" "$temporal.anterior"' EXIT
        # Extrae como o usuario de Debian e publica só despois de validar o contido.
        if ! tar -xzf "$arquivo" --strip-components=1 --no-same-owner --no-same-permissions -C "$temporal"; then
            echo 'Non se puido extraer o paquete: comproba a descarga e o espazo libre en Debian.' >&2
            exit 1
        fi
        if ! instalado "$temporal"; then
            echo 'O paquete non corresponde á versión ou á arquitectura do VS Code deste equipo.' >&2
            exit 1
        fi
        if [[ -e $destino || -L $destino ]]; then mv -T -- "$destino" "$temporal.anterior"; fi
        mv -T -- "$temporal" "$destino"
        echo 'VS Code Server instalado en Debian.'
        ;;
    *)
        echo 'Uso: vscode-server.sh comprobar COMMIT | instalar COMMIT ARQUIVO' >&2
        exit 2
        ;;
esac
