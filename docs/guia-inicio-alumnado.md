# Contorno DAW Dev na aula

DAW Dev é un contorno de desenvolvemento PHP que funciona na túa conta de
Windows sen permisos de administración. Está formado por unha distribución
Linux de WSL2, `Debian`, con Docker, e tres contedores: `web` (Apache e
PHP 8.6 con Xdebug 3.6), `db` (MariaDB) e `phpmyadmin`.

O contedor `web` compórtase como a máquina virtual (MV) da aula: a raíz web
é `/home/ad/html`, Apache executa PHP como `www-data` e as directivas de PHP
son as mesmas.

O contorno instálase en cada conta e en cada computador. Noutro computador da
aula tes outra copia, que non comparte ficheiros nin bases de datos con esta:
para levar o traballo dun a outro, usa Git ou unha copia dos ficheiros.

## Activar o contorno

A primeira vez que o usas nun computador, no menú Inicio, escolle **DAW Dev
→ Activar DAW Dev**. Unha xanela amosa o progreso; tarda uns minutos e
remata con «DAW Dev está activado». Despois abre un terminal novo para que
as ordes `daw-*` estean dispoñibles.

Repetir a activación é seguro: conserva os teus ficheiros e as bases de
datos, e trae as ordes e os ficheiros do proxecto que cambiasen.

## Onde están os ficheiros

- **`www`** é a raíz web. O acceso directo «DAW - Proxectos (www)» do
  Escritorio abre `\\wsl.localhost\Debian\home\ad\proxectos\daw-dev\www`.
  Tamén podes abrilo con `daw-web-root -Open`. No contedor é `/home/ad/html`.
  O ficheiro `www/u3/t1/index.php` ábrese en
  `http://localhost/u3/t1/index.php`.
- **`datos`** garda, como na MV, os ficheiros que unha aplicación le ou
  escribe fóra da raíz web. En Windows está en
  `\\wsl.localhost\Debian\home\ad\proxectos\daw-dev\datos`, e no
  contedor, en `/home/ad/datos`.

Apache executa PHP como `www-data`, que non pode escribir en `www` nin en
`datos`. Se unha tarefa necesita que PHP cree ficheiros nun directorio,
executa as ordes de permisos do enunciado no terminal do contedor, onde as
rutas son as mesmas ca na MV (véxase *Abrir un terminal de Linux*).

## Ordes diarias

Escríbense nun terminal de PowerShell ou CMD de Windows:

| Orde | Que fai |
|---|---|
| `daw-start` | Arranca só o contedor `web` |
| `daw-start-db` | Arranca `web` e MariaDB |
| `daw-start-all` | Arranca `web`, MariaDB e phpMyAdmin |
| `daw-start-angular` | Arranca o contedor de Angular (DWCC) |
| `daw-start-doc` | Arranca a documentación sen conexión |
| `daw-status` | Amosa os contedores, o seu estado e os portos |
| `daw-logs` | Segue os rexistros dos contedores; `Ctrl+C` remata |
| `daw-code` | Abre o proxecto en Visual Studio Code |
| `daw-web-root -Open` | Abre a raíz web no Explorador |
| `daw-wsl-shell` | Abre Debian no cartafol do proxecto |
| `daw-web-shell` | Abre a terminal do contedor de Apache e PHP |
| `daw-stop` | Para todos os contedores; ficheiros e datos quedan |
| `daw-help` | Lista as ordes |

`daw-start` tarda uns segundos. A primeira vez que arranca MariaDB, crea as
bases de datos e tarda uns 20 segundos.

Ao rematar, `daw-stop` libera a memoria e os portos. Os ficheiros e as bases
de datos consérvanse para a próxima sesión.

O uso do contedor de Angular, coa conexión de VS Code por SSH, está na
guía *Angular con DAW Dev (DWCC)*.

## Servizos no navegador

| Servizo | Enderezo | Arranque |
|---|---|---|
| Web | `http://localhost/` | `daw-start` |
| phpMyAdmin | `http://localhost:8081/` | `daw-start-all` |
| MariaDB | `localhost`, porto `3306` | `daw-start-db` |
| Manual de PHP | `http://localhost:8080/` | `daw-start-doc` |
| DevDocs (HTML e CSS) | `http://localhost:5042/` | `daw-start-doc` |
| Documentación de Laravel | `http://localhost:8088/` | `daw-start-doc` |

