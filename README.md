# daw-dev

[![CI](https://github.com/miguelfm/daw-dev/actions/workflows/ci.yml/badge.svg)](https://github.com/miguelfm/daw-dev/actions/workflows/ci.yml)

Contorna Docker de desenvolvemento para **Desenvolvemento de Aplicacións Web (DAW)**.
Actualmente inclúe PHP e as ferramentas usadas no módulo **Desenvolvemento Web en Contorna Servidor (DWCS)**. Un só comando arranca PHP 8.6, servidor web, base de datos,
depurador e ferramentas, igual en Linux e en Windows 11 (WSL2). Fóra de Docker non hai que instalar PHP,
servidores nin bases de datos no equipo.

| Servizo    | Que é                                                  | URL / acceso                     |
|------------|--------------------------------------------------------|----------------------------------|
| `backend`  | PHP 8.6 + Apache, Xdebug 3.6.0alpha1, Composer, cliente MariaDB, git | <http://localhost> |
| `db`       | MariaDB (última LTS)                                   | `db:3306` (dende PHP) · `localhost:3306` (dende o equipo) |
| `db-admin` | phpMyAdmin: xestión web da base de datos               | <http://localhost:8081>          |

## Requisitos

- **Linux (Arch Linux, Debian, Ubuntu, Fedora...):** Docker Engine + plugin `compose`. O teu usuario debe pertencer ao grupo `docker` para executar sen `sudo` (ex. en Arch: `sudo pacman -S docker docker-compose`, `sudo systemctl enable --now docker.service`, `sudo usermod -aG docker $USER`).
- **Windows 11:** WSL2 con Debian e Docker Engine, sen Docker Desktop. Guías:
  [preparación dos equipos (administración)](docs/wsl2-administracion.md),
  [instalación e uso](docs/wsl2-alumnado.md),
  [lanzadores e acceso aos ficheiros](docs/windows11-contedores.md) e
  [guía rápida da aula](docs/guia-inicio-alumnado.md).
- **Aulas con contas persoais:** [despregamento remoto desde o profesor, distribución `linux`, execución paralela e soporte para aulas compartidas](docs/aula-windows11.md).
- **Xestión gráfica opcional:** [Portainer CE en Debian/WSL2](docs/wsl2-alumnado.md#portainer-ce-xestión-gráfica-opcional),
  para xestionar Docker desde o navegador en <https://localhost:9443>.
- VS Code coa extensión **PHP Debug** (`xdebug.php-debug`). Ao abrir o proxecto, VS Code propón as extensións recomendadas. Se desexas executar o editor dentro do contedor, require a extensión **Dev Containers** (`ms-vscode-remote.remote-containers`).

Para Angular (DWCC), consulta a [guía de uso](docs/guia-angular-alumnado.md) e o [procedemento para comparar o rendemento en WSL2 e VirtualBox](docs/rendemento-angular-wsl2-virtualbox.md).

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
./scripts/check.sh
```

> **Linux:** a imaxe publicada usa o UID 1000, o do primeiro usuario de case todas as distribucións. Se o teu é
> outro (comproba con `id`), pon `USER_UID` e `USER_GID` no `.env` e constrúe a túa con `docker compose build`.
> Así os ficheiros que crea PHP son teus e non doutro usuario.

### Actualizar a PHP 8.6 e á conta `ad`

Se no teu `.env` figura `PHP_VERSION=8.5`, comenta a liña para seguir a versión do
proxecto. Desde a raíz, descarga a imaxe pública e actualiza o backend:

```bash
docker compose pull backend
docker compose up -d --no-deps backend
docker compose exec -u ad backend php -v
```

A imaxe é `ghcr.io/miguelfm/daw-php:8.6`: o nome di o que contén e a etiqueta, a versión de PHP.
Ata o 27-11-2026 chamábase `dwcs-php:8.6-ad`; se só tes esa, `daw-start` pásaa ao nome novo
sen descargar nada, e a CI segue publicando o nome anterior. Se traballas cos cambios locais
ou tes un UID/GID personalizado, constrúe a imaxe con `docker compose build backend`.
Ao recrear `backend`, consérvanse `www/` e o volume de MariaDB. Se gardaches traballo
dentro do contedor fóra de `www/` ou de `~/daw`, cópiao ao proxecto antes de recrealo. Para os equipos da aula, segue o
[procedemento de actualización e carga sen Internet](docs/aula-windows11.md#actualizar-a-php-86-nos-equipos-da-aula).

## Comandos do día a día

O servidor web mostra por defecto a listaxe de ficheiros e subdirectorios en cada
cartafol, mesmo se contén `index.php`, `index.html` ou `index.txt`. Para executar un ficheiro, ábreo explicitamente: por exemplo,
<http://localhost/index.php> ou `http://localhost/exercicio/index.php`.
En Apache, un `.htaccess` pode sobrescribir este comportamento.

A configuración do servidor móntase desde `docker/apache/daw-dev.conf`. Para aplicar esta actualización
a un contedor existente, executa `daw-start` en Windows ou
`docker compose up -d --no-deps backend` en Debian. Non precisa reconstruír a imaxe.
Tras editar só este ficheiro de configuración, reinicia o backend con
`docker compose restart backend`.

En **Windows 11**, podes instalar os comandos `daw-*` no PATH do usuario para executar
`daw-start` (só servidor web), `daw-start-db` (BD e web),
`daw-start-all` (web, BD e phpMyAdmin), `daw-start-doc` (documentación sen conexión), `daw-stop`,
`daw-status`, `daw-logs` e `daw-code` (apertura directa en VS Code con soporte Dev Containers) desde PowerShell ou CMD.
`daw-web-root` amosa as rutas de Windows e Debian da raíz web de Apache.
`daw-web-root -Open` abre o cartafol no Explorador de ficheiros.
`daw-shell` entra no backend e `daw-wsl-shell` abre Debian no cartafol do proxecto.
Consulta a [guía de xestión de contedores en Windows 11](docs/windows11-contedores.md) e a
[comparación das rutas do cartafol web en Windows e Debian](docs/windows11-contedores.md#abrir-a-raíz-web-no-explorador-de-ficheiros).

| Para…                                   | Comando                                         |
|-----------------------------------------|-------------------------------------------------|
| Arrancar só PHP + Apache                | `docker compose up -d --no-deps backend`             |
| Arrancar a contorna completa / parar    | `docker compose up -d` / `docker compose stop`  |
| Ver estado, incluídos os parados        | `docker compose ps --all`                        |
| Ver erros de PHP e do servidor backend      | `docker compose logs -f backend`                    |
| Abrir unha shell no contedor            | `docker compose exec -u ad backend bash`           |
| Consola de MariaDB                      | `docker compose exec -u ad backend mysql -u dwcs -p dwcs` |
| Consola de MariaDB como root            | `docker compose exec db mariadb -u root -p`     |
| Composer                                | `docker compose exec -u ad backend composer require monolog/monolog` |
| Executar un script PHP por consola      | `docker compose exec -u ad backend php script.php` |
| Reconstruír tras cambiar Dockerfile/ini | `docker compose up -d --build`                  |
| Actualizar o servidor backend               | `docker compose pull backend && docker compose up -d --no-deps backend` |
| Comprobar que todo funciona             | `./scripts/check.sh`                        |
| Borrar contedores e volumes xestionados, **incluída a BD** | `docker compose down -v`             |

### Consola do backend

O contedor `backend-c` debe estar en marcha e o teu usuario debe poder executar Docker.
Se está parado, arráncao con `daw-start` se tes os atallos configurados, ou con
`docker compose up -d --no-deps backend` desde o cartafol do proxecto.

Desde ese cartafol, abre unha consola co usuario `ad`:

```bash
docker compose exec -u ad backend bash
```

Tamén podes entrar **desde calquera cartafol**, usando o nome fixo do contedor:

```bash
docker exec -it -u ad backend-c bash
```

[`docker exec`](https://docs.docker.com/reference/cli/docker/container/exec/) usa `-it` para abrir
unha consola interactiva. [`docker compose exec`](https://docs.docker.com/reference/cli/docker/compose/exec/)
xa activa ese modo por defecto e usa o nome do servizo (`backend`).

Dentro da shell estás en `/var/www/html`, o cartafol local definido por `WWW_DIR` (`www/` por defecto),
co usuario `ad`, que non ten contrasinal: `sudo` non o pide. Tes `php`, `composer` e `mysql` dispoñibles,
ademais de `nano`, `vi` e `vis` para editar ficheiros.

O prompt indica onde estás: `ad@backend:/var/www/html$`. Os nomes seguen o papel de cada
contedor; o servizo de Compose e o hostname (o prompt) son o mesmo nome, e o contedor engade
`-c`, para non coincidir con imaxes, ordes nin contedores doutros proxectos:

| Servizo e hostname | Contedor | Que é |
|---|---|---|
| `backend` | `backend-c` | PHP 8.6 e Apache (DWCS) |
| `db` | `db-c` | MariaDB |
| `db-admin` | `db-admin-c` | phpMyAdmin |
| `frontend` | `frontend-c` | Node.js e Angular (DWCC) |
| `doc-php` | `doc-php-c` | Manual de PHP |
| `doc-web` | `doc-web-c` | Referencia web: HTML, HTTP e CSS (agora de MDN) |
| `doc-laravel` | `doc-laravel-c` | Documentación de Laravel |

`docker compose exec backend bash` usa o servizo; `docker exec -it backend-c bash`, o contedor.
Na distribución de WSL da aula, o prompt leva o nome do computador, por exemplo `ad@A31EQ28:~/html$`.
Ata o 27-11-2026 os servizos eran `web`, `phpmyadmin`, `angular` e `doc-devdocs`, e os contedores
`daw-web`, `daw-db`…: `daw-start` retira os contedores anteriores ao arrancar.

Para abrir a consola **como root**:

```bash
docker exec -it -u root backend-c bash
```

Desde o proxecto tamén podes usar `docker compose exec -u root backend bash`.
Escribe `exit` para pechar a consola; o contedor segue funcionando.

#### Acceso desde outro equipo por SSH

A imaxe DAW Dev non inclúe un servidor SSH. Se o **equipo anfitrión** ten SSH habilitado e a túa
conta pode executar Docker, conéctate a ese equipo e abre a consola do contedor:

```bash
ssh usuario@equipo
docker exec -it -u ad backend-c bash
```

Substitúe `usuario@equipo` polo usuario e o nome ou IP do anfitrión. O segundo comando execútase
na sesión remota, sobre o Docker dese equipo. Un `exit` volve á consola do anfitrión;
outro `exit` pecha a sesión SSH.

En Windows con Docker dentro de WSL2, executa os comandos Docker na terminal de Debian ou usa
o [acceso desde PowerShell ou CMD](docs/windows11-contedores.md#consola-do-backend).

### Atallos daw para a terminal

En Linux e macOS podes instalar os lanzadores para Bash, Zsh e Fish desde a raíz do proxecto
(require Bash, Python 3 e, para Angular, o cliente OpenSSH):

```bash
bash scripts/install-daw-commands.sh
```

Abre unha terminal nova e executa `daw-help`. `daw-start` inicia só o backend;
`daw-shell` abre a súa terminal e `daw-web-root` amosa a ruta nativa da raíz web.
`daw-start-frontend` prepara a chave SSH persoal
e a conexión `dwcc-angular`, e inicia só Angular. `daw-stop` para tamén Angular.
`daw-code` abre o proxecto no perfil `DWCS - PHP` de VS Code ou, se a raíz web ten o seu
propio `.devcontainer` (na aula, `~/html`; ou cun `WWW_DIR` fóra do proxecto), a raíz web; para traballar dentro
do contedor, usa **Dev Containers: Reopen in Container**.
Se xa tes un publicador persoal `daw-publicar`, o instalador consérvao.

Estes atallos permiten controlar a contorna desde calquera cartafol. Escolle o bloque correspondente
á túa shell e axusta a ruta ao lugar onde descargaches o proxecto. Os nomes usan guións en
todos os sistemas, tamén en PowerShell e CMD. O prefixo anterior `dwcs-` pasa a ser `daw-`;
por exemplo, `dwcs-start` pasa a chamarse `daw-start`.
Se xa tiñas os atallos configurados, substitúe as definicións antigas polas novas e abre outra
terminal para cargar os nomes actualizados.

| Atallo | Que fai |
|--------|---------|
| `daw-start` | Arranca só o backend (`backend-c`), sen iniciar a base de datos nin phpMyAdmin. |
| `daw-start-all` | Arranca `backend`, `db` e `db-admin`, como `docker compose up -d`. |
| `daw-start-db` | Arranca a base de datos e o backend. |
| `daw-start-doc` | Arranca a documentación sen conexión do proxecto [daw-doc](https://github.com/miguelfm/daw-doc): manual de PHP en <http://localhost:8080/>, a referencia de HTML, HTTP e CSS de MDN en <http://localhost:5042/> e Laravel en <http://localhost:8088/>. |
| `daw-stop` | Para os contedores da contorna con `stop`, conservando os contedores e os datos. |
| `daw-stop-all` | Para todos os contedores: desenvolvemento, documentación sen conexión e Angular. |
| `daw-stop-doc` | Para só os servizos da documentación sen conexión (`daw-doc`). |
| `daw-status` | Mostra unha táboa compacta co nome, estado e portos dos contedores existentes da contorna, incluídos os parados. |
| `daw-logs` | Mostra as últimas 100 liñas de logs por servizo e segue as novas; `Ctrl+C` sae da consulta. |
| `daw-shell` | Abre Bash no backend como `ad`. `daw-web-shell` segue funcionando como alias. |
| `daw-wsl-shell` | Desde Windows, abre Debian no cartafol do proxecto. En Linux ou macOS xa estás no sistema anfitrión ao abrir o terminal. |
| `daw-web-root` | Amosa a ruta nativa en Linux e macOS. En Windows con WSL amosa a ruta do Explorador seguida da de Debian. |
| `daw-code` | Abre o proxecto en VS Code con soporte e integración completa para Dev Containers. |
| `daw-help` | Mostra os comandos dispoñibles. |

`daw-start` usa [`--no-deps`](https://docs.docker.com/reference/cli/docker/compose/up/) porque `backend` ten
unha dependencia de `db`. Úsao cando traballes con PHP sen base de datos; para os exercicios con BD
ou para que a comprobación completa saia en verde, usa `daw-start-all`. Se xa hai outros contedores
en marcha, `daw-start` déixaos funcionando.

`daw-status` usa [`ps --all`](https://docs.docker.com/reference/cli/docker/compose/ps/):
non mostra servizos cuxos contedores
aínda non se crearon ou xa se eliminaron.

#### Fish (Linux ou macOS)

Engade este bloque a `~/.config/fish/conf.d/my_aliases.fish` (crea o cartafol e o ficheiro se non existen):

```fish
alias daw-start 'docker compose -f "$HOME/Projects/daw-dev/compose.yaml" up -d --no-deps backend'
alias daw-start-all 'docker compose -f "$HOME/Projects/daw-dev/compose.yaml" up -d'
alias daw-start-db 'docker compose -f "$HOME/Projects/daw-dev/compose.yaml" up -d db backend'
alias daw-start-doc 'docker compose -f "$HOME/Projects/daw-dev/compose.yaml" --profile doc up -d doc-php doc-web doc-laravel'
alias daw-stop 'docker compose -f "$HOME/Projects/daw-dev/compose.yaml" --profile doc --profile frontend stop'
alias daw-stop-all 'docker compose -f "$HOME/Projects/daw-dev/compose.yaml" --profile doc --profile frontend stop'
alias daw-stop-doc 'docker compose -f "$HOME/Projects/daw-dev/compose.yaml" --profile doc stop doc-php doc-web doc-laravel'
alias daw-status 'docker compose -f "$HOME/Projects/daw-dev/compose.yaml" ps --all --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"'
alias daw-logs 'docker compose -f "$HOME/Projects/daw-dev/compose.yaml" --profile doc --profile frontend logs --tail 100 -f'
alias daw-shell 'docker compose -f "$HOME/Projects/daw-dev/compose.yaml" exec -u ad backend bash'
alias daw-help 'printf "%s\n" daw-start daw-start-all daw-start-db daw-start-doc daw-stop daw-stop-all daw-stop-doc daw-status daw-logs daw-shell daw-help'
```

Abre outra terminal ou executa `source ~/.config/fish/conf.d/my_aliases.fish` para activalos.

#### Bash ou Zsh (Linux, macOS ou Debian en WSL2)

Engade este bloque a `~/.bashrc` se usas Bash ou a `~/.zshrc` se usas Zsh. En macOS, se a túa
terminal abre Bash como shell de inicio de sesión, podes gardalo en `~/.bash_profile`.
**Na instalación WSL2 desta guía, substitúe `$HOME/Projects/daw-dev` por `$HOME/daw`.**

```bash
alias daw-start='docker compose -f "$HOME/Projects/daw-dev/compose.yaml" up -d --no-deps backend'
alias daw-start-all='docker compose -f "$HOME/Projects/daw-dev/compose.yaml" up -d'
alias daw-start-db='docker compose -f "$HOME/Projects/daw-dev/compose.yaml" up -d db backend'
alias daw-start-doc='docker compose -f "$HOME/Projects/daw-dev/compose.yaml" --profile doc up -d doc-php doc-web doc-laravel'
alias daw-stop='docker compose -f "$HOME/Projects/daw-dev/compose.yaml" --profile doc --profile frontend stop'
alias daw-stop-all='docker compose -f "$HOME/Projects/daw-dev/compose.yaml" --profile doc --profile frontend stop'
alias daw-stop-doc='docker compose -f "$HOME/Projects/daw-dev/compose.yaml" --profile doc stop doc-php doc-web doc-laravel'
alias daw-status='docker compose -f "$HOME/Projects/daw-dev/compose.yaml" ps --all --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"'
alias daw-logs='docker compose -f "$HOME/Projects/daw-dev/compose.yaml" --profile doc --profile frontend logs --tail 100 -f'
alias daw-shell='docker compose -f "$HOME/Projects/daw-dev/compose.yaml" exec -u ad backend bash'
alias daw-help='printf "%s\n" daw-start daw-start-all daw-start-db daw-start-doc daw-stop daw-stop-all daw-stop-doc daw-status daw-logs daw-shell daw-help'
```

Abre outra terminal ou executa `source ~/.bashrc`, `source ~/.zshrc` ou `source ~/.bash_profile`,
segundo o ficheiro que editaches.

#### PowerShell (Windows con Debian en WSL2)

En PowerShell definimos funcións para incluír os argumentos do comando. Estes atallos executan Docker
dentro de Debian, como na [guía do alumnado](docs/wsl2-alumnado.md), e non requiren Docker Desktop.
Substitúe `uxia` polo teu usuario de Debian; se usas outra distribución ou ruta, axústaas tamén.
Para usar `daw-web-root` ou `daw-wsl-shell`, instala [os lanzadores de Windows](docs/windows11-contedores.md#instalar-os-comandos-no-path-do-usuario).

```powershell
$script:DawCompose = '/home/uxia/daw/compose.yaml'
function daw-start { wsl.exe -d Debian -- docker compose -f $script:DawCompose up -d --no-deps backend @args }
function daw-start-db { wsl.exe -d Debian -- docker compose -f $script:DawCompose up -d db backend @args }
function daw-start-all { wsl.exe -d Debian -- docker compose -f $script:DawCompose up -d @args }
function daw-start-doc { wsl.exe -d Debian -- docker compose -f $script:DawCompose --profile doc up -d doc-php doc-web doc-laravel @args }
function daw-stop { wsl.exe -d Debian -- docker compose -f $script:DawCompose --profile doc --profile frontend stop @args }
function daw-stop-all { wsl.exe -d Debian -- docker compose -f $script:DawCompose --profile doc --profile frontend stop @args }
function daw-stop-doc { wsl.exe -d Debian -- docker compose -f $script:DawCompose --profile doc stop doc-php doc-web doc-laravel @args }
function daw-status { wsl.exe -d Debian -- docker compose -f $script:DawCompose ps --all --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}' @args }
function daw-logs { wsl.exe -d Debian -- docker compose -f $script:DawCompose --profile doc --profile frontend logs --tail 100 -f @args }
function daw-shell { wsl.exe -d Debian -- docker compose -f $script:DawCompose exec -u ad backend bash @args }
function daw-help { Write-Output 'daw-start', 'daw-start-all', 'daw-start-db', 'daw-start-doc', 'daw-stop', 'daw-stop-all', 'daw-stop-doc', 'daw-status', 'daw-logs', 'daw-shell', 'daw-help' }
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
$script:DawCompose = Join-Path $HOME 'Projects/daw-dev/compose.yaml'
function daw-start { docker compose -f $script:DawCompose up -d --no-deps backend @args }
function daw-start-db { docker compose -f $script:DawCompose up -d db backend @args }
function daw-start-all { docker compose -f $script:DawCompose up -d @args }
function daw-start-doc { docker compose -f $script:DawCompose --profile doc up -d doc-php doc-web doc-laravel @args }
function daw-stop { docker compose -f $script:DawCompose --profile doc --profile frontend stop @args }
function daw-stop-all { docker compose -f $script:DawCompose --profile doc --profile frontend stop @args }
function daw-stop-doc { docker compose -f $script:DawCompose --profile doc stop doc-php doc-web doc-laravel @args }
function daw-status { docker compose -f $script:DawCompose ps --all --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}' @args }
function daw-logs { docker compose -f $script:DawCompose --profile doc --profile frontend logs --tail 100 -f @args }
function daw-shell { docker compose -f $script:DawCompose exec -u ad backend bash @args }
function daw-help { Write-Output 'daw-start', 'daw-start-all', 'daw-start-db', 'daw-start-doc', 'daw-stop', 'daw-stop-all', 'daw-stop-doc', 'daw-status', 'daw-logs', 'daw-shell', 'daw-help' }
```

Unha vez cargado o bloque da túa shell, podes executar `daw-start`, `daw-start-all`, `daw-status`
ou `daw-stop` sen entrar no cartafol do proxecto. Docker debe estar instalado e dispoñible na
contorna onde se executan os comandos.

Ten en conta que estas definicións manuais chaman directamente a `docker compose` sen pasar por
`scripts/daw.sh`: polo tanto, non inclúen a migración automática dun ficheiro `.env` anterior
ao 24-11-2026 (se tes un `.env` antigo co contrasinal por defecto anterior, actualízao a man ou usa
os lanzadores do instalador).

O instalador da [guía de Windows](docs/windows11-contedores.md) crea lanzadores cos mesmos
nomes `daw-*` para PowerShell e CMD. Escolle os lanzadores ou as funcións de PowerShell segundo
onde teñas o proxecto. `daw-start-all` arranca os mesmos tres servizos en todos os sistemas.

## Base de datos

Credenciais de exemplo por defecto (cámbianse no `.env`). Consérvanse os nomes `dwcs` da
contorna orixinal para manter compatibles os exercicios e as bases de datos existentes:

| Base de datos | Usuario | Contrasinal | Root       |
|---------------|---------|-------------|------------|
| `dwcs`        | `dwcs`  | `abc123..`  | `abc123..` |

O contrasinal é o mesmo da MV da aula. Un `.env` ou un volume de MariaDB anteriores
ao 24-11-2026 levan o contrasinal por defecto anterior: as ordes `daw-start` cambian
o do `.env`, e MariaDB, ao arrancar, o dos usuarios `root` e `dwcs` que aínda o teñan
(`docker/mariadb/healthcheck.sh`). Un contrasinal posto a man non se toca.

As contas de Linux non teñen contrasinal: no contedor, `ad` usa `sudo` sen contrasinal;
na distribución `linux` da aula, a conta `ad` está bloqueada e non ten `sudo`.

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

## Dev Container e integración con VS Code

Para alternar entre Programación con Java e DWCS con PHP, consulta a
[guía de perfís separados de VS Code](docs/vscode-perfis.md).

Coa extensión **Dev Containers** (`ms-vscode-remote.remote-containers`): *F1 → Dev Containers: Reopen in Container*.
VS Code execútase dentro do contedor `backend` co usuario `ad`, e tes PHP, Composer, Git e o cliente `mysql` no terminal integrado sen `docker compose exec`.
A depuración funciona igual (F5). Xdebug conecta a `localhost` grazas a `.devcontainer/compose.devcontainer.yaml`.
A directiva `build: !reset null` fai que Dev Containers reutilice a imaxe web local ou descargue `ghcr.io/miguelfm/daw-php:8.6` de GHCR.

### Alternar entre `daw-start` e o Dev Container

O contedor `backend-c` ten dúas definicións. A de `daw-start` serve a web e deixa que Xdebug
conecte co VS Code do anfitrión. A do Dev Container engade o espazo de traballo (o proxecto en `~/daw` ou, na aula, o código
web en `~/html`), Xdebug cara a `localhost` e a entrada de Dev Containers. Dev Containers usa sen recrealo calquera contedor `backend` que xa
exista, e Compose recrea o dun Dev Container. Sen máis, abrirías o contedor de `daw-start`, sen
o espazo de traballo, ou `daw-start` pecharía a xanela de VS Code. Os scripts encárganse de evitalo:

| Situación | Que pasa |
|---|---|
| Abres o Dev Container e `backend-c` é de `daw-start` | Retírase e Dev Containers créao coa súa definición |
| Abres o Dev Container e o seu contedor é anterior a un cambio dos ficheiros que o definen (os `compose*.yaml` e o `devcontainer.json` que usou, e `.env`) ou da imaxe web | Retírase e créase de novo |
| `daw-start`, `daw-start-db` ou `daw-start-all` co Dev Container aberto | O backend non se toca; arrancan só a base de datos e phpMyAdmin |
| `scripts/check.sh` co Dev Container aberto | Compróbao sen recrealo, e Xdebug dentro do contedor, onde escoita o VS Code do contedor |
| `daw-stop` ou `daw-stop-all` co Dev Container aberto | Paran tamén `backend-c`, e avisan: VS Code amosa «Cannot reconnect. Please reload the window.» ata que se reabre con **Reopen in Container** |
| `daw-start` despois de pechar a xanela do Dev Container | Recrea `backend-c` coa definición de `daw-start` |
| `daw-start` con `backend-c` en marcha e un ficheiro montado substituído (por exemplo `docker/apache/daw-dev.conf` tras un `git pull`) | Recrea `backend-c`: Docker monta o ficheiro polo seu inodo e seguiría co anterior |

Ao abrir o Dev Container, a comprobación faina o `initializeCommand` de
`.devcontainer/devcontainer.json` (na aula, `~/html/.devcontainer/devcontainer.json`) con
`scripts/daw.sh prepare-devcontainer`, que precisa Bash, Python 3 e Docker. Se falta algún, avisa
e Dev Containers abre igual o contedor que atope. Os ficheiros que definiron o contedor sáense
das súas etiquetas, así que vale igual coas dúas disposicións. Retirar o contedor conserva
`www/`, o volume da base de datos e os demais volumes. Pérdese só o que gardases dentro do
contedor fóra das montaxes.

**F1 → Dev Containers: Rebuild Container** segue dispoñible para forzar un contedor novo. Se aparece `unable to find user ad`, comproba que a imaxe usada inclúe ese usuario antes de reconstruír. O perfil de terminal de Linux detecta se xa está dentro do contedor e abre Bash directamente.

- **En Linux (Arch Linux, Debian, Ubuntu...):**
  - Funciona de forma 100% nativa comunicándose co socket `/var/run/docker.sock`, con montaxes nativas de disco e sen sobrecarga de virtualización.
  - O usuario `ad` (`UID:GID 1000:1000`) coincide co primeiro usuario habitual do sistema anfitrión, polo que non hai conflitos de permisos nos ficheiros creados.
  - O ficheiro `.vscode/settings.json` está preparado para ambos os sistemas: a opción de WSL ignórase en Linux automaticamente, e disponse do perfil de terminal `"Contedor DAW Dev"` se se usa VS Code no anfitrión sen Dev Containers.
- **En Windows 11 con WSL2 (sen Docker Desktop):**
  - O proxecto vén preconfigurado en `.vscode/settings.json` para delegar as accións de Dev Containers na distribución Debian de WSL (`executeInWSL: true`).
  - No despregamento de aula, as extensións de VS Code (`ms-vscode-remote.remote-containers` e `ms-vscode-remote.remote-wsl`) instálanse automaticamente e disponse da orde `daw-code` para abrir o proxecto directamente e facer clic en *«Reopen in Container»*.
  - Se se traballa con VS Code directamente en Windows sen Dev Containers, o perfil predeterminado de terminal de Windows abre tamén a shell do contedor `backend-c`.
  - Consulta a [guía de integración con VS Code en Windows 11](docs/windows11-contedores.md#integración-con-vs-code-en-windows-11) e a [guía de aula Windows 11](docs/aula-windows11.md).



## Problemas habituais

Se en Windows `localhost` funciona ao arrancar e deixa de responder ao pouco,
consulta [o peche de WSL tras o arranque](docs/windows11-contedores.md#localhost-deixa-de-responder-pouco-despois-do-arranque).
A guía inclúe o diagnóstico, a protección dos lanzadores e a proba de permanencia.

Primeiro executa `./scripts/check.sh`: indica que parte falla e, en moitos casos, como arranxala.

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
├── compose.yaml              # servizos: backend, db, db-admin, frontend e doc-*
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
├── www/                      # ← O TEU CÓDIGO (DocumentRoot; carpetas locais como dwcs/ ignoradas en git)
├── scripts/                  # comandos daw-* de Linux, check.sh (comprobación da contorna) e scripts que se executan en WSL
├── docs/                     # guías de Windows 11 + WSL2 (administración e alumnado)
├── windows/                  # comandos daw-* de Windows e instalación de WSL2
│   └── classroom/            # despregamento na aula (paquete, WinRM, ficheiros do proxecto)
├── .github/workflows/ci.yml  # probas e publicación das imaxes en ghcr.io
├── .vscode/                  # launch.json (Xdebug) e extensións recomendadas
└── .devcontainer/            # configuración opcional de Dev Container
```

---

## Notas para o profesorado

- **Imaxe:** `php:8.6-apache` en Debian 13. As extensións instálanse con
  [`install-php-extensions`](https://github.com/mlocati/docker-php-extension-installer), que limpa as dependencias de compilación.
  Hai `bcmath`, `mbstring`, `pdo_mysql`, `mysqli`, `intl`, `zip`, `gd` e Xdebug `3.6.0alpha1`, ademais de Composer 2. Xdebug compílase desde a etiqueta da versión preliminar en GitHub. `mbstring` instálase á parte porque a imaxe oficial de PHP 8.6 xa non a compila, como facía a 8.5.
- **Base de datos:** MariaDB en vez de MySQL. Ocupa menos (imaxe de ~340 MB fronte a ~810 MB, ~125 MB de RAM fronte a ~435 MB),
  e para o que se ve no módulo o comportamento é o mesmo: o DSN segue sendo `mysql:`, e `mysqli`, PDO e phpMyAdmin funcionan igual.
  A etiqueta `lts` colle a última versión de soporte longo. Cando saia unha LTS nova, `docker compose pull` actualiza a imaxe e MariaDB
  actualiza os datos existentes ao arrancar. Antes de cambiar de serie con datos que
  queiras conservar, fai unha copia da base de datos e proba a actualización nun
  volume separado. Para quedar na serie 12.3 e recibir os seus parches, usa
  `MARIADB_VERSION=12.3` no `.env`.
- **Outra versión de PHP:** `PHP_VERSION=8.4` no `.env` e `docker compose up -d`. Como esa versión non está publicada,
  Compose constrúea co `Dockerfile`. Cada versión ten a súa etiqueta, así que se poden ter varias á vez.
- **En Compose base, Apache executa PHP como `ad`**, co UID indicado ao construír a imaxe. Na aula, o override executa Apache como `www-data`, igual ca na MV.
- **OPcache** está activo con `revalidate_freq=0` para que os cambios se vexan ao momento.
- **Imaxes publicadas e CI:** GitHub Actions ([`ci.yml`](.github/workflows/ci.yml)) executa `scripts/check.sh`
  en cada cambio e en cada pull request. Se as probas pasan en `main`, publica
  `ghcr.io/miguelfm/daw-php:8.6` e `ghcr.io/miguelfm/daw-angular:22`, públicas e sen login. Para os
  paquetes e proxectos anteriores publica tamén os nomes de antes (`dwcs-php:8.6-ad`, `daw-dev:8.6-ad` e
  `dwcc-angular:22`). Nun fork, os paquetes novos de GHCR poden nacer privados: comproba a súa
  visibilidade. Tamén a reconstrúe cada luns para incorporar as actualizacións
  de seguridade de PHP e Debian.
  O alumnado descarga as imaxes en vez de compilalas: aforra minutos e evita fallos de rede no build.
  As imaxes publicadas usan o UID 1000.
- **Usar o teu propio repositorio:** fai un fork. O CI publica as imaxes en `ghcr.io/<o-teu-usuario>/daw-php`.
  Pon `DAW_PHP_IMAGE=ghcr.io/<o-teu-usuario>/daw-php` no `.env` (antes `DAW_DEV_IMAGE`), e cambia a URL en
  [docs/wsl2-alumnado.md](docs/wsl2-alumnado.md).
- **Credenciais:** son de exemplo e só para desenvolvemento local. Non hai que expoñer estes portos fóra do equipo.

## Scripts de aula

Os scripts de `windows/classroom/` preparan o paquete DAW Dev e despregano nos postos por WinRM: validan o
paquete e o modelo, conservan o modo baixo demanda, verifican o IDE e esperan o resultado real da tarefa do
alumno. Desde o 26/11/2026 a instalación DAW Dev (distribución `linux`; desde o 27/11/2026, a contorna en
`~/.daw` e o código web en `~/html`) substitúe sen migración a anterior: os paquetes antigos non se reutilizan. Véxase o [README dos scripts de aula](windows/classroom/README.md).

Ver [solucións, actualización de paquetes e recuperación](docs/aula-correccions-20261113.md), [despregamento na aula 34 do 18/11/2026](docs/aula-despregamento-20261118.md), [despregamento na aula 31 do 19/11/2026](docs/aula-despregamento-20261119-aula31.md), [guía da aula](docs/aula-windows11.md), [guía do alumnado](docs/guia-inicio-alumnado.md), [Angular para DWCC](docs/guia-angular-alumnado.md) e as probas `tests/classroom.ps1`, `tests/migration.py` e `tests/overlay.py`.
