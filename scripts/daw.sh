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

# Ata o 24-11-2026 o contrasinal por defecto de MariaDB era abc123.; agora é
# abc123.., o da MV da aula. MariaDB só le os do .env ao crear o volume: nun
# volume anterior, root e o usuario da BD que conserven o valor vello cámbianse
# aos do .env. Un contrasinal cambiado a man non se toca.
sincronizar_bd() {
    docker compose "${COMPOSE_ARGS[@]}" exec -T db sh -s <<'SQL'
vello='abc123.'
# Por TCP: polo socket, root entra sen contrasinal (unix_socket)
entra() { MYSQL_PWD=$2 mariadb --protocol=TCP -h 127.0.0.1 -u "$1" -e 'SELECT 1' >/dev/null 2>&1; }
literal() { printf "'%s'" "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g")"; }
if entra root "$MARIADB_ROOT_PASSWORD"; then
    root=$MARIADB_ROOT_PASSWORD
elif entra root "$vello"; then
    root=$vello
else
    echo 'Aviso: o contrasinal de root de MariaDB non é o do .env; non se cambiou nada.' >&2
    exit 0
fi
ordes=''
if [ "$root" != "$MARIADB_ROOT_PASSWORD" ]; then
    novo=$(literal "$MARIADB_ROOT_PASSWORD")
    ordes="ALTER USER IF EXISTS 'root'@'%' IDENTIFIED BY $novo;"
    ordes="$ordes ALTER USER IF EXISTS 'root'@'localhost' IDENTIFIED BY $novo;"
fi
if [ -n "$MARIADB_USER" ] && ! entra "$MARIADB_USER" "$MARIADB_PASSWORD" \
        && entra "$MARIADB_USER" "$vello"; then
    ordes="$ordes ALTER USER $(literal "$MARIADB_USER")@'%' IDENTIFIED BY $(literal "$MARIADB_PASSWORD");"
fi
[ -n "$ordes" ] || exit 0
MYSQL_PWD=$root mariadb --protocol=TCP -h 127.0.0.1 --skip-ssl-verify-server-cert -u root -e "$ordes"
echo 'Contrasinais de MariaDB cambiados aos do .env (abc123.. por defecto).'
SQL
}

show_help() {
    cat << 'EOF'
Uso: daw-start | daw-start-all | daw-start-db | daw-start-angular | daw-start-doc
     daw-stop | daw-status | daw-logs | daw-shell | daw-help

Comandos dispoñibles:
  daw-start      Arranca só daw-web: PHP 8.6, Apache, Xdebug e acceso con daw-shell.
                 Os demais servizos arráncanse cos seus comandos específicos.
  daw-start-all  Arranca a contorna completa (web, db e phpmyadmin).
  daw-start-db   Arranca a base de datos MariaDB e o servizo web xuntos.
  daw-start-angular  Arranca Angular e prepara o acceso SSH dwcc-angular.
  daw-start-doc  Arranca a documentación sen conexión: manual de PHP (8080),
                 DevDocs (5042) e Laravel (8088).
  daw-code       Abre o proxecto no perfil DWCS - PHP de VS Code.
  daw-stop       Para os contedores da contorna DAW Dev sen borrar datos.
  daw-status     Mostra o estado e portos dos contedores da contorna.
  daw-logs       Mostra e segue as últimas liñas de logs dos contedores (Ctrl+C para saír).
  daw-shell      Abre unha terminal interactiva bash no contedor web co usuario ad.
  daw-publicar   Sincroniza o código e as solucións de DWCS cara a daw-dev/www/dwcs.
  daw-help       Mostra esta axuda.

Tamén podes invocar:
  daw <start|start-all|start-db|start-angular|start-doc|code|stop|status|logs|shell|check|publicar|help> [argumentos...]
EOF
}

PROG_NAME="$(basename "$0")"
ACTION=""

case "$PROG_NAME" in
    daw-start)          ACTION="start" ;;
    daw-start-all)      ACTION="start-all" ;;
    daw-start-db)       ACTION="start-db" ;;
    daw-start-angular)  ACTION="start-angular" ;;
    daw-start-doc)      ACTION="start-doc" ;;
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
        sincronizar_bd
        ;;
    start-db)
        docker compose "${COMPOSE_ARGS[@]}" up -d --wait --wait-timeout 300 db web "$@"
        sincronizar_bd
        ;;
    sincronizar-bd)
        # Para daw.ps1, que arranca os contedores desde Windows
        sincronizar_bd
        ;;
    stop)
        docker compose "${COMPOSE_ARGS[@]}" --profile angular --profile doc stop "$@"
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
        printf '%s\n' 'Manual de PHP: http://localhost:8080/' 'DevDocs:       http://localhost:5042/' \
            'Laravel:       http://localhost:8088/'
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
