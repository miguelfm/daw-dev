# Contorno DAW Dev na aula

DAW Dev é un contorno de desenvolvemento PHP que funciona na túa conta de
Windows sen permisos de administración. Está formado por unha distribución
Linux de WSL2, `Debian-DAW`, con Docker, e tres contedores: `web` (Apache e
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
  Escritorio abre o cartafol `\\wsl.localhost\Debian-DAW\home\ad\www`, que no
  contedor é `/home/ad/html`. O ficheiro `www/u3/t1/index.php` ábrese en
  `http://localhost/u3/t1/index.php`.
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
|---|---|
| `daw-start` | Arranca só o contedor `web` |
| `daw-start-db` | Arranca `web` e MariaDB |
| `daw-start-all` | Arranca `web`, MariaDB e phpMyAdmin |
| `daw-start-angular` | Arranca o contedor de Angular (DWCC) |
| `daw-status` | Amosa os contedores, o seu estado e os portos |
| `daw-logs` | Segue os rexistros dos contedores; `Ctrl+C` remata |
| `daw-code` | Abre o proxecto en Visual Studio Code |
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

Só se pode acceder a eles desde o propio computador. MariaDB ten dous
usuarios, co mesmo contrasinal:

| Usuario | Contrasinal | Uso |
|---|---|---|
| `dwcs` | `abc123.` | Aplicacións; base de datos `dwcs` |
| `root` | `abc123.` | Administración |

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

- **`http://localhost/` non responde.** Mira `daw-status`: se `daw-web`
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
