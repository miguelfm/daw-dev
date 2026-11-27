#!/usr/bin/env bash
# Xestión dos contedores DAW Dev (PHP + Apache + MariaDB + phpMyAdmin)
set -eo pipefail

# Resolver a ruta real do proxecto mesmo a través de ligazóns simbólicas
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
PROJECT_DIR="$( cd -P "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd )"
COMPOSE_FILE="$PROJECT_DIR/compose.yaml"

if [ ! -f "$COMPOSE_FILE" ]; then
    echo "Erro: non se atopou compose.yaml en $PROJECT_DIR" >&2
    exit 1
fi

COMPOSE_ARGS=(-f "$COMPOSE_FILE")
if [[ -f $PROJECT_DIR/compose.override.yaml ]]; then
    COMPOSE_ARGS+=(-f "$PROJECT_DIR/compose.override.yaml")
fi

# O contrasinal de MariaDB é abc123.., o da MV da aula. Un .env copiado do
# .env.example antes do 24-11-2026 leva o contrasinal por defecto anterior:
# cámbiase antes de arrancar, cunha copia do .env. Outros valores consérvanse.
migrar_env() {
    local env=$PROJECT_DIR/.env copia
    [[ -f $env && ! -L $env ]] || return 0
    grep -qE '^DB_(ROOT_)?PASSWORD=abc123\.$' "$env" || return 0
    copia="$env.daw-backup-$(date +%Y%m%d%H%M%S)-$$"
    cp -p "$env" "$copia"
    sed -i -E 's/^(DB_(ROOT_)?PASSWORD)=abc123\.$/\1=abc123../' "$env"
    echo "O contrasinal de MariaDB do .env é agora abc123.. (copia do anterior en $copia)."
}

# O contedor web ten dúas definicións: a de Compose (daw-start) e a de Dev Containers, que
# engade o proxecto en ~/daw, Xdebug cara a localhost e a súa propia entrada. Dev Containers reutiliza
# sen recrealo calquera contedor web que xa exista, e Compose recrea o de Dev Containers.
# web_state escribe «id modo estado motivo»: modo compose ou devcontainer, estado running ou
# stopped, e motivo «-» ou por que o contedor xa non corresponde aos ficheiros do proxecto.
# Sen contedor escribe «- none - -».
web_state() {
    python3 - "$PROJECT_DIR" "${COMPOSE_ARGS[@]}" <<'PY'
import json, os, subprocess, sys

project, compose = sys.argv[1], ("compose", "--project-directory", sys.argv[1], *sys.argv[2:])

def docker(*args):
    return subprocess.run(("docker", *args), check=True, stdout=subprocess.PIPE, encoding="utf-8").stdout

def nanoseconds(stamp):
    # Docker usa RFC 3339 en UTC con ata nove decimais, que datetime non le enteiro.
    from datetime import datetime, timezone
    stamp = stamp.rstrip("Z")
    whole, _, fraction = stamp.partition(".")
    seconds = datetime.fromisoformat(whole).replace(tzinfo=timezone.utc).timestamp()
    return int(seconds) * 10**9 + int((fraction + "000000000")[:9])

ids = [i for i in docker(*compose, "ps", "--all", "--quiet", "web").split() if i]
if not ids:
    print("- none - -")
    sys.exit()
container = json.loads(docker("inspect", "--type", "container", ids[0]))[0]
labels = container["Config"].get("Labels") or {}
mode = "devcontainer" if labels.get("devcontainer.local_folder") else "compose"
running = container["State"]["Running"]
reason = None
if mode == "devcontainer":
    # Compose comproba os seus cambios ao arrancar; Dev Containers, non.
    created = nanoseconds(container["Created"])
    for name in ("compose.yaml", "compose.override.yaml", ".env",
                 ".devcontainer/devcontainer.json", ".devcontainer/compose.devcontainer.yaml"):
        path = os.path.join(project, name)
        if os.path.isfile(path) and os.stat(path).st_mtime_ns > created:
            reason = f"cambiou {name}"
            break
    if not reason:
        # Dev Containers constrúe a súa imaxe sobre a do proxecto: debe conter as súas capas.
        image = json.loads(docker(*compose, "config", "--format", "json"))["services"]["web"].get("image")
        if image:
            try:
                base = json.loads(docker("image", "inspect", image))[0]["RootFS"]["Layers"]
            except subprocess.CalledProcessError:
                base = None
            used = json.loads(docker("image", "inspect", container["Image"]))[0]["RootFS"]["Layers"]
            if base and used[:len(base)] != base:
                reason = f"hai unha imaxe nova {image}"
if running and not reason:
    # Docker monta un ficheiro polo seu inodo: se git ou a copia da aula o substitúen, o
    # contedor en marcha segue co anterior ata que se volve arrancar.
    started = nanoseconds(container["State"]["StartedAt"])
    for mount in container.get("Mounts") or []:
        source = mount.get("Source", "")
        if mount.get("Type") == "bind" and os.path.isfile(source) and os.stat(source).st_mtime_ns > started:
            reason = f"cambiou {os.path.relpath(source, project) if source.startswith(project + os.sep) else source}"
            break
print(container["Id"][:12], mode, "running" if running else "stopped", reason or "-")
PY
}

