#!/usr/bin/env bash
# Comproba que a contorna DAW Dev funciona e mostra un informe.
#
# Uso:  ./scripts/check.sh [--build] [--all | --doc | --frontend]
#   --build        reconstrúe a imaxe antes de comprobar
#   --doc          comproba tamén a documentación sen conexión (daw-start-doc)
#   --frontend     comproba tamén o frontend Angular e o acceso SSH dwcc-angular
#   --all          equivalente a --doc --frontend
#
# Arranca a contorna se non está en marcha. Non borra datos nin cambia a configuración:
# os ficheiros de proba que crea en www/ elimínanse ao rematar.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

BUILD=()
CHECK_DOC=0
CHECK_FRONTEND=0
for opcion in "$@"; do
    case $opcion in
        --build) BUILD=(--build) ;;
        --doc) CHECK_DOC=1 ;;
        --frontend) CHECK_FRONTEND=1 ;;
        --all) CHECK_DOC=1; CHECK_FRONTEND=1 ;;
        -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Opción descoñecida: $opcion (usa --help)" >&2; exit 2 ;;
    esac
done

LOG=$(mktemp -t daw-dev-check.XXXXXX.log)
ESCOITA=""
WWW=""
PROBA=".comprobar-$$"
cleanup() {
    rm -f -- "$LOG"
    [[ -n $ESCOITA ]] && rm -f -- "$ESCOITA"
    [[ -n $WWW ]] && rm -f -- "$WWW/$PROBA.php" "$WWW/$PROBA.txt"
}
trap cleanup EXIT

FALLOS=0
ok()     { printf '\033[32mOK\033[0m     %s\n' "$*"; }
fallo()  { printf '\033[31mFALLO\033[0m  %s\n' "$*"; FALLOS=$((FALLOS + 1)); }
aviso()  { printf '\033[33mAVISO\033[0m  %s\n' "$*"; }
seccion() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
# Páxina de estado como táboa de texto: "✔ nome detalle"
estado() { curl -sk "${1%/}/index.php" | sed -n '/<table>/,/<\/table>/p' | sed 's/<[^>]*>/ /g' | tr -s ' \n' | grep -v '^ *$' | paste - - -; }

seccion "Sistema"
. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-?} · kernel $(uname -r)"
grep -qi microsoft /proc/version 2>/dev/null && echo "WSL2 detectado"
echo "Usuario: $(id -un) (uid $(id -u))"
docker version --format 'Docker Engine {{.Server.Version}}' 2>/dev/null || { fallo "Docker non responde"; exit 1; }
docker compose version

seccion "Arranque"
# Os contedores dos servizos anteriores ao 27-11-2026 ocuparían os portos.
bash scripts/daw.sh remove-old-services
# Un Dev Container aberto compróbase tal como está: Compose recrearía backend-c coa
# definición de daw-start e VS Code quedaría en «Cannot reconnect».
SERVIZOS=()
DEVCONTAINER=
id=$(docker compose ps -q --status running backend 2>/dev/null)
if [[ -n $id && -n $(docker inspect -f '{{index .Config.Labels "devcontainer.local_folder"}}' "$id" 2>/dev/null) ]]; then
    DEVCONTAINER=1 SERVIZOS=(db db-admin)
    aviso "backend-c está aberto en Dev Containers: compróbase sen recrealo${BUILD[*]:+, e sen --build}"
    BUILD=()
fi
inicio=$SECONDS
if docker compose up -d "${BUILD[@]}" --wait --wait-timeout 300 "${SERVIZOS[@]}" > "$LOG" 2>&1; then
    ok "docker compose up${BUILD[*]:+ ${BUILD[*]}} en $((SECONDS - inicio)) s"
else
    fallo "docker compose up: últimas liñas do log:"; tail -20 "$LOG"
    exit 1
fi
docker compose ps --format '{{.Service}}: {{.Status}}'

