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

show_help() {
    cat << 'EOF'
Uso: daw-start | daw-start-all | daw-start-db | daw-start-angular
     daw-stop | daw-status | daw-logs | daw-shell | daw-help

Comandos dispoñibles:
  daw-start      Arranca só daw-web: PHP 8.6, Apache, Xdebug e acceso con daw-shell.
                 Os demais servizos arráncanse cos seus comandos específicos.
  daw-start-all  Arranca a contorna completa (web, db e phpmyadmin).
  daw-start-db   Arranca a base de datos MariaDB e o servizo web xuntos.
  daw-start-angular  Arranca Angular e prepara o acceso SSH dwcc-angular.
  daw-code       Abre o proxecto no perfil DWCS - PHP de VS Code.
  daw-stop       Para os contedores da contorna DAW Dev sen borrar datos.
  daw-status     Mostra o estado e portos dos contedores da contorna.
  daw-logs       Mostra e segue as últimas liñas de logs dos contedores (Ctrl+C para saír).
  daw-shell      Abre unha terminal interactiva bash no contedor web co usuario ad.
  daw-publicar   Sincroniza o código e as solucións de DWCS cara a daw-dev/www/dwcs.
  daw-help       Mostra esta axuda.

Tamén podes invocar:
  daw <start|start-all|start-db|start-angular|code|stop|status|logs|shell|check|publicar|help> [argumentos...]
EOF
}

PROG_NAME="$(basename "$0")"
ACTION=""

case "$PROG_NAME" in
    daw-start)          ACTION="start" ;;
    daw-start-all)      ACTION="start-all" ;;
    daw-start-db)       ACTION="start-db" ;;
    daw-start-angular)  ACTION="start-angular" ;;
    daw-code)           ACTION="code" ;;
    daw-stop)           ACTION="stop" ;;
    daw-status)         ACTION="status" ;;
    daw-logs)           ACTION="logs" ;;
    daw-shell|daw-bash) ACTION="shell" ;;
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
    start)
        docker compose "${COMPOSE_ARGS[@]}" up -d --wait --wait-timeout 300 --no-deps web "$@"
        ;;
    start-all)
        docker compose "${COMPOSE_ARGS[@]}" up -d --wait --wait-timeout 300 "$@"
        ;;
    start-db)
        docker compose "${COMPOSE_ARGS[@]}" up -d --wait --wait-timeout 300 db web "$@"
        ;;
    stop)
        docker compose "${COMPOSE_ARGS[@]}" --profile angular stop "$@"
        ;;
    status)
        docker compose "${COMPOSE_ARGS[@]}" ps --all --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" "$@"
        ;;
    logs)
        docker compose "${COMPOSE_ARGS[@]}" --profile angular logs --tail 100 -f "$@"
        ;;
    start-angular)
        "$SCRIPT_DIR/preparar-angular.sh"
        docker compose "${COMPOSE_ARGS[@]}" --profile angular up -d --wait --wait-timeout 300 angular "$@"
        printf '%s\n' 'Angular dispoñible: ssh dwcc-angular' 'VS Code: Remote-SSH → dwcc-angular → /home/node/proxectos' 'Aplicación: ng serve --host 0.0.0.0 → http://localhost:4200'
        ;;
    code)
        code --new-window --profile 'DWCS - PHP' "$PROJECT_DIR" "$@"
        ;;
    shell|bash)
        docker compose "${COMPOSE_ARGS[@]}" exec -u ad web bash "$@"
        ;;
    check|comprobar)
        "$PROJECT_DIR/scripts/comprobar.sh" "$@"
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
