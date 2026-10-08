# daw-dev

[![CI](https://github.com/miguelfm/daw-dev/actions/workflows/ci.yml/badge.svg)](https://github.com/miguelfm/daw-dev/actions/workflows/ci.yml)

Contorna Docker de desenvolvemento para **Desenvolvemento de Aplicacións Web (DAW)**.
Actualmente inclúe PHP e as ferramentas usadas no módulo **Desenvolvemento Web en Contorna Servidor (DWCS)**. Un só comando arranca PHP 8.5, servidor web, base de datos,
depurador e ferramentas, igual en Linux e en Windows 11 (WSL2). Fóra de Docker non hai que instalar PHP,
servidores nin bases de datos no equipo.

| Servizo      | Que é                                                  | URL / acceso                     |
|--------------|--------------------------------------------------------|----------------------------------|
| `web`        | PHP 8.5 + Apache, Xdebug 3, Composer, cliente MariaDB, git | <http://localhost> |
| `db`         | MariaDB (última LTS)                                   | `db:3306` (dende PHP) · `localhost:3306` (dende o equipo) |
| `phpmyadmin` | Xestión web da base de datos                           | <http://localhost:8081>          |

## Requisitos

- **Linux:** Docker Engine + plugin `compose`.
- **Windows 11:** WSL2 con Debian e Docker Engine, sen Docker Desktop. Guías:
  [preparación dos equipos (administración)](docs/wsl2-administracion.md) e
  [instalación e uso (alumnado)](docs/wsl2-alumnado.md).
- **Xestión gráfica opcional:** [Portainer CE en Debian/WSL2](docs/wsl2-alumnado.md#portainer-ce-xestión-gráfica-opcional),
  para xestionar Docker desde o navegador en <https://localhost:9443>.
- VS Code coa extensión **PHP Debug** (`xdebug.php-debug`). Ao abrir o proxecto, VS Code propón as extensións recomendadas.

## Posta en marcha

Se xa tiñas unha instalación de `dwcs-php`, segue a [guía de migración a daw-dev](docs/renomeado-daw-dev.md)
para actualizar os nomes e conservar os datos existentes.

En **Windows 11**, segue a [guía do alumnado](docs/wsl2-alumnado.md). En **Linux**:

```bash
git clone https://github.com/miguelfm/daw-dev.git
cd daw-dev
cp .env.example .env      # opcional, só se queres cambiar algo
docker compose up -d      # a primeira vez descarga as imaxes (uns minutos)
```

Abre <http://localhost> para ver a listaxe de ficheiros. En
<http://localhost/index.php>, a páxina de comprobación debe saír toda en verde.
O teu código vai na carpeta **`www/`**. Os cambios vense ao recargar o navegador.

Para comprobar a contorna completa (servidor, base de datos, Composer, permisos, Xdebug...):

```bash
./scripts/comprobar.sh
```

> **Linux:** a imaxe publicada usa o UID 1000, o do primeiro usuario de case todas as distribucións. Se o teu é
> outro (comproba con `id`), pon `USER_UID` e `USER_GID` no `.env` e constrúe a túa con `docker compose build`.
> Así os ficheiros que crea PHP son teus e non doutro usuario.

## Comandos do día a día

O servidor web mostra por defecto a listaxe de ficheiros e subdirectorios en cada
cartafol, mesmo se contén `index.php`, `index.html` ou `index.txt`. Para executar un ficheiro, ábreo explicitamente: por exemplo,
<http://localhost/index.php> ou `http://localhost/exercicio/index.php`.
En Apache, un `.htaccess` pode sobrescribir este comportamento.

A configuración do servidor móntase desde `docker/apache/daw-dev.conf`. Para aplicar esta actualización
a un contedor existente, executa `daw-dev-start` en Windows ou
`docker compose up -d --no-deps web` en Debian. Non precisa reconstruír a imaxe.
Tras editar só este ficheiro de configuración, reinicia o web con
`docker compose restart web`.

En **Windows 11**, podes instalar os comandos `daw-dev-*` no PATH do usuario para executar
`daw-dev-start` (só servidor web), `daw-dev-start-db` (BD e web),
`daw-dev-start-all` (web, BD e phpMyAdmin), `daw-dev-stop`,
`daw-dev-status` e `daw-dev-logs` desde PowerShell ou CMD.
Consulta a [guía de xestión de contedores en Windows 11](docs/windows11-contedores.md).

| Para…                                   | Comando                                         |
|-----------------------------------------|-------------------------------------------------|
| Arrancar só PHP + Apache                | `docker compose up -d --no-deps web`             |
| Arrancar a contorna completa / parar    | `docker compose up -d` / `docker compose stop`  |
| Ver estado, incluídos os parados        | `docker compose ps --all`                        |
| Ver erros de PHP e do servidor web      | `docker compose logs -f web`                    |
| Abrir unha shell no contedor            | `docker compose exec -u dev web bash`           |
| Consola de MariaDB                      | `docker compose exec -u dev web mysql -u dwcs -p dwcs` |
| Consola de MariaDB como root            | `docker compose exec db mariadb -u root -p`     |
| Composer                                | `docker compose exec -u dev web composer require monolog/monolog` |
| Executar un script PHP por consola      | `docker compose exec -u dev web php script.php` |
| Reconstruír tras cambiar Dockerfile/ini | `docker compose up -d --build`                  |
| Actualizar as imaxes publicadas         | `docker compose pull && docker compose up -d`   |
| Comprobar que todo funciona             | `./scripts/comprobar.sh`                        |
| Borrar contedores e volumes xestionados, **incluída a BD** | `docker compose down -v`             |

### Consola do contedor web

O contedor `daw-dev-web` debe estar en marcha e o teu usuario debe poder executar Docker.
Se está parado, arráncao con `daw-dev-start` se tes os atallos configurados, ou con
`docker compose up -d --no-deps web` desde o cartafol do proxecto.

Desde ese cartafol, abre unha consola co usuario `dev`:

```bash
docker compose exec -u dev web bash
```

Tamén podes entrar **desde calquera cartafol**, usando o nome fixo do contedor:

```bash
docker exec -it -u dev daw-dev-web bash
```

[`docker exec`](https://docs.docker.com/reference/cli/docker/container/exec/) usa `-it` para abrir
unha consola interactiva. [`docker compose exec`](https://docs.docker.com/reference/cli/docker/compose/exec/)
xa activa ese modo por defecto e usa o nome do servizo (`web`).

Dentro da shell estás en `/var/www/html`, o cartafol local definido por `WWW_DIR` (`www/` por defecto),
co usuario `dev`, que ten `sudo` sen contrasinal. Tes `php`, `composer` e `mysql` dispoñibles,
ademais de `nano`, `vi` e `vis` para editar ficheiros.

Para abrir a consola **como root**:

```bash
docker exec -it -u root daw-dev-web bash
```

Desde o proxecto tamén podes usar `docker compose exec -u root web bash`.
Escribe `exit` para pechar a consola; o contedor segue funcionando.

#### Acceso desde outro equipo por SSH

A imaxe DAW Dev non inclúe un servidor SSH. Se o **equipo anfitrión** ten SSH habilitado e a túa
conta pode executar Docker, conéctate a ese equipo e abre a consola do contedor:

```bash
ssh usuario@equipo
docker exec -it -u dev daw-dev-web bash
```

Substitúe `usuario@equipo` polo usuario e o nome ou IP do anfitrión. O segundo comando execútase
na sesión remota, sobre o Docker dese equipo. Un `exit` volve á consola do anfitrión;
outro `exit` pecha a sesión SSH.

En Windows con Docker dentro de WSL2, executa os comandos Docker na terminal de Debian ou usa
o [acceso desde PowerShell ou CMD](docs/windows11-contedores.md#consola-do-contedor-web).

### Atallos daw-dev para a terminal

Estes atallos permiten controlar a contorna desde calquera cartafol. Escolle o bloque correspondente
á túa shell e axusta a ruta ao lugar onde descargaches o proxecto. Os nomes usan guións en
todos os sistemas, tamén en PowerShell e CMD. O prefixo anterior `dwcs-` pasa a ser `daw-dev-`;
por exemplo, `dwcs-start` pasa a chamarse `daw-dev-start`.
Se xa tiñas os atallos configurados, substitúe as definicións antigas polas novas e abre outra
terminal para cargar os nomes actualizados.

| Atallo | Que fai |
|--------|---------|
| `daw-dev-start` | Arranca só `daw-dev-web` (servizo `web`), sen iniciar a base de datos nin phpMyAdmin. |
| `daw-dev-start-all` | Arranca `web`, `db` e `phpmyadmin`, como `docker compose up -d`. |
| `daw-dev-start-db` | Arranca a base de datos e o web. |
| `daw-dev-stop` | Para os contedores da contorna con `stop`, conservando os contedores e os datos. |
| `daw-dev-status` | Mostra unha táboa compacta co nome, estado e portos dos contedores existentes da contorna, incluídos os parados. |
| `daw-dev-logs` | Mostra as últimas 100 liñas de logs por servizo e segue as novas; `Ctrl+C` sae da consulta. |
| `daw-dev-help` | Mostra os comandos dispoñibles. |

`daw-dev-start` usa [`--no-deps`](https://docs.docker.com/reference/cli/docker/compose/up/) porque `web` ten
unha dependencia de `db`. Úsao cando traballes con PHP sen base de datos; para os exercicios con BD
ou para que a comprobación completa saia en verde, usa `daw-dev-start-all`. Se xa hai outros contedores
en marcha, `daw-dev-start` déixaos funcionando.

`daw-dev-status` usa [`ps --all`](https://docs.docker.com/reference/cli/docker/compose/ps/):
non mostra servizos cuxos contedores
aínda non se crearon ou xa se eliminaron.

#### Fish (Linux ou macOS)

Engade este bloque a `~/.config/fish/conf.d/my_aliases.fish` (crea o cartafol e o ficheiro se non existen):

```fish
alias daw-dev-start 'docker compose -f "$HOME/Projects/daw-dev/compose.yaml" up -d --no-deps web'
alias daw-dev-start-all 'docker compose -f "$HOME/Projects/daw-dev/compose.yaml" up -d'
alias daw-dev-start-db 'docker compose -f "$HOME/Projects/daw-dev/compose.yaml" up -d db web'
alias daw-dev-stop 'docker compose -f "$HOME/Projects/daw-dev/compose.yaml" stop'
alias daw-dev-status 'docker compose -f "$HOME/Projects/daw-dev/compose.yaml" ps --all --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"'
alias daw-dev-logs 'docker compose -f "$HOME/Projects/daw-dev/compose.yaml" logs --tail 100 -f'
alias daw-dev-help 'printf "%s\n" daw-dev-start daw-dev-start-all daw-dev-start-db daw-dev-stop daw-dev-status daw-dev-logs daw-dev-help'
```

Abre outra terminal ou executa `source ~/.config/fish/conf.d/my_aliases.fish` para activalos.

#### Bash ou Zsh (Linux, macOS ou Debian en WSL2)

Engade este bloque a `~/.bashrc` se usas Bash ou a `~/.zshrc` se usas Zsh. En macOS, se a túa
terminal abre Bash como shell de inicio de sesión, podes gardalo en `~/.bash_profile`.
**Na instalación WSL2 desta guía, substitúe `$HOME/Projects/daw-dev` por `$HOME/proxectos/daw-dev`.**

```bash
alias daw-dev-start='docker compose -f "$HOME/Projects/daw-dev/compose.yaml" up -d --no-deps web'
alias daw-dev-start-all='docker compose -f "$HOME/Projects/daw-dev/compose.yaml" up -d'
alias daw-dev-start-db='docker compose -f "$HOME/Projects/daw-dev/compose.yaml" up -d db web'
alias daw-dev-stop='docker compose -f "$HOME/Projects/daw-dev/compose.yaml" stop'
alias daw-dev-status='docker compose -f "$HOME/Projects/daw-dev/compose.yaml" ps --all --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"'
alias daw-dev-logs='docker compose -f "$HOME/Projects/daw-dev/compose.yaml" logs --tail 100 -f'
alias daw-dev-help='printf "%s\n" daw-dev-start daw-dev-start-all daw-dev-start-db daw-dev-stop daw-dev-status daw-dev-logs daw-dev-help'
```

Abre outra terminal ou executa `source ~/.bashrc`, `source ~/.zshrc` ou `source ~/.bash_profile`,
segundo o ficheiro que editaches.

#### PowerShell (Windows con Debian en WSL2)

En PowerShell definimos funcións para incluír os argumentos do comando. Estes atallos executan Docker
dentro de Debian, como na [guía do alumnado](docs/wsl2-alumnado.md), e non requiren Docker Desktop.
Substitúe `uxia` polo teu usuario de Debian; se usas outra distribución ou ruta, axústaas tamén.

```powershell
$script:DawDevCompose = '/home/uxia/proxectos/daw-dev/compose.yaml'
function daw-dev-start { wsl.exe -d Debian -- docker compose -f $script:DawDevCompose up -d --no-deps web @args }
function daw-dev-start-db { wsl.exe -d Debian -- docker compose -f $script:DawDevCompose up -d db web @args }
function daw-dev-start-all { wsl.exe -d Debian -- docker compose -f $script:DawDevCompose up -d @args }
function daw-dev-stop { wsl.exe -d Debian -- docker compose -f $script:DawDevCompose stop @args }
function daw-dev-status { wsl.exe -d Debian -- docker compose -f $script:DawDevCompose ps --all --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}' @args }
function daw-dev-logs { wsl.exe -d Debian -- docker compose -f $script:DawDevCompose logs --tail 100 -f @args }
function daw-dev-help { Write-Output 'daw-dev-start', 'daw-dev-start-all', 'daw-dev-start-db', 'daw-dev-stop', 'daw-dev-status', 'daw-dev-logs', 'daw-dev-help' }
```

Podes pegar o bloque na sesión actual. Para gardalo, engádeo ao teu
[perfil de PowerShell](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles):

```powershell
if (!(Test-Path -LiteralPath $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}
notepad $PROFILE
```

Garda o bloque nese ficheiro e abre outra terminal ou executa `. $PROFILE`.

#### PowerShell con Docker dispoñible directamente en Windows

Se xa usas Docker desde PowerShell (por exemplo, con Docker Desktop en modo de contedores Linux)
e tes o proxecto en Windows, garda **este bloque en lugar do anterior** no mesmo `$PROFILE`.
Axusta a ruta se o proxecto está noutro cartafol:

```powershell
$script:DawDevCompose = Join-Path $HOME 'Projects/daw-dev/compose.yaml'
function daw-dev-start { docker compose -f $script:DawDevCompose up -d --no-deps web @args }
function daw-dev-start-db { docker compose -f $script:DawDevCompose up -d db web @args }
function daw-dev-start-all { docker compose -f $script:DawDevCompose up -d @args }
function daw-dev-stop { docker compose -f $script:DawDevCompose stop @args }
function daw-dev-status { docker compose -f $script:DawDevCompose ps --all --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}' @args }
function daw-dev-logs { docker compose -f $script:DawDevCompose logs --tail 100 -f @args }
function daw-dev-help { Write-Output 'daw-dev-start', 'daw-dev-start-all', 'daw-dev-start-db', 'daw-dev-stop', 'daw-dev-status', 'daw-dev-logs', 'daw-dev-help' }
```

Unha vez cargado o bloque da túa shell, podes executar `daw-dev-start`, `daw-dev-start-all`, `daw-dev-status`
ou `daw-dev-stop` sen entrar no cartafol do proxecto. Docker debe estar instalado e dispoñible na
contorna onde se executan os comandos.

O instalador da [guía de Windows](docs/windows11-contedores.md) crea lanzadores cos mesmos
nomes `daw-dev-*` para PowerShell e CMD. Escolle os lanzadores ou as funcións de PowerShell segundo
onde teñas o proxecto. `daw-dev-start-all` arranca os mesmos tres servizos en todos os sistemas.

## Base de datos

Credenciais de exemplo por defecto (cámbianse no `.env`). Consérvanse os nomes `dwcs` da
contorna orixinal para manter compatibles os exercicios e as bases de datos existentes:

| Base de datos | Usuario | Contrasinal | Root       |
|---------------|---------|-------------|------------|
| `dwcs`        | `dwcs`  | `abc123.`   | `abc123.`  |

- **Dende PHP o servidor é `db`, non `localhost`.** As credenciais están tamén en variables de contorna:

  ```php
  $pdo = new PDO(
      'mysql:host=' . getenv('DB_HOST') . ';dbname=' . getenv('DB_NAME') . ';charset=utf8mb4',
      getenv('DB_USER'),
      getenv('DB_PASSWORD'),
      [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
  );
  ```

- **Dende o teu equipo** (DBeaver, HeidiSQL, extensión de VS Code…): `localhost`, porto `3306`.
  MySQL Workbench conecta, pero con MariaDB dá avisos e algunhas funcións fallan.
- **Scripts iniciais:** os `.sql` de `docker/mariadb/init/` execútanse por orde alfabética **só a primeira vez** que se crea a BD.
  Para volver executalos cun volume xestionado por Compose: `docker compose down -v && docker compose up -d`.
  Empeza sempre os teus `.sql` con `SET NAMES utf8mb4;`, porque se non os acentos gárdanse mal.
- Os datos persisten no volume `daw-dev_db_data` aínda que pares ou borres os contedores (sen `-v`).
  `DB_VOLUME_NAME` permite reutilizar un volume existente; `DB_VOLUME_EXTERNAL=true` evita que Compose
  o cree ou elimine. Consulta a [guía de migración](docs/renomeado-daw-dev.md) para o antigo `dwcs_db_data`.
- Se usas un volume externo, `down -v` non borra esa BD. Para probar unha BD baleira conservando a anterior,
  escolle outro `DB_VOLUME_NAME`, pon `DB_VOLUME_EXTERNAL=false` e recrea os contedores.

## Depurar con Xdebug

**VS Code no teu equipo:**

1. Abre a carpeta do proxecto (a raíz, non `www/`).
2. Pon un punto de interrupción nun `.php` de `www/`.
3. Pulsa **F5** (configuración «Escoitar Xdebug»).
4. Recarga a páxina no navegador: a execución detense no punto de interrupción.

Xdebug intenta conectar en **todas** as peticións (`start_with_request=yes`). Se VS Code non está escoitando non pasa nada: a páxina carga normal e sen avisos.

O modo cámbiase no `.env` sen reconstruír (despois executa `docker compose up -d`):

| `XDEBUG_MODE`    | Para que                                                      |
|------------------|---------------------------------------------------------------|
| `debug,develop`  | Depuración paso a paso + `var_dump` e erros con formato (por defecto) |
| `debug`          | Só depuración                                                 |
| `coverage`       | Cobertura de código para PHPUnit                              |
| `off`            | Desactivado (o máis rápido)                                   |

Se prefires depurar só cando o pidas, cambia `xdebug.start_with_request` a `trigger` en
`docker/php/conf.d/99-xdebug.ini`, reconstrúe a imaxe e usa a extensión do navegador «Xdebug helper».

## Dev Container (opcional)

Coa extensión **Dev Containers**: *F1 → Dev Containers: Reopen in Container*.
VS Code execútase dentro do contedor `web` co usuario `dev`, e tes PHP, Composer e `mysql` no terminal integrado sen `docker compose exec`.
A depuración funciona igual (F5). Xdebug conecta a `localhost` grazas a `.devcontainer/compose.devcontainer.yaml`.

## Problemas habituais

Primeiro executa `./scripts/comprobar.sh`: indica que parte falla e, en moitos casos, como arranxala.

| Síntoma | Solución |
|---------|----------|
| `port is already allocated` / `address already in use` | Outro programa usa ese porto (XAMPP, MySQL/MariaDB local, outro proxecto…). Párao ou cambia `WEB_PORT`, `DB_PORT` ou `PMA_PORT` no `.env`. |
| `SQLSTATE[HY000] [2002] No such file or directory` ou `Connection refused` | Dende PHP usa `host=db`, non `localhost` nin `127.0.0.1`. |
| Os puntos de interrupción non paran | Comproba que VS Code está escoitando (barra inferior laranxa) e que abriches a **raíz** do proxecto (o `pathMappings` apunta a `www/`). En Linux, revisa que o cortalumes permita o porto 9003 dende as redes de Docker. Para diagnosticar, pon `xdebug.log=/tmp/xdebug.log` e `xdebug.log_level=7` no `99-xdebug.ini`, reconstrúe e mira o log. |
| Os acentos saen mal (`Ã¡`) | Engade `charset=utf8mb4` no DSN de PDO e `SET NAMES utf8mb4;` nos `.sql`. Se os datos xa se gardaron mal, hai que volver cargalos. |
| Cambiei un `.sql` de `init/` e non se aplica | Só se executan coa BD baleira: `docker compose down -v && docker compose up -d`. |
| Ficheiros de `www/` propiedade de root (Linux) | Axusta `USER_UID`/`USER_GID` no `.env` e `docker compose build`. Para arranxar os xa creados: `sudo chown -R $USER: www`. |

## Estrutura

```
.
├── compose.yaml              # servizos: web, db, phpmyadmin
├── Dockerfile                # imaxe daw-dev (Apache)
├── .env.example              # variables configurables (portos, versións, credenciais, Xdebug)
├── docker/
│   ├── apache/daw-dev.conf      # ServerName, AllowOverride All (.htaccess)
│   ├── php/conf.d/
│   │   ├── 90-daw-dev.ini       # zona horaria, erros visibles, límites de subida, OPcache
│   │   └── 99-xdebug.ini     # configuración de Xdebug
│   └── mariadb/
│       ├── client/daw-dev.cnf   # os comandos `mysql`/`mariadb` conectan a `db` por defecto
│       └── init/             # scripts .sql iniciais
├── www/                      # ← O TEU CÓDIGO (DocumentRoot)
├── scripts/comprobar.sh      # comprobación automática da contorna
├── docs/                     # guías de Windows 11 + WSL2 (administración e alumnado)
├── wsl/                      # scripts de instalación para Windows 11 + WSL2
├── .github/workflows/ci.yml  # probas e publicación das imaxes en ghcr.io
├── .vscode/                  # launch.json (Xdebug) e extensións recomendadas
└── .devcontainer/            # configuración opcional de Dev Container
```

---

## Notas para o profesorado

- **Imaxe:** `php:8.5-apache` en Debian 13. As extensións instálanse con
  [`install-php-extensions`](https://github.com/mlocati/docker-php-extension-installer), que limpa as dependencias de compilación.
  Hai `bcmath`, `pdo_mysql`, `mysqli`, `intl`, `zip`, `gd` e `xdebug`, ademais de Composer 2. Para engadir máis, pon o nome na lista do `Dockerfile`.
- **Base de datos:** MariaDB en vez de MySQL. Ocupa menos (imaxe de ~340 MB fronte a ~810 MB, ~125 MB de RAM fronte a ~435 MB),
  e para o que se ve no módulo o comportamento é o mesmo: o DSN segue sendo `mysql:`, e `mysqli`, PDO e phpMyAdmin funcionan igual.
  A etiqueta `lts` colle a última versión de soporte longo. Cando saia unha LTS nova, `docker compose pull` actualiza a imaxe e MariaDB
  actualiza os datos existentes ao arrancar. Para fixar unha versión concreta: `MARIADB_VERSION=12.3` no `.env`.
- **Outra versión de PHP:** `PHP_VERSION=8.4` no `.env` e `docker compose up -d`. Como esa versión non está publicada,
  Compose constrúea co `Dockerfile`. Cada versión ten a súa etiqueta, así que se poden ter varias á vez.
- **PHP execútase co usuario `dev`**, co UID do anfitrión vía `APACHE_RUN_USER`. Así se evitan os problemas de permisos con subidas de ficheiros, `vendor/`, logs…
- **OPcache** está activo en PHP 8.5, pero con `revalidate_freq=0` e os cambios vense ao momento.
- **Imaxes publicadas e CI:** GitHub Actions ([`ci.yml`](.github/workflows/ci.yml)) executa `scripts/comprobar.sh`
  en cada cambio e en cada pull request. Se as probas pasan en `main`, publica
  `ghcr.io/miguelfm/daw-dev:8.5` e a ruta pública compatible `ghcr.io/miguelfm/dwcs-php:8.5`.
  Por defecto úsase a segunda para permitir descargas sen login: os paquetes novos de GHCR nacen privados
  ata que o propietario cambia a súa visibilidade. Tamén a reconstrúe cada luns para incorporar as actualizacións
  de seguridade de PHP e Debian.
  O alumnado descarga as imaxes en vez de compilalas: aforra minutos e evita fallos de rede no build.
  As imaxes publicadas usan o UID 1000.
- **Usar o teu propio repositorio:** fai un fork. O CI publica as imaxes en `ghcr.io/<o-teu-usuario>/daw-dev`.
  Cambia o valor por defecto de `DAW_DEV_IMAGE` en `compose.yaml`, e a URL en
  [docs/wsl2-alumnado.md](docs/wsl2-alumnado.md).
- **Credenciais:** son de exemplo e só para desenvolvemento local. Non hai que expoñer estes portos fóra do equipo.
