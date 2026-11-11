#!/usr/bin/env bash
# Proba de BD usada por comprobar-alumno.ps1, só nunha conta de proba.
set -euo pipefail
action=${1:?write|read|clean}
token=${2:?token}
[[ $token =~ ^[a-f0-9]{32}$ ]] || exit 2
cd /home/alumno/proxectos/daw-dev
query() {
    docker compose exec -T db sh -c 'exec mariadb --batch --skip-column-names --user="$MARIADB_USER" --password="$MARIADB_PASSWORD" "$MARIADB_DATABASE"'
}
case "$action" in
write) printf 'CREATE TABLE daw_probe_%s (value VARCHAR(32)); INSERT INTO daw_probe_%s VALUES ("%s");\n' "$token" "$token" "$token" | query ;;
read) printf 'SELECT value FROM daw_probe_%s;\n' "$token" | query ;;
clean) printf 'DROP TABLE IF EXISTS daw_probe_%s;\n' "$token" | query ;;
*) exit 2 ;;
esac