# Portos e cartafol reais (respectan o .env)
porto() { docker compose --profile frontend --profile doc port "$1" "$2" 2>/dev/null | head -n 1 | sed 's/.*://'; }
WEB="http://localhost:$(porto backend 80)"
PMA="http://localhost:$(porto db-admin 80)"
CONTEDOR=$(docker compose ps -q backend)
WWW=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/www/html"}}{{.Source}}{{end}}{{end}}' "$CONTEDOR")
IMAXE=$(docker inspect -f '{{.Config.Image}}' "$CONTEDOR")

seccion "Páxina de estado ($WEB)"
for _ in $(seq 1 15); do curl -s -o /dev/null "$WEB/" && break; sleep 1; done
if curl -fsS "$WEB/" | grep -Eq 'href="(\./)?index\.php"'; then
    ok "listaxe de directorios mesmo con index.php"
else
    fallo "a raíz non mostra a listaxe de ficheiros"
fi
E=$(estado "$WEB/")
echo "$E"
if [ "$(grep -c '✔' <<< "$E")" -ge 10 ] && ! grep -q '✘' <<< "$E"; then ok "todo en verde"; else fallo "hai comprobacións en vermello"; fi
SERVIDOR=$(grep -o 'Servidor web.*' <<< "$E" | awk -F'\t' '{print $2}' | sed 's/^ *//')

seccion "Ferramentas no contedor"
if docker compose exec -T -u ad backend sh -ec 'test "$HOME" = /home/ad && ! id dev >/dev/null 2>&1 && ! getent group dev && test ! -e /home/dev && test ! -L /home/dev'; then
    ok "conta ad e directorio /home/ad"
else
    fallo "a imaxe web non ten a conta ad limpa"
fi
if docker compose exec -T -u ad backend sh -c 'MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" "$DB_NAME" -e "SELECT nome FROM alumnado"' 2>/dev/null | grep -q 'Uxía'; then
    ok "cliente mysql e acentos (utf8mb4)"
else
    fallo "cliente mysql (credenciais cambiadas no .env? BD sen os datos de exemplo?)"
fi
if docker compose exec -T -u ad backend bash -c 'd=$(mktemp -d) && cd "$d" && composer require -q psr/log >/dev/null 2>&1 && test -f vendor/autoload.php; r=$?; rm -rf "$d"; exit $r'; then
    ok "composer require"
else
    fallo "composer require (sen acceso a packagist.org?)"
fi

seccion "Ficheiros e permisos"
echo '<?php file_put_contents(__DIR__ . "/'"$PROBA"'.txt", "x"); echo "v1";' > "$WWW/$PROBA.php"
if [ "$(curl -s "$WEB/$PROBA.php")" = v1 ] && [ -f "$WWW/$PROBA.txt" ]; then
    dono=$(stat -c %u "$WWW/$PROBA.txt")
    if [ "$dono" = "$(id -u)" ]; then
        ok "os ficheiros que crea PHP son de $(id -un)"
    else
        fallo "os ficheiros que crea PHP son do uid $dono, non do teu ($(id -u)): pon USER_UID/USER_GID no .env e executa docker compose build"
    fi
else
    fallo "PHP non executa ficheiros novos de www/"
fi
sed -i 's/v1/v2/' "$WWW/$PROBA.php"
if [ "$(curl -s "$WEB/$PROBA.php")" = v2 ]; then ok "os cambios vense ao momento (OPcache)"; else fallo "os cambios non se ven ao recargar"; fi

seccion "Xdebug"
# Simula VS Code escoitando no porto 9003 deste equipo (en WSL2: dentro de Debian) ou, nun
# Dev Container, dentro do contedor, onde Xdebug conecta (client_host=localhost)
ESCOITA=$(mktemp -t daw-dev-xdebug.XXXXXX)
ESCOITA_PHP='
    $s = @stream_socket_server("tcp://0.0.0.0:9003");
    if (!$s) { echo "OCUPADO"; exit; }
    $c = @stream_socket_accept($s, 15);
    echo $c ? fread($c, 4096) : "SEN_CONEXION";'
if [[ -n $DEVCONTAINER ]]; then
    docker compose exec -T backend php -n -r "$ESCOITA_PHP" > "$ESCOITA" 2>&1 &
