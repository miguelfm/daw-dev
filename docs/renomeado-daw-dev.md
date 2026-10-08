# Migrar de dwcs-php a daw-dev

O proxecto, o repositorio, os contedores e os comandos pasan a usar o nome `daw-dev`.
O código de `www/` e os datos de MariaDB consérvanse. A base de datos e o usuario de exemplo
seguen chamándose `dwcs`; non é necesario renomealos para migrar a contorna.

## Instalacións existentes en Linux ou WSL2

Antes de actualizar, desde o cartafol antigo, consulta o nome do volume da BD:

```bash
docker inspect dwcs-db --format '{{range .Mounts}}{{if eq .Destination "/var/lib/mysql"}}{{.Name}}{{end}}{{end}}'
```

Na configuración orixinal é `dwcs_db_data`. Retira os contedores antigos conservando o volume:

```bash
docker compose down
```

Non engadas `-v`: esa opción eliminaría os datos dos volumes xestionados polo proxecto.

Actualiza o remoto e descarga o cambio de nome:

```bash
git remote set-url origin https://github.com/miguelfm/daw-dev.git
git pull --ff-only
```

Renomea o cartafol desde o seu directorio pai. Axusta estes nomes se a túa copia estaba noutro lugar:

```bash
cd ..
mv dwcs-php daw-dev
cd daw-dev
```

No `.env`, conserva os teus valores de portos, ruta de `www/` e credenciais. Engade estas dúas liñas,
usando o nome do volume que consultaches antes:

```dotenv
DB_VOLUME_NAME=dwcs_db_data
DB_VOLUME_EXTERNAL=true
```

A montaxe reutiliza ese volume. Ao ser externo, Compose non o crea se falta nin o elimina con `down -v`.
Se tiñas `DWCS_IMAGE` no `.env`, cambia o nome da variable a `DAW_DEV_IMAGE`; a imaxe publicada
pasa a ser `ghcr.io/miguelfm/daw-dev:8.5`. Se `WWW_DIR` era unha ruta absoluta dentro do cartafol
antigo, actualízaa tamén. As rutas relativas como `./www` seguen funcionando.

Actualiza as definicións dos atallos da túa shell segundo o [README](../README.md#atallos-daw-dev-para-a-terminal).
Agora chámanse `daw-dev-start`, `daw-dev-start-all`, `daw-dev-start-db`, `daw-dev-stop`,
`daw-dev-status`, `daw-dev-logs` e `daw-dev-help`.

Para iniciar só o web, executa `daw-dev-start`. Para comprobar a contorna completa:

```bash
daw-dev-start-all
./scripts/comprobar.sh
```

Os novos contedores chámanse `daw-dev-web`, `daw-dev-db` e `daw-dev-phpmyadmin`.
As instalacións novas usan por defecto o volume `daw-dev_db_data`; as migradas poden conservar
o nome antigo mediante as variables anteriores.

## Lanzadores de Windows

Se usas unha copia do repositorio en Windows, retira primeiro os contedores antigos desde esa copia:

```powershell
wsl -d Debian --cd C:\Users\miguelfm\Projects\dwcs-php -- docker compose down
```

Actualiza o repositorio, renomea o cartafol a `daw-dev` e axusta o `.env` como no apartado anterior.
Desde a nova raíz do repositorio, executa:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wsl\install-daw-dev-commands.ps1
```

O instalador crea os lanzadores `daw-dev-*.cmd` e retira os antigos `dwcs*.cmd` cando apuntan
a esta copia ou á súa antiga localización. Abre outra terminal e executa `daw-dev-help`.
Consulta a [guía de Windows](windows11-contedores.md) para o uso habitual.

## Repositorio de GitHub

O novo repositorio é <https://github.com/miguelfm/daw-dev>. GitHub redirixe as ligazóns e operacións
Git do nome antigo, pero convén actualizar `origin` como nos comandos anteriores.
Véxase a [documentación de GitHub sobre renomeados](https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository).
