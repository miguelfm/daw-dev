#!/usr/bin/env bash
# Comproba que a contorna DWCS funciona e mostra un informe.
#
# Uso:  ./scripts/comprobar.sh [--build]
#   --build        reconstrúe a imaxe antes de comprobar
#
# Arranca a contorna se non está en marcha. Non borra datos nin cambia a configuración:
# os ficheiros de proba que crea en www/ elimínanse ao rematar.
set -uo pipefail
cd "$(dirname "$0")/.."

BUILD=()
for opcion in "$@"; do
    case $opcion in
        --build) BUILD=(--build) ;;
        -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Opción descoñecida: $opcion (usa --help)" >&2; exit 2 ;;
    esac
done

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
inicio=$SECONDS
if docker compose up -d "${BUILD[@]}" --wait --wait-timeout 300 > /tmp/dwcs-comprobar.log 2>&1; then
    ok "docker compose up${BUILD[*]:+ ${BUILD[*]}} en $((SECONDS - inicio)) s"
else
    fallo "docker compose up: últimas liñas do log:"; tail -20 /tmp/dwcs-comprobar.log
    exit 1
fi
docker compose ps --format '{{.Service}}: {{.Status}}'

# Portos e cartafol reais (respectan o .env)
porto() { docker compose port "$1" "$2" 2>/dev/null | sed 's/.*://'; }
WEB="http://localhost:$(porto web 80)"
PMA="http://localhost:$(porto phpmyadmin 80)"
CONTEDOR=$(docker compose ps -q web)
WWW=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/www/html"}}{{.Source}}{{end}}{{end}}' "$CONTEDOR")
IMAXE=$(docker inspect -f '{{.Config.Image}}' "$CONTEDOR")
PROBA=".comprobar-$$"
trap 'rm -f "$WWW/$PROBA.php" "$WWW/$PROBA.txt"' EXIT

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
if docker compose exec -T -u dev web mysql -udwcs -pabc123. dwcs -e 'SELECT nome FROM alumnado' 2>/dev/null | grep -q 'Uxía'; then
    ok "cliente mysql e acentos (utf8mb4)"
else
    fallo "cliente mysql (credenciais cambiadas no .env? BD sen os datos de exemplo?)"
fi
if docker compose exec -T -u dev web bash -c 'd=$(mktemp -d) && cd "$d" && composer require -q psr/log >/dev/null 2>&1 && test -f vendor/autoload.php; r=$?; rm -rf "$d"; exit $r'; then
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
# Simula VS Code escoitando no porto 9003 deste equipo (en WSL2: dentro de Debian)
escoita=$(mktemp)
docker run --rm --network host --entrypoint php "$IMAXE" -n -r '
    $s = @stream_socket_server("tcp://0.0.0.0:9003");
    if (!$s) { echo "OCUPADO"; exit; }
    $c = @stream_socket_accept($s, 15);
    echo $c ? fread($c, 4096) : "SEN_CONEXION";' > "$escoita" 2>&1 &
sleep 3
curl -s -m 10 -o /dev/null "$WEB/info.php"
wait
if grep -q 'fileuri=' "$escoita"; then
    ok "Xdebug conecta co depurador do porto 9003"
elif grep -q OCUPADO "$escoita"; then
    aviso "o porto 9003 está ocupado (VS Code xa escoitando?): non se comproba"
else
    fallo "Xdebug non conectou co porto 9003 (cortalumes?)"
fi
rm -f "$escoita"
t=$(curl -s -o /dev/null -w '%{time_total}' "$WEB/info.php")
echo "       tempo de resposta sen depurador: ${t}s"

seccion "phpMyAdmin ($PMA)"
codigo=$(curl -s -o /dev/null -w '%{http_code}' "$PMA/")
if [ "$codigo" = 200 ]; then ok "phpMyAdmin responde"; else fallo "phpMyAdmin responde $codigo"; fi

seccion "Resultado"
echo "Servidor: ${SERVIDOR:-?} · imaxe: $IMAXE"
if [ "$FALLOS" -eq 0 ]; then ok "todo correcto"; else fallo "$FALLOS comprobacións fallaron"; fi
exit $(( FALLOS > 0 ))