Só se pode acceder a eles desde o propio computador. MariaDB ten dous
usuarios, co mesmo contrasinal:

| Usuario | Contrasinal | Uso |
|---|---|---|
| `dwcs` | `abc123..` | Aplicacións; base de datos `dwcs` |
| `root` | `abc123..` | Administración |

Desde PHP, o servidor de bases de datos chámase `db`, non `localhost`. O
contedor ten os datos de conexión en variables de contorno, que o código
pode ler con `getenv('DB_HOST')`, `getenv('DB_NAME')`, `getenv('DB_USER')`
e `getenv('DB_PASSWORD')`.

## Abrir un terminal de Linux

Desde PowerShell ou CMD, estas ordes abren terminais en sitios distintos:

```powershell
daw-wsl-shell
daw-web-shell
```

`daw-wsl-shell` abre Debian no proxecto (`~/proxectos/daw-dev`). Aquí podes
usar Docker e Git ou consultar `curl --manual`. Funciona tamén con Docker parado.

`daw-web-shell` entra no contedor web como `ad`. A raíz web da aula é
`/home/ad/html`. Aquí tes PHP e Composer, e podes executar as tarefas que
usan as rutas da máquina virtual da aula. Arranca o contedor con `daw-start`
antes de entrar. Escribe `exit` para volver á terminal anterior.

## Contrasinais

Ningunha das contas de Linux de DAW Dev ten contrasinal. É un cambio
respecto da MV da aula, onde `ad` ten o contrasinal `abc123..` e `sudo`
pídeo:

| Onde | Conta | Contrasinal |
|---|---|---|
| Contedor `web` | `ad` | Ningún: `sudo` non o pide |
| Debian de WSL | `ad` | Ningún, e a conta non ten `sudo` |
| MariaDB | `dwcs` e `root` | `abc123..`, o mesmo da MV |

O traballo diario na Debian non precisa `sudo`, e as ordes `daw-*` non
piden ningún contrasinal, nin de Linux nin de Windows.

## Traballar con Visual Studio Code

Para programar dentro do contedor, coa súa versión de PHP e o seu terminal:

1. Executa `daw-code`. VS Code conéctase a Debian e abre o proxecto.
2. Preme `F1` e escolle **Dev Containers: Reopen in Container**.
3. VS Code ábrese de novo dentro do contedor `web`, co proxecto en
   `/workspace` e o código en `/workspace/www`. O terminal integrado
   (`Ctrl+ñ`) xa é o do contedor, como `ad`.

Ao abrir o proxecto no contedor arrancan tamén MariaDB e phpMyAdmin, e ao
pechar VS Code páranse os contedores.

Xdebug só depura as peticións que o piden, como na MV:

1. Pon un punto de interrupción e preme `F5` coa configuración
   **Escoitar Xdebug**.
2. Abre a páxina engadindo `?XDEBUG_TRIGGER=1` ao enderezo, por exemplo
   `http://localhost/u3/t1/index.php?XDEBUG_TRIGGER=1`.

Para depurar, abre VS Code dentro do contedor.

## Problemas habituais

- **`http://localhost/` non responde.** Mira `daw-status`: se `daw-web`
  non está `Up`, executa `daw-start`.
- **phpMyAdmin non abre ou non conecta.** Arranca con `daw-start-all`.
- **Windows non recoñece `daw-start`.** Abre un terminal novo. Se persiste,
  escolle **DAW Dev → Activar DAW Dev** no menú Inicio.
- **A activación remata cun erro.** Avisa ao docente. O rexistro está en
  `%LOCALAPPDATA%\DAW-Aula`.
- **PHP non pode escribir un ficheiro (`Permission denied`).** O directorio
  necesita os permisos que indica o enunciado: Apache é `www-data`.
- **Windows non deixa gardar un ficheiro creado como `root`.** Desde
  `~/proxectos/daw-dev`, devólvello a `ad` con esta orde.

  ```bash
  docker compose exec web chown ad:ad /home/ad/html/u3/t1/f.php
  ```
