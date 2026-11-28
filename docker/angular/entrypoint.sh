#!/bin/sh
set -eu
install -d -m 700 -o node -g node /home/node/.ssh
install -m 600 -o node -g node /chave.pub /home/node/.ssh/authorized_keys
if [ ! -s /claves-host/ed25519 ]; then
    ssh-keygen -q -t ed25519 -N '' -f /claves-host/ed25519
elif [ ! -s /claves-host/ed25519.pub ]; then
    ssh-keygen -y -f /claves-host/ed25519 > /claves-host/ed25519.pub
fi
exec /usr/sbin/sshd -D -e -h /claves-host/ed25519 -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o PermitRootLogin=no -o AllowUsers=node