read_web_state() {
    WEB_ID=- WEB_MODE=unknown WEB_STATUS=unknown WEB_STALE=-
    command -v python3 >/dev/null || return 1
    local state
    state=$(web_state) || return 1
    read -r WEB_ID WEB_MODE WEB_STATUS WEB_STALE <<< "$state"
}

# Compose recrearía o contedor dun Dev Container aberto e pecharía a sesión de VS Code.
web_in_devcontainer() {
    [[ $WEB_MODE == devcontainer && $WEB_STATUS == running ]]
}

wait_docker() {
    local i
    for ((i = 0; i < 30; i++)); do
        docker info >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

show_help() {
    cat << 'EOF'
Uso: daw-start | daw-start-all | daw-start-db | daw-start-angular | daw-start-doc
     daw-stop | daw-stop-all | daw-stop-doc | daw-status | daw-logs | daw-web-shell | daw-web-root | daw-help

Comandos dispoñibles:
  daw-start      Arranca só daw-web: PHP 8.6, Apache, Xdebug e acceso con daw-shell.
                 Os demais servizos arráncanse cos seus comandos específicos.
  daw-start-all  Arranca a contorna completa (web, db e phpmyadmin).
  daw-start-db   Arranca a base de datos MariaDB e o servizo web xuntos.
  daw-start-angular  Arranca Angular e prepara o acceso SSH dwcc-angular.
  daw-start-doc  Arranca a documentación sen conexión: manual de PHP (8080),
                 referencia de MDN (5042) e Laravel (8088).
  daw-code       Abre o proxecto no perfil DWCS - PHP de VS Code.
  daw-web-root   Amosa a ruta da raíz web de Apache no sistema anfitrión.
  daw-stop       Para os contedores da contorna DAW Dev sen borrar datos.
  daw-stop-all   Para todos os contedores: desenvolvemento, documentación e Angular.
  daw-stop-doc   Para só os contedores da documentación sen conexión.
  daw-status     Mostra o estado e portos dos contedores da contorna.
  daw-logs       Mostra e segue as últimas liñas de logs dos contedores (Ctrl+C para saír).
  daw-web-shell  Abre Bash no contedor de Apache e PHP co usuario ad.
  daw-shell      Alias de daw-web-shell.
  daw-publicar   Sincroniza o código e as solucións de DWCS cara a daw-dev/www/dwcs.
  daw-help       Mostra esta axuda.

Tamén podes invocar:
  daw <start|start-all|start-db|start-angular|start-doc|code|web-root|stop|stop-all|stop-doc|status|logs|web-shell|check|publicar|help> [argumentos...]
EOF
}

PROG_NAME="$(basename "$0")"
ACTION=""

case "$PROG_NAME" in
    daw-start|daw-star) ACTION="start" ;;
    daw-start-all)      ACTION="start-all" ;;
    daw-start-db)       ACTION="start-db" ;;
    daw-start-angular)  ACTION="start-angular" ;;
    daw-start-doc)      ACTION="start-doc" ;;
    daw-code)           ACTION="code" ;;
    daw-web-root)       ACTION="web-root" ;;
    daw-stop)           ACTION="stop" ;;
    daw-stop-all)       ACTION="stop-all" ;;
    daw-stop-doc)       ACTION="stop-doc" ;;
    daw-status)         ACTION="status" ;;
    daw-logs)           ACTION="logs" ;;
    daw-web-shell|daw-shell|daw-bash) ACTION="web-shell" ;;
    daw-publicar)       ACTION="publicar" ;;
    daw-help)           ACTION="help" ;;
    daw|daw.sh)
        ACTION="${1:-help}"
        shift || true
        ;;
    *)
        ACTION="${1:-help}"
        shift || true
        ;;
