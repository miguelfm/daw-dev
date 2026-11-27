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

# Arranxos dun .env anterior, cunha copia do .env antes de cambialo. Outros valores consérvanse:
# - Un .env copiado do .env.example antes do 24-11-2026 leva o contrasinal por defecto anterior
#   de MariaDB; agora é abc123.., o da MV da aula.
# - Ata o 27-11-2026 a imaxe PHP era DAW_DEV_IMAGE=ghcr.io/miguelfm/dwcs-php; compose.yaml
#   xa non le esa variable, e a liña do .env.example retírase para non confundir.
migrar_env() {
    local env=$PROJECT_DIR/.env copia
    [[ -f $env && ! -L $env ]] || return 0
    if grep -qE '^DAW_DEV_IMAGE=' "$env" && ! grep -qxF 'DAW_DEV_IMAGE=ghcr.io/miguelfm/dwcs-php' "$env"; then
        echo 'Aviso: o .env ten DAW_DEV_IMAGE, que xa non se usa: indica a imaxe con DAW_PHP_IMAGE (sen a etiqueta).' >&2
    fi
    grep -qE '^DB_(ROOT_)?PASSWORD=abc123\.$|^DAW_DEV_IMAGE=ghcr\.io/miguelfm/dwcs-php$' "$env" || return 0
    copia="$env.daw-backup-$(date +%Y%m%d%H%M%S)-$$"
    cp -p "$env" "$copia"
    if grep -qE '^DB_(ROOT_)?PASSWORD=abc123\.$' "$env"; then
        sed -i -E 's/^(DB_(ROOT_)?PASSWORD)=abc123\.$/\1=abc123../' "$env"
        echo "O contrasinal de MariaDB do .env é agora abc123.. (copia do anterior en $copia)."
    fi
    if grep -qxF 'DAW_DEV_IMAGE=ghcr.io/miguelfm/dwcs-php' "$env"; then
        sed -i '/^DAW_DEV_IMAGE=ghcr\.io\/miguelfm\/dwcs-php$/d' "$env"
        echo "Retirouse do .env DAW_DEV_IMAGE, que xa non se usa (copia do anterior en $copia)."
    fi
}

# O contedor backend ten dúas definicións: a de Compose (daw-start) e a de Dev Containers, que
# engade o proxecto en ~/daw, Xdebug cara a localhost e a súa propia entrada. Dev Containers
# reutiliza sen recrealo calquera contedor backend que xa exista, e Compose recrea o de Dev Containers.
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

ids = [i for i in docker(*compose, "ps", "--all", "--quiet", "backend").split() if i]
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
    # Os ficheiros que o definiron, das etiquetas do propio contedor: valen igual co proxecto
    # do repositorio e coa aula (devcontainer.json en ~/html). O de /tmp xérao Dev Containers.
    created = nanoseconds(container["Created"])
    paths = [f for f in labels.get("com.docker.compose.project.config_files", "").split(",")
             if f and "/devcontainercli" not in f]
    paths += [labels.get("devcontainer.config_file", ""), os.path.join(project, ".env")]
    for path in dict.fromkeys(paths):
        if path and os.path.isfile(path) and os.stat(path).st_mtime_ns > created:
            name = os.path.relpath(path, project) if path.startswith(project + os.sep) else path
            reason = f"cambiou {name}"
            break
    if not reason:
        # Dev Containers constrúe a súa imaxe sobre a do proxecto: debe conter as súas capas.
        image = json.loads(docker(*compose, "config", "--format", "json"))["services"]["backend"].get("image")
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

# Ata o 27-11-2026 os servizos eran web, phpmyadmin, angular e doc-devdocs, cos contedores
# daw-*. Compose recoñece os contedores polo servizo: os anteriores quedarían órfos, quizais en
# marcha e cos portos ocupados. Retíranse; os datos están en volumes e no proxecto, non neles.
# OLD_RUNNING garda os servizos anteriores que estaban en marcha.
# Pares anterior:actual, sen táboas asociativas: o Bash 3.2 de macOS non as ten.
OLD_SERVICES='web:backend phpmyadmin:db-admin angular:frontend doc-devdocs:doc-web'
remove_old_services() {
    local project pair service ids
    OLD_RUNNING=
    project=$(docker compose "${COMPOSE_ARGS[@]}" config 2>/dev/null | sed -n 's/^name: //p' | head -n 1) || true
    [[ -n $project ]] || return 0
    for pair in $OLD_SERVICES; do
        service=${pair%%:*}
        ids=$(docker ps -aq --filter "label=com.docker.compose.project=$project" \
            --filter "label=com.docker.compose.service=$service" 2>/dev/null) || return 0
        [[ -n $ids ]] || continue
        if [[ -n $(docker ps -q --filter "label=com.docker.compose.project=$project" \
            --filter "label=com.docker.compose.service=$service" 2>/dev/null) ]]; then
            OLD_RUNNING+=" $service"
        fi
        echo "Retírase o contedor do servizo anterior $service: agora é ${pair#*:}."
        # shellcheck disable=SC2086
        docker rm -f $ids >/dev/null
    done
}

