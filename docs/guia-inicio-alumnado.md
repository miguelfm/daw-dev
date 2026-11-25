# Contorno DAW Dev na aula e na casa

DAW Dev é un contorno de desenvolvemento PHP. Na aula funciona na túa conta de
Windows sen permisos de administración. Está formado por unha distribución
Linux de WSL2, `Debian-DAW`, con Docker, e tres contedores: `web` (Apache e
PHP 8.6 con Xdebug 3.6), `db` (MariaDB) e `phpmyadmin`.

O contedor `web` compórtase como a máquina virtual (MV) da aula: a raíz web
é `/home/ad/html`, Apache executa PHP como `www-data` e as directivas de PHP
son as mesmas.

O contorno instálase en cada conta e en cada computador. Noutro computador da
aula tes outra copia, que non comparte ficheiros nin bases de datos con esta:
para levar o traballo dun a outro, usa Git ou unha copia dos ficheiros.

Se vas preparar o teu computador, vai a [Instalar DAW Dev na casa](#instalar-daw-dev-na-casa).

## Activar o contorno

A primeira vez que o usas nun computador, no menú Inicio, escolle **DAW Dev
→ Activar DAW Dev**. Unha xanela amosa o progreso; tarda uns minutos e
remata con «DAW Dev está activado». Despois abre un terminal novo para que
as ordes `daw-*` estean dispoñibles.

Repetir a activación é seguro: conserva os teus ficheiros e as bases de
datos, e trae as ordes e os ficheiros do proxecto que cambiasen.

O usuario de Linux é `ad`, co contrasinal `abc123..`, como na MV. Pídeo
`sudo` en Debian. Se o cambias con `passwd`, a activación consérvao.

## Onde están os ficheiros

- **`www`** é a raíz web. O acceso directo «DAW - Proxectos (www)» do
  Escritorio abre o cartafol `\\wsl.localhost\Debian-DAW\home\ad\www`, que no
  contedor é `/home/ad/html`. O ficheiro `www/u3/t1/index.php` ábrese en
  `http://localhost/u3/t1/index.php`.
- **`angular`** garda os proxectos de Angular. O acceso directo «DAW -
  Proxectos (angular)» abre `\\wsl.localhost\Debian-DAW\home\ad\angular`.
- **`datos`** garda, como na MV, os ficheiros que unha aplicación le ou
  escribe fóra da raíz web. En Windows está en
  `\\wsl.localhost\Debian-DAW\home\ad\proxectos\daw-dev\datos`, e no
  contedor, en `/home/ad/datos`.

Apache executa PHP como `www-data`, que non pode escribir en `www` nin en
`datos`. Se unha tarefa necesita que PHP cree ficheiros nun directorio,
executa as ordes de permisos do enunciado no terminal do contedor, onde as
rutas son as mesmas ca na MV (véxase *Abrir un terminal de Linux*).

## Ordes diarias

Escríbense nun terminal de PowerShell ou CMD de Windows:

| Orde | Que fai |
|:-------------------------|:--------------------------------------------------------|
| `daw-start` | Arranca só o contedor `web` |
| `daw-start-db` | Arranca `web` e MariaDB |
| `daw-start-all` | Arranca `web`, MariaDB e phpMyAdmin |
| `daw-start-angular` | Arranca o contedor de Angular (DWCC) |
| `daw-code-angular` | Arranca o contedor de Angular e ábreo en Visual Studio Code |
| `daw-code-proxecto` | Arranca web, MariaDB e Angular e abre `angular` e `www` en Visual Studio Code |
| `daw-status` | Amosa os contedores, o seu estado e os portos |
| `daw-logs` | Segue os rexistros dos contedores; `Ctrl+C` remata |
| `daw-code` | Abre o proxecto en Visual Studio Code |
| `daw-stop` | Para todos os contedores; ficheiros e datos quedan |
| `daw-help` | Lista as ordes |

`daw-start` tarda uns segundos. A primeira vez que arranca MariaDB, crea as
bases de datos e tarda uns 20 segundos.

Ao rematar, `daw-stop` libera a memoria e os portos. Os ficheiros e as bases
de datos consérvanse para a próxima sesión.

O uso do contedor de Angular con Visual Studio Code, e como conectalo co
PHP do contedor web, está na guía *Angular con DAW Dev (DWCC)*. Para un
proxecto con Angular e Laravel, consulta a guía *Proxecto con cliente e
servidor en DAW Dev*.

## Servizos no navegador

| Servizo | Enderezo | Arranque |
|---|---|---|
| Web | `http://localhost/` | `daw-start` |
| phpMyAdmin | `http://localhost:8081/` | `daw-start-all` |
| MariaDB | `localhost`, porto `3306` | `daw-start-db` |

Só se pode acceder a eles desde o propio computador. MariaDB ten dous
usuarios, co mesmo contrasinal:

| Usuario | Contrasinal | Uso |
|---|---|---|
| `daw` | `abc123..` | Aplicacións; base de datos `dwcs` |
| `root` | `abc123..` | Administración |

Desde PHP, o servidor de bases de datos chámase `db`, non `localhost`. O
contedor ten os datos de conexión en variables de contorno, que o código
pode ler con `getenv('DB_HOST')`, `getenv('DB_NAME')`, `getenv('DB_USER')`
e `getenv('DB_PASSWORD')`.

## Abrir un terminal de Linux

Desde PowerShell, esta orde abre un terminal en `Debian-DAW`:

```powershell
wsl -d Debian-DAW --cd ~
```

Entras como `ad` no teu directorio persoal, onde está `www`. Aquí hai Docker
e o proxecto (`~/proxectos/daw-dev`), pero non PHP: PHP está no contedor.
Para entrar no contedor `web`, que ten que estar arrancado:

```bash
cd ~/proxectos/daw-dev
docker compose exec -u dev web bash
```

Entras como `dev` en `/var/www/html`, que é o mesmo directorio ca
`/home/ad/html`. Tes `php`, `composer`, `git`, o cliente `mariadb` e `nano`,
coas mesmas directivas de PHP ca Apache, e as rutas da MV: por exemplo,
`cd /home/ad/html/u3/t1`. Un `exit` sae do contedor e outro, de `Debian-DAW`.

::: warning

Sen `-u dev` entras como `root`, e os ficheiros que crees así quedan de
`root`: desde Windows non poderás gardar cambios neles.

:::

## Traballar con Visual Studio Code

Para programar dentro do contedor, coa súa versión de PHP e o seu terminal:

1. Executa `daw-code`. VS Code abre o proxecto,
   `\\wsl.localhost\Debian-DAW\home\ad\proxectos\daw-dev`.
2. Preme `F1` e escolle **Dev Containers: Reopen in Container**.
3. VS Code ábrese de novo dentro do contedor `web`, co proxecto en
   `/workspace` e o código en `/workspace/www`. O terminal integrado
   (`Ctrl+ñ`) xa é o do contedor, como `dev`.

Ao abrir o proxecto no contedor arrancan tamén MariaDB e phpMyAdmin, e ao
pechar VS Code páranse os contedores.

Xdebug só depura as peticións que o piden, como na MV:

1. Pon un punto de interrupción e preme `F5` coa configuración
   **Escoitar Xdebug**.
2. Abre a páxina engadindo `?XDEBUG_TRIGGER=1` ao enderezo, por exemplo
   `http://localhost/u3/t1/index.php?XDEBUG_TRIGGER=1`.

Xdebug conecta con VS Code cando este está dentro do contedor. Con VS Code
aberto en Windows, fóra del, podes editar os ficheiros, pero non depurar.

## Problemas habituais

- **`http://localhost/` non responde.** Mira `daw-status`: se `daw-dev-web`
  non está `Up`, executa `daw-start`.
- **phpMyAdmin non abre ou non conecta.** Arranca con `daw-start-all`.
- **Windows non recoñece `daw-start`.** Abre un terminal novo. Se segue sen
  recoñecela, ou se estás noutro computador, o contorno aínda non está
  activado nesa conta: escolle **DAW Dev → Activar DAW Dev** no menú Inicio.
- **A activación remata cun erro.** Avisa ao docente: o rexistro está en
  `%LOCALAPPDATA%\DAW-Aula`. Non a repitas mentres a xanela segue aberta.
- **PHP non pode escribir un ficheiro (`Permission denied`).** O directorio
  necesita os permisos que indica o enunciado: Apache é `www-data`.
- **Windows non deixa gardar un ficheiro.** Creouse como `root` dentro do
  contedor. Desde `~/proxectos/daw-dev`, devólvello a `dev`:

  ```bash
  docker compose exec web chown dev:dev /home/ad/html/u3/t1/f.php
  ```

## Instalar DAW Dev na casa

Os pasos seguintes instalan a rama `proxecto` de DAW Dev. Na casa, os
ficheiros web van en `www/` (no contedor, `/var/www/html`) e os de Angular
en `angular/`. Para levar unha práctica da aula á casa, usa Git ou copia
os seus ficheiros.

### Windows 11 con WSL2

1. En PowerShell como administrador, instala WSL e Debian. Reinicia Windows
   se cho pide. Se xa tes Debian en WSL, comproba con `wsl -l -v` que
   aparece coa versión 2. [Instrucións de Microsoft](https://learn.microsoft.com/windows/wsl/install/).

   ```powershell
   wsl --install -d Debian
   ```

2. Abre **Debian** desde o menú Inicio. Na primeira apertura crea o teu
   usuario e contrasinal de Linux. No terminal de Debian, descarga DAW Dev e
   instala Docker Engine e Compose co script do proxecto. Se xa tes Docker
   Engine e Compose dentro de Debian, podes saltar a última orde.

   ```bash
   sudo apt update
   sudo apt install -y git
   mkdir -p ~/proxectos
   cd ~/proxectos
   git clone -b proxecto https://github.com/miguelfm/daw-dev.git
   cd daw-dev
   sudo bash wsl/instalar-docker.sh
   ```

   O proxecto queda no disco de Debian, en `~/proxectos/daw-dev`. Despois de
   instalar Docker, pecha o terminal de Debian, executa `wsl --terminate Debian`
   en PowerShell e volve abrir Debian. Comproba que funciona:

   ```bash
   sudo systemctl enable --now docker
   docker compose version
   docker run --rm hello-world
   ```

3. En PowerShell, instala as ordes `daw-*` para a túa conta de Windows:

   ```powershell
   $proxecto = (wsl -d Debian --exec printenv HOME).Trim()
   $proxecto += '/proxectos/daw-dev'
   $rutaWindows = wsl -d Debian --exec wslpath -w $proxecto
   $script = Join-Path $rutaWindows 'wsl\install-daw-commands.ps1'
   $opcions = @(
       '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script
       '-Distribution', 'Debian', '-LinuxProjectPath', $proxecto
   )
   powershell.exe @opcions
   ```

   Abre outro terminal de PowerShell ou CMD e executa `daw-help`.

### Linux

1. Instala Git, Docker Engine e o complemento Docker Compose. Segue a guía
   da túa distribución e configura o acceso a Docker para a túa conta.
   Comproba nun terminal que funcionan `docker compose version` e
   `docker run --rm hello-world`. [Instalación de Docker Engine](https://docs.docker.com/engine/install/) ·
   [Configuración de Docker para o teu usuario](https://docs.docker.com/engine/install/linux-postinstall/).

2. Descarga DAW Dev e instala os lanzadores do teu usuario:

   ```bash
   mkdir -p ~/proxectos
   cd ~/proxectos
   git clone -b proxecto https://github.com/miguelfm/daw-dev.git
   cd daw-dev
   bash scripts/install-daw-commands.sh
   ```

   Se o terminal non atopa `daw-help`, executa a orde seguinte. Para
   conservala nos terminais novos de Bash, engádea a `~/.bashrc`.

   ```bash
   export PATH="$HOME/.local/bin:$PATH"
   daw-help
   ```

   Se a túa copia de DAW Dev é anterior ao instalador, podes usar os
   [atallos para Bash](../README.md#bash-ou-zsh-linux-macos-ou-debian-en-wsl2).

### Configurar e comprobar o primeiro arranque

Desde Debian en Windows, ou desde Linux, executa:

```bash
cd ~/proxectos/daw-dev
test -f .env || cp .env.example .env
```

Abre `.env` e cambia estas tres liñas para que os servizos se publiquen
só no teu computador:

```dotenv
WEB_PORT=127.0.0.1:80
PMA_PORT=127.0.0.1:8081
DB_PORT=127.0.0.1:3306
```

Executa `daw-start-all` e `daw-status` en PowerShell (Windows) ou no
terminal de Linux. A primeira vez descárganse as imaxes. Abre
<http://localhost/index.php> para verificar PHP e MariaDB. En
<http://localhost:8081> podes entrar en phpMyAdmin cos valores de
`DB_USER` e `DB_PASSWORD` do teu `.env`. Para parar a contorna
conservando os datos, executa `daw-stop`.

Para traballar con Visual Studio Code, instala o editor e a extensión
**Dev Containers** para PHP. En Windows, instala tamén a extensión **WSL**.
Con `daw-code` podes abrir o proxecto e escoller **Dev Containers: Reopen
in Container**.

Se vas usar Angular en Windows, prepara a súa imaxe desde o cartafol do
proxecto en Debian antes do primeiro `daw-code-angular`:

```bash
docker compose --profile angular build angular
```

En Linux, `daw-start-angular` e `daw-code-angular` preparan a imaxe se
fai falta. En ambos os sistemas, `daw-code-proxecto` abre os dous
cartafoles en VS Code, con acceso a PHP e a Angular.