esac

case "$ACTION" in
    start|start-all|start-db|start-doc|start-angular|migrar-env) migrar_env ;;
esac

case "$ACTION" in
    start|start-db|start-all)
        if ! read_web_state; then
            echo 'Aviso: non se puido comprobar o contedor web (precisa Python 3); arráncase con Compose.' >&2
        fi
        if web_in_devcontainer; then
            # Apache segue servindo no Dev Container; Compose recrearíao e pecharía VS Code.
            echo 'daw-web está aberto en Dev Containers: segue en marcha así. Para usar a definición de daw-start, pecha antes a xanela de VS Code do contedor.'
        elif [[ $WEB_STATUS == running && $WEB_STALE != - ]]; then
            echo "Recréase daw-web: $WEB_STALE."
            docker compose "${COMPOSE_ARGS[@]}" up -d --wait --wait-timeout 300 --no-deps --force-recreate web
        fi
        services=()
        case $ACTION in
            start) web_in_devcontainer || services=(--no-deps web) ;;
            start-db) if web_in_devcontainer; then services=(db); else services=(db web); fi ;;
            start-all) if web_in_devcontainer; then services=(db phpmyadmin); fi ;;
        esac
        if ((${#services[@]})); then
            docker compose "${COMPOSE_ARGS[@]}" up -d --wait --wait-timeout 300 "${services[@]}" "$@"
        elif [[ $ACTION == start-all ]]; then
            docker compose "${COMPOSE_ARGS[@]}" up -d --wait --wait-timeout 300 "$@"
        fi
        ;;
    prepare-devcontainer)
        # initializeCommand de .devcontainer/devcontainer.json e daw-code -Container: Dev Containers
        # usa o contedor web que atope, así que se retira o que non teña a súa definición actual.
        # www, a base de datos e os volumes non están no contedor: non se perde traballo.
        if ! wait_docker; then
            echo 'Aviso: Docker non responde; Dev Containers usará o contedor web que atope.' >&2
            exit 0
        fi
        if ! read_web_state; then
            echo 'Aviso: non se puido comprobar o contedor web (precisa Python 3).' >&2
            exit 0
        fi
        reason=
        if [[ $WEB_MODE == compose ]]; then
            reason='creouno daw-start, sen o proxecto en ~/daw nin a configuración do Dev Container'
        elif [[ $WEB_MODE == devcontainer && $WEB_STALE != - ]]; then
            reason=$WEB_STALE
        fi
        if [[ -n $reason ]]; then
            echo "Retírase daw-web para que Dev Containers o cree de novo: $reason."
            docker rm -f "$WEB_ID" >/dev/null
        fi
        ;;
    migrar-env)
        # Para daw.ps1, que arranca os contedores desde Windows
        ;;
    stop|stop-all)
        docker compose "${COMPOSE_ARGS[@]}" --profile angular --profile doc stop "$@"
        ;;
    stop-doc)
        docker compose "${COMPOSE_ARGS[@]}" --profile doc stop doc-php doc-devdocs doc-laravel "$@"
        ;;
    status)
        docker compose "${COMPOSE_ARGS[@]}" ps --all --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" "$@"
        ;;
    logs)
        docker compose "${COMPOSE_ARGS[@]}" --profile angular --profile doc logs --tail 100 -f "$@"
        ;;
    start-doc)
        docker compose "${COMPOSE_ARGS[@]}" --profile doc up -d --wait --wait-timeout 300 \
            doc-php doc-devdocs doc-laravel "$@"
        printf '%s\n' 'Manual de PHP: http://localhost:8080/' 'MDN:           http://localhost:5042/' \
            'Laravel:       http://localhost:8088/'
        ;;
    start-angular)
        "$SCRIPT_DIR/setup-angular.sh"
        docker compose "${COMPOSE_ARGS[@]}" --profile angular up -d --wait --wait-timeout 300 angular "$@"
        printf '%s\n' 'Angular dispoñible: ssh dwcc-angular' 'VS Code: Remote-SSH → dwcc-angular → /home/node/proxectos' 'Aplicación: ng serve --host 0.0.0.0 → http://localhost:4200'
        ;;
    code)
        code --new-window --profile 'DWCS - PHP' "$PROJECT_DIR" "$@"
        ;;
    web-root)
        if ! command -v python3 >/dev/null; then
            echo 'Erro: daw-web-root require Python 3.' >&2
            exit 1
        fi
        python3 - "$PROJECT_DIR" "${COMPOSE_ARGS[@]}" <<'PY'
