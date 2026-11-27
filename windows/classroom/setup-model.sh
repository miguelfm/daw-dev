#!/usr/bin/env bash
# Só se executa na distribución NOVA creada por build-package.ps1.
set -euo pipefail
action=${1:?install|images|seal}
# Valores de daw-classroom.psm1 (ruta do proxecto, imaxe web e marcador do modelo), desde build-package.ps1.
project=${DAW_PROJECT:?Falta DAW_PROJECT: executar desde build-package.ps1}
web_image=${DAW_WEB_IMAGE:?Falta DAW_WEB_IMAGE: executar desde build-package.ps1}
marker_file=${DAW_MODEL_MARKER_FILE:?Falta DAW_MODEL_MARKER_FILE: executar desde build-package.ps1}
marker=${DAW_MODEL_MARKER:?Falta DAW_MODEL_MARKER: executar desde build-package.ps1}
[[ $(id -u) == 0 ]] || { echo 'Precisa root na distribución modelo.' >&2; exit 1; }
. /etc/os-release
[[ $ID == debian ]] || { echo 'O modelo debe ser Debian.' >&2; exit 1; }
case "$action" in
install)
    [[ ! -e $marker_file ]] || { echo 'O modelo xa foi configurado.' >&2; exit 1; }
    # O tar procede de git archive: exclúe .env, código do profesor e credenciais.
    [[ ! -e /home/ad && ! -L /home/ad ]] || { echo '/home/ad xa existe; precisa unha base limpa.' >&2; exit 1; }
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y systemd systemd-sysv dbus sudo git curl wget ca-certificates procps python3
    useradd --uid 1000 --user-group --create-home --shell /bin/bash ad
    passwd --lock ad
    mkdir -p "$project"
    tar -xf "${2:?sources.tar}" -C "$project"
    cp -a "$project/windows/classroom/overlay/." "$project/"
    # A contorna queda en $project; o que é do alumnado, no home: o código web en ~/html (coa
    # configuración de VS Code da aula), os datos en ~/data e os proxectos de Angular en ~/angular.
    home=${project%/*}
    mv -T "$project/www" "$home/html"
    cp -a "$project/html/." "$home/html/"
    rm -rf -- "$project/html"
    install -D -m 644 "$project/.vscode/settings.json" "$home/html/.vscode/settings.json"
    mv -T "$project/data" "$home/data"
    mv -T "$project/angular" "$home/angular"
    cat > /etc/wsl.conf <<'EOF'
[boot]
systemd=true
[user]
default=ad
EOF
    SUDO_USER=ad bash "$project/scripts/install-docker.sh"
    cp "$project/.env.example" "$project/.env"
    sed -i -e 's/^WEB_PORT=.*/WEB_PORT=127.0.0.1:80/' \
           -e 's/^PMA_PORT=.*/PMA_PORT=127.0.0.1:8081/' \
           -e 's/^DB_PORT=.*/DB_PORT=127.0.0.1:3306/' "$project/.env"
    chown -R ad:ad /home/ad
    # Comandos dispoñibles tamén dentro da distribución: os mesmos de scripts/daw.sh, que
    # escolle a orde polo nome da ligazón e resolve o proxecto desde a súa ruta real.
    for command in daw-start daw-star daw-start-all daw-start-db daw-stop daw-status daw-web-root daw-web-shell daw-shell; do
        ln -s "$project/scripts/daw.sh" "/usr/local/bin/$command"
    done
    printf '%s\n' "$marker" > "$marker_file"
    ;;
images)
    [[ $(cat "$marker_file") == "$marker" ]]
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
    runuser -u ad -- docker compose config --images backend | grep -Fxq "$web_image"
    docker run --rm --pull never --network none --user ad --entrypoint sh "$web_image" -ec \
        'test "$HOME" = /home/ad && ! id dev >/dev/null 2>&1 && test ! -e /home/dev && test ! -L /home/dev'
    # Sen contedores persistentes nin volumes: cada alumno inicializa a súa propia BD.
    [[ -z $(docker ps -aq) && -z $(docker volume ls -q) ]]
    ;;
seal)
    [[ $(cat "$marker_file") == "$marker" ]]
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
