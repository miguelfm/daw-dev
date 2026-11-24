#!/bin/sh
# Comprobación de saúde de MariaDB (healthcheck de compose.yaml).
#
# Os contrasinais de MariaDB son os do .env: abc123.. por defecto, o da MV da
# aula. Un volume creado antes do 24-11-2026 garda o contrasinal por defecto
# anterior, e MariaDB só le os do .env ao crear o volume. A primeira vez que o
# servidor responde en cada contedor, root e o usuario da BD que aínda teñan o
# anterior pasan aos do .env. Vale para calquera arranque: daw-start-db,
# daw-start-all, docker compose up ou Dev Containers. Un contrasinal cambiado a
# man non se toca.

# Script incluído na imaxe oficial: só dá "ok" cando rematou a inicialización
healthcheck.sh --connect --innodb_initialized || exit 1

feito=/tmp/daw-contrasinais
[ -e "$feito" ] && exit 0
anterior='abc123.'
# Por TCP: polo socket, root entra sen contrasinal (unix_socket)
entra() {
    MYSQL_PWD=$2 mariadb --protocol=TCP -h 127.0.0.1 -u "$1" -e 'SELECT 1' >/dev/null 2>&1
}
literal() {
    printf "'%s'" "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g")"
}

if entra root "$MARIADB_ROOT_PASSWORD"; then
    root=$MARIADB_ROOT_PASSWORD
elif entra root "$anterior"; then
    root=$anterior
else
    # root ten outro contrasinal, posto a man: non se cambia nada
    touch "$feito"
    exit 0
fi
ordes=''
if [ "$root" != "$MARIADB_ROOT_PASSWORD" ]; then
    novo=$(literal "$MARIADB_ROOT_PASSWORD")
    ordes="ALTER USER IF EXISTS 'root'@'%' IDENTIFIED BY $novo;"
    ordes="$ordes ALTER USER IF EXISTS 'root'@'localhost' IDENTIFIED BY $novo;"
fi
if [ -n "$MARIADB_USER" ] && ! entra "$MARIADB_USER" "$MARIADB_PASSWORD" \
        && entra "$MARIADB_USER" "$anterior"; then
    ordes="$ordes ALTER USER $(literal "$MARIADB_USER")@'%' IDENTIFIED BY $(literal "$MARIADB_PASSWORD");"
fi
if [ -n "$ordes" ]; then
    MYSQL_PWD=$root mariadb --protocol=TCP -h 127.0.0.1 --skip-ssl-verify-server-cert \
        -u root -e "$ordes" >/dev/null 2>&1 || exit 1
fi
touch "$feito"