import json
import os
import subprocess
import sys

web_roots = {"/var/www/html"}
compose = ("compose", "--project-directory", *sys.argv[1:])


def docker(*args):
    return subprocess.run(("docker", *args), check=True, stdout=subprocess.PIPE, encoding="utf-8").stdout


def native_path(source):
    if sys.platform == "darwin" and not os.path.isdir(source):
        for prefix in ("/host_mnt", "/run/desktop/mnt/host"):
            if source.startswith(prefix + "/"):
                return source[len(prefix):]
    return source


try:
    containers = docker(*compose, "ps", "--all", "--quiet", "web").split()
    mounts = []
    if containers:
        # As instancias de docker compose run poden ter montaxes propias.
        template = '{{if ne (index .Config.Labels "com.docker.compose.oneoff") "True"}}{{json .Mounts}}{{end}}'
        inspected = docker("inspect", "--type", "container", "--format", template, *containers)
        mounts = [json.loads(line) for line in inspected.splitlines() if line]

    if mounts:
        sources = (mount["Source"] for container in mounts for mount in container
                   if mount["Type"] == "bind" and mount["Destination"] in web_roots)
    else:
        config = json.loads(docker(*compose, "config", "--format", "json", "web"))
        sources = (mount["source"] for mount in config["services"]["web"].get("volumes", [])
                   if mount["type"] == "bind" and mount["target"] in web_roots)
except subprocess.CalledProcessError as error:
    sys.exit(error.returncode)

paths = dict.fromkeys(native_path(source) for source in sources)
if not paths:
    sys.exit("Erro: a raíz web non está montada desde un cartafol do anfitrión.")
print(*paths, sep="\n")
PY
        ;;
    web-shell|shell|bash)
        docker compose "${COMPOSE_ARGS[@]}" exec -u ad web bash "$@"
        ;;
    check|comprobar)
        "$PROJECT_DIR/scripts/check.sh" "$@"
        ;;
    publicar)
        if command -v publicar-daw-dev >/dev/null 2>&1; then
            publicar-daw-dev "$@"
        elif [ -x "$PROJECT_DIR/../docencia/scripts/publicar-daw-dev.sh" ]; then
            "$PROJECT_DIR/../docencia/scripts/publicar-daw-dev.sh" "$@"
        else
            echo "Erro: non se atopou o script publicar-daw-dev.sh" >&2
            exit 1
        fi
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Comando descoñecido: $ACTION" >&2
        echo "Usa: daw-help (ou daw help) para ver os comandos dispoñibles." >&2
        exit 2
        ;;
esac
