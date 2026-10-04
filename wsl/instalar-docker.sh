#!/usr/bin/env bash
# Instala Docker Engine en Debian (WSL2) para a contorna DWCS.
# Uso, dentro de Debian:  sudo bash instalar-docker.sh
# Non precisa permisos de administrador de Windows: só o contrasinal do teu usuario de Debian.
set -euo pipefail

if [ "$(id -u)" -ne 0 ] || [ -z "${SUDO_USER:-}" ]; then
    echo "Executa o script con sudo desde o teu usuario: sudo bash $0" >&2
    exit 1
fi
USUARIO=$SUDO_USER

echo "==> Activando systemd en WSL (/etc/wsl.conf)"
touch /etc/wsl.conf
if grep -q '^systemd *= *true' /etc/wsl.conf; then
    echo "    xa estaba activado"
elif grep -q '^\[boot\]' /etc/wsl.conf; then
    sed -i '/^\[boot\]/a systemd=true' /etc/wsl.conf
else
    printf '\n[boot]\nsystemd=true\n' >> /etc/wsl.conf
fi

echo "==> Instalando dependencias"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl git > /dev/null

echo "==> Engadindo o repositorio oficial de Docker"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $VERSION_CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list

echo "==> Instalando Docker Engine e Docker Compose"
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null

echo "==> Permitindo usar docker sen sudo a $USUARIO"
usermod -aG docker "$USUARIO"

echo
echo "FEITO. Agora:"
echo "  1. Pecha esta xanela de Debian."
echo "  2. En PowerShell (sen administrador) executa:  wsl --shutdown"
echo "  3. Volve abrir Debian e comproba:  docker run --rm hello-world"