else
    docker run --rm --network host --entrypoint php "$IMAXE" -n -r "$ESCOITA_PHP" > "$ESCOITA" 2>&1 &
fi
sleep 3
curl -s -m 10 -o /dev/null "$WEB/info.php"
wait
if grep -q 'fileuri=' "$ESCOITA"; then
    ok "Xdebug conecta co depurador do porto 9003"
elif grep -q OCUPADO "$ESCOITA"; then
    aviso "o porto 9003 está ocupado (VS Code xa escoitando?): non se comproba"
else
    fallo "Xdebug non conectou co porto 9003 (cortalumes?)"
fi
t=$(curl -s -o /dev/null -w '%{time_total}' "$WEB/info.php")
echo "       tempo de resposta sen depurador: ${t}s"

seccion "phpMyAdmin ($PMA)"
codigo=$(curl -s -o /dev/null -w '%{http_code}' "$PMA/")
if [ "$codigo" = 200 ]; then ok "phpMyAdmin responde"; else fallo "phpMyAdmin responde $codigo"; fi

if [[ $CHECK_DOC -eq 1 ]]; then
    seccion "Documentación sen conexión"
    if bash scripts/daw.sh start-doc > "$LOG" 2>&1; then
        ok "daw-start-doc"
        for spec in "doc-php:80:PHP:/pagefind/pagefind-ui.js" "doc-web:9292:Web:/pagefind/pagefind-ui.js" "doc-laravel:80:Laravel:"; do
            IFS=: read -r svc cport label extra <<< "$spec"
            hport=$(porto "$svc" "$cport")
            if [[ -z $hport ]]; then
                fallo "$label ($svc): sen porto publicado"
                continue
            fi
            url="http://localhost:$hport"
            code=$(curl -s -o /dev/null -w '%{http_code}' "$url/")
            if [[ $code == 200 ]]; then
                if [[ -n $extra ]]; then
                    extra_code=$(curl -s -o /dev/null -w '%{http_code}' "$url$extra")
                    if [[ $extra_code == 200 ]]; then
                        ok "$label responde ($url/) con buscador"
                    else
                        fallo "$label ($url$extra) responde $extra_code"
                    fi
                else
                    ok "$label responde ($url/)"
                fi
            else
                fallo "$label ($url/) responde $code"
            fi
        done
    else
        fallo "daw-start-doc: últimas liñas do log:"; tail -20 "$LOG"
    fi
fi

if [[ $CHECK_FRONTEND -eq 1 ]]; then
    seccion "Frontend (Angular)"
    if bash scripts/daw.sh start-frontend > "$LOG" 2>&1; then
        ok "daw-start-frontend"
        fe_id=$(docker compose --profile frontend ps -q frontend 2>/dev/null)
        fe_health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$fe_id" 2>/dev/null)
        if [[ $fe_health == healthy ]]; then
            ok "frontend-c healthy"
        else
            fallo "frontend-c estado de saúde: ${fe_health:-descoñecido}"
        fi
        if command -v ssh >/dev/null 2>&1; then
            if ssh_out=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=5 dwcc-angular \
                'printf "Node %s · Angular CLI %s\n" "$(node -v)" "$(ng version 2>/dev/null | sed -n "s/.*Angular CLI[[:space:]]*:[[:space:]]*//p" | head -n 1)"' 2>"$LOG"); then
                ok "SSH dwcc-angular (${ssh_out})"
            else
                fallo "SSH dwcc-angular fallou:"; tail -10 "$LOG"
            fi
        else
            aviso "non se atopou ssh; non se comproba a conexión dwcc-angular"
        fi
    else
        fallo "daw-start-frontend: últimas liñas do log:"; tail -20 "$LOG"
    fi
fi

seccion "Resultado"
echo "Servidor: ${SERVIDOR:-?} · imaxe: $IMAXE"
if [ "$FALLOS" -eq 0 ]; then ok "todo correcto"; else fallo "$FALLOS comprobacións fallaron"; fi
exit $(( FALLOS > 0 ))