# Ata o 27-11-2026 as imaxes eran dwcs-php:8.6-ad e dwcc-angular:22. Sen Internet (nun exame),
# a anterior que xa estea no equipo pasa a levar o nome actual; despois retírase o nome
# anterior (docker image rm non borra unha imaxe que use un contedor).
OLD_IMAGES='ghcr.io/miguelfm/dwcs-php:8.6-ad=ghcr.io/miguelfm/daw-php:8.6 ghcr.io/miguelfm/dwcc-angular:22=ghcr.io/miguelfm/daw-angular:22'
rename_old_images() {
    local pair old new
    for pair in $OLD_IMAGES; do
        old=${pair%%=*} new=${pair#*=}
        docker image inspect "$old" >/dev/null 2>&1 || continue
        if ! docker image inspect "$new" >/dev/null 2>&1; then
            docker image tag "$old" "$new" || continue
            echo "A imaxe $old chámase agora $new."
        fi
        docker image rm "$old" >/dev/null 2>&1 || true
    done
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
Uso: daw-start | daw-start-all | daw-start-db | daw-start-frontend | daw-start-doc
     daw-stop | daw-stop-all | daw-stop-doc | daw-status | daw-logs | daw-shell | daw-web-root | daw-help

Comandos dispoñibles:
  daw-start      Arranca só o backend: PHP 8.6, Apache, Xdebug e acceso con daw-shell.
                 Os demais servizos arráncanse cos seus comandos específicos.
  daw-start-all  Arranca backend, db (MariaDB) e db-admin (phpMyAdmin).
  daw-start-db   Arranca a base de datos MariaDB e o backend xuntos.
  daw-start-frontend  Arranca o frontend (Angular) e prepara o acceso SSH dwcc-angular.
  daw-start-angular   Alias de daw-start-frontend.
  daw-start-doc  Arranca a documentación sen conexión: PHP (8080), web: HTML, HTTP e CSS (5042)
                 e Laravel (8088).
  daw-code       Abre o proxecto no perfil DWCS - PHP de VS Code.
  daw-web-root   Amosa a ruta da raíz web de Apache no sistema anfitrión.
  daw-stop       Para os contedores da contorna DAW Dev sen borrar datos.
  daw-stop-all   Para todos os contedores: backend, db, db-admin, frontend e documentación.
  daw-stop-doc   Para só os contedores da documentación sen conexión.
  daw-status     Mostra o estado e portos dos contedores da contorna.
  daw-logs       Mostra e segue as últimas liñas de logs dos contedores (Ctrl+C para saír).
  daw-shell      Abre Bash no backend (Apache e PHP) co usuario ad.
  daw-web-shell  Alias de daw-shell.
  daw-publicar   Publica o código e as solucións de DWCS na raíz web (www/U3/A4/code...).
  daw-help       Mostra esta axuda.

Tamén podes invocar:
  daw <start|start-all|start-db|start-frontend|start-doc|code|web-root|stop|stop-all|stop-doc|status|logs|shell|check|publicar|help> [argumentos...]

Os contedores levan o nome do servizo con -c: backend-c, db-c, db-admin-c, frontend-c,
doc-php-c, doc-web-c e doc-laravel-c (docker exec -it backend-c bash).
EOF
}

PROG_NAME="$(basename "$0")"
ACTION=""

case "$PROG_NAME" in
    daw-start|daw-star) ACTION="start" ;;
    daw-start-all)      ACTION="start-all" ;;
    daw-start-db)       ACTION="start-db" ;;
    daw-start-frontend|daw-start-angular) ACTION="start-frontend" ;;
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
[[ $ACTION != start-angular ]] || ACTION=start-frontend

case "$ACTION" in
    start|start-all|start-db|start-doc|start-frontend|migrar-env) migrar_env ;;
esac
case "$ACTION" in
    start|start-all|start-db|start-doc|start-frontend|remove-old-services) remove_old_services; rename_old_images ;;
esac

