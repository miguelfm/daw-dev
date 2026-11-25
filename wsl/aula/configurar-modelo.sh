#!/usr/bin/env bash
# Só se executa na distribución NOVA creada por preparar-modelo.ps1.
set -euo pipefail
action=${1:?install|images|seal}
project=/home/ad/proxectos/daw-dev
[[ $(id -u) == 0 ]] || { echo 'Precisa root na distribución modelo.' >&2; exit 1; }
. /etc/os-release
[[ $ID == debian ]] || { echo 'O modelo debe ser Debian.' >&2; exit 1; }
case "$action" in
install)
    [[ ! -e /etc/daw-aula-modelo ]] || { echo 'O modelo xa foi configurado.' >&2; exit 1; }
    # O tar procede de git archive: exclúe .env, código do profesor e credenciais.
    [[ ! -e /home/ad && ! -L /home/ad ]] || { echo '/home/ad xa existe; precisa unha base limpa.' >&2; exit 1; }
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y systemd systemd-sysv dbus sudo git curl wget ca-certificates procps python3
    useradd --uid 1000 --user-group --create-home --shell /bin/bash ad
    passwd --lock ad
    mkdir -p "$project"
    tar -xf "${2:?sources.tar}" -C "$project"
    cp -a "$project/wsl/aula/proxecto/ficheiros/." "$project/"
    ln -s "$project/www" /home/ad/www
    cat > /etc/wsl.conf <<'EOF'
[boot]
systemd=true
[user]
default=ad
EOF
    SUDO_USER=ad bash "$project/wsl/instalar-docker.sh"
    cp "$project/.env.example" "$project/.env"
    sed -i -e 's/^WEB_PORT=.*/WEB_PORT=127.0.0.1:80/' \
           -e 's/^PMA_PORT=.*/PMA_PORT=127.0.0.1:8081/' \
           -e 's/^DB_PORT=.*/DB_PORT=127.0.0.1:3306/' "$project/.env"
    chown -R ad:ad /home/ad
    # Comandos dispoñibles tamén dentro de Debian, en terminais interactivas.
    cat > /usr/local/bin/daw-aula-command <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd /home/ad/proxectos/daw-dev
case "${0##*/}" in
  daw-start|daw-star) exec docker compose up -d --wait --wait-timeout 300 --no-deps web "$@" ;;
  daw-start-all) exec docker compose up -d --wait --wait-timeout 300 "$@" ;;
  daw-start-db) exec docker compose up -d --wait --wait-timeout 300 db web "$@" ;;
  daw-stop) exec docker compose stop "$@" ;;
  daw-status) exec docker compose ps --all "$@" ;;
  daw-web-root) exec bash scripts/daw.sh web-root "$@" ;;
  daw-web-shell|daw-shell) exec bash scripts/daw.sh web-shell "$@" ;;
esac
EOF
    chmod 755 /usr/local/bin/daw-aula-command
    for command in daw-start daw-star daw-start-all daw-start-db daw-stop daw-status daw-web-root daw-web-shell daw-shell; do
        ln -s /usr/local/bin/daw-aula-command "/usr/local/bin/$command"
    done
    printf '%s\n' 'daw-aula-v1' > /etc/daw-aula-modelo
    ;;
images)
    [[ $(cat /etc/daw-aula-modelo) == daw-aula-v1 ]]
    systemctl enable --now docker.service containerd.service
    for ((i=0; i<60; i++)); do docker info >/dev/null 2>&1 && break; sleep 1; done
    docker info >/dev/null
    cd "$project"
    runuser -u ad -- docker compose config --quiet
    if [[ -n ${2:-} ]]; then
        docker image load --input "$2"
        while IFS= read -r image; do docker image inspect "$image" >/dev/null; done < <(docker compose config --images)
    else
        runuser -u ad -- docker compose pull
    fi
    web_image=ghcr.io/miguelfm/dwcs-php:8.6-ad
    runuser -u ad -- docker compose config --images web | grep -Fxq "$web_image"
    docker run --rm --pull never --network none --user ad --entrypoint sh "$web_image" -ec \
        'test "$HOME" = /home/ad && ! id dev >/dev/null 2>&1 && test ! -e /home/dev && test ! -L /home/dev'
    # Sen contedores persistentes nin volumes: cada alumno inicializa a súa propia BD.
    [[ -z $(docker ps -aq) && -z $(docker volume ls -q) ]]
    ;;
seal)
    [[ $(cat /etc/daw-aula-modelo) == daw-aula-v1 ]]
    [[ -z $(docker ps -aq) && -z $(docker volume ls -q) ]]
    systemctl stop docker.socket docker.service containerd.service
    # Un identificador novo en cada importación; ningunha identidade do profesor.
    truncate -s 0 /etc/machine-id
    ln -sf /etc/machine-id /var/lib/dbus/machine-id
    apt-get clean
    sync
    ;;
*) echo "Acción descoñecida: $action" >&2; exit 2 ;;
esac