case "$ACTION" in
    start|start-db|start-all)
        if ! read_web_state; then
            echo 'Aviso: non se puido comprobar o backend (precisa Python 3); arráncase con Compose.' >&2
        fi
        if web_in_devcontainer; then
            # Apache segue servindo no Dev Container; Compose recrearíao e pecharía VS Code.
            echo 'backend-c está aberto en Dev Containers: segue en marcha así. Para usar a definición de daw-start, pecha antes a xanela de VS Code do contedor.'
        elif [[ $WEB_STATUS == running && $WEB_STALE != - ]]; then
            echo "Recréase backend-c: $WEB_STALE."
            docker compose "${COMPOSE_ARGS[@]}" up -d --wait --wait-timeout 300 --no-deps --force-recreate backend
        fi
        services=()
        case $ACTION in
            start) web_in_devcontainer || services=(--no-deps backend) ;;
            start-db) if web_in_devcontainer; then services=(db); else services=(db backend); fi ;;
            start-all) if web_in_devcontainer; then services=(db db-admin); fi ;;
        esac
        if ((${#services[@]})); then
            docker compose "${COMPOSE_ARGS[@]}" up -d --wait --wait-timeout 300 "${services[@]}" "$@"
        elif [[ $ACTION == start-all ]]; then
            docker compose "${COMPOSE_ARGS[@]}" up -d --wait --wait-timeout 300 "$@"
        fi
        ;;
    prepare-devcontainer)
        # initializeCommand de .devcontainer/devcontainer.json e daw-code -Container: Dev Containers
        # usa o contedor backend que atope, así que se retira o que non teña a súa definición actual.
        # www, a base de datos e os volumes non están no contedor: non se perde traballo.
        if ! wait_docker; then
            echo 'Aviso: Docker non responde; Dev Containers usará o contedor backend que atope.' >&2
            exit 0
        fi
        remove_old_services
        rename_old_images
        if ! read_web_state; then
            echo 'Aviso: non se puido comprobar o backend (precisa Python 3).' >&2
            exit 0
        fi
        reason=
        if [[ $WEB_MODE == compose ]]; then
            reason='creouno daw-start, sen o proxecto en ~/daw nin a configuración do Dev Container'
        elif [[ $WEB_MODE == devcontainer && $WEB_STALE != - ]]; then
            reason=$WEB_STALE
        fi
        if [[ -n $reason ]]; then
            echo "Retírase backend-c para que Dev Containers o cree de novo: $reason."
            docker rm -f "$WEB_ID" >/dev/null
        fi
        ;;
    restart-backend)
        # A activación da aula, despois de copiar os ficheiros do proxecto: recrea backend se
        # estaba en marcha (ou o web anterior), aínda que só cambiase un ficheiro montado.
        wait_docker || { echo 'Docker non responde.' >&2; exit 1; }
        remove_old_services
        rename_old_images >&2
        if docker compose "${COMPOSE_ARGS[@]}" ps --status running --services | grep -Fxq backend \
            || [[ " $OLD_RUNNING " == *" web "* ]]; then
            docker compose "${COMPOSE_ARGS[@]}" up -d --no-deps --force-recreate --wait --wait-timeout 300 backend >&2
            echo restarted
        fi
        ;;
    migrar-env|remove-old-services)
        # Para daw.ps1, que arranca os contedores desde Windows
        ;;
    stop|stop-all)
        if read_web_state 2>/dev/null && web_in_devcontainer; then
            echo 'backend-c está aberto en Dev Containers: a xanela de VS Code perderá a conexión («Cannot reconnect»). Ábrea de novo con Reopen in Container.'
        fi
        docker compose "${COMPOSE_ARGS[@]}" --profile frontend --profile doc stop "$@"
        ;;
    stop-doc)
        docker compose "${COMPOSE_ARGS[@]}" --profile doc stop doc-php doc-web doc-laravel "$@"
        ;;
    status)
        docker compose "${COMPOSE_ARGS[@]}" ps --all --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" "$@"
        ;;
    logs)
        docker compose "${COMPOSE_ARGS[@]}" --profile frontend --profile doc logs --tail 100 -f "$@"
        ;;
    start-doc)
        docker compose "${COMPOSE_ARGS[@]}" --profile doc up -d --wait --wait-timeout 300 \
            doc-php doc-web doc-laravel "$@"
        printf '%s\n' 'PHP:     http://localhost:8080/' 'Web:     http://localhost:5042/ (HTML, HTTP e CSS)' \
            'Laravel: http://localhost:8088/'
        ;;
    start-frontend)
        # daw.ps1 prepara a chave da conta de Windows e pasa DAW_SKIP_SSH_SETUP=1.
        [[ ${DAW_SKIP_SSH_SETUP:-} == 1 ]] || "$SCRIPT_DIR/setup-angular.sh"
        docker compose "${COMPOSE_ARGS[@]}" --profile frontend up -d --wait --wait-timeout 300 frontend "$@"
        printf '%s\n' 'Frontend (Angular) dispoñible: ssh dwcc-angular' 'VS Code: Remote-SSH → dwcc-angular → /home/node/proxectos' 'Aplicación: ng serve --host 0.0.0.0 → http://localhost:4200'
        ;;
    code)
        # Na aula, a contorna está en ~/.daw e o espazo de traballo de VS Code é o código web, ~/html.
        workspace=$PROJECT_DIR
        if [[ ${PROJECT_DIR##*/} == .daw && -d $PROJECT_DIR/../html/.devcontainer ]]; then
            workspace=$(cd "$PROJECT_DIR/../html" && pwd)
        fi
        code --new-window --profile 'DWCS - PHP' "$workspace" "$@"
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
    containers = docker(*compose, "ps", "--all", "--quiet", "backend").split()
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
        config = json.loads(docker(*compose, "config", "--format", "json", "backend"))
        sources = (mount["source"] for mount in config["services"]["backend"].get("volumes", [])
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
        docker compose "${COMPOSE_ARGS[@]}" exec -u ad backend bash "$@"
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
