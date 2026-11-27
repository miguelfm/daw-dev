# Contorno DAW Dev na aula

DAW Dev é un contorno de desenvolvemento PHP que funciona na túa conta de
Windows sen permisos de administración. Está formado por unha distribución
Linux de WSL2, `linux`, con Docker, e tres contedores: `web` (Apache e
PHP 8.6 con Xdebug 3.6), `db` (MariaDB) e `phpmyadmin`.

No contedor `web`, Apache executa PHP como `www-data`, como nun servidor
Debian, e serve o código desde `/var/www/html`.

O contorno instálase en cada conta e en cada computador. Noutro computador da
aula tes outra copia, que non comparte ficheiros nin bases de datos con esta:
para levar o traballo dun a outro, usa Git ou unha copia dos ficheiros.

## Activar o contorno

A primeira vez que o usas nun computador, no menú Inicio, escolle **DAW Dev
→ Activar DAW Dev**. Unha xanela amosa o progreso; tarda uns minutos e
remata con «DAW Dev está activado». Despois abre un terminal novo para que
as ordes `daw-*` estean dispoñibles. Se xa tes as ordes `daw-*`, `daw-activate`
fai o mesmo desde PowerShell ou CMD. Se o menú Inicio aínda non amosa a entrada, abre
`C:\DAW-Dev` no Explorador de ficheiros e fai dobre clic en **Activar DAW Dev.cmd**.

Repetir a activación é seguro: conserva os teus ficheiros e as bases de
datos, e trae as ordes e os ficheiros do proxecto que cambiasen.

Se a conta tiña a instalación anterior (a distribución `Debian`, co proxecto
en `~/proxectos/daw-dev`), a primeira activación bórraa. Antes copia o teu
código web en `Documentos\DAW-Dev-www-<data>-Debian` e despois pono no `www`
novo. O resto (`datos`, os proxectos de Angular e as bases de datos)
pérdese: gárdao antes fóra dela.

## Onde están os ficheiros

O proxecto está no cartafol `daw`. No Explorador de Windows:

```text
\\wsl.localhost\linux\home\ad\daw
```

Ata o 27-11-2026 chamábase `workspace`. Ao repetir a activación móvese a `daw`
sen perder nada, e `workspace` segue levando ao mesmo cartafol.

Dentro hai dous cartafoles de traballo:

- **`www`** é a raíz web. O acceso directo «DAW - Web» do Escritorio
  ábreo; tamén `daw-web-root -Open`. No contedor é `/var/www/html`.
  O ficheiro `www/u3/t1/index.php` ábrese en
  `http://localhost/u3/t1/index.php`.
- **`data`** garda os ficheiros que unha aplicación le ou escribe fóra da
  raíz web. No contedor está en `/home/ad/data`.

Apache executa PHP como `www-data`, que non pode escribir en `www` nin en
`data`. Se unha tarefa necesita que PHP cree ficheiros nun directorio,
executa as ordes de permisos do enunciado no terminal do contedor
(véxase *Abrir un terminal de Linux*).

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
| `daw-code` | Abre directamente o proxecto en Visual Studio Code |
| `daw-code -Container` | Abre directamente o proxecto no Dev Container de PHP |
| `daw-web-root -Open` | Abre a raíz web no Explorador |
| `daw-wsl-shell` | Abre a distribución `linux` no cartafol do proxecto |
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
| MDN: HTML, HTTP, CSS | `http://localhost:5042/` | `daw-start-doc` |
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

`daw-wsl-shell` abre a distribución `linux` no proxecto (`~/daw`). Aquí podes
usar Docker e Git ou consultar `curl --manual`. Funciona tamén con Docker parado.

`daw-web-shell` entra no contedor web como `ad`, en `/var/www/html`. Aquí
tes PHP e Composer, e os datos das tarefas en `/home/ad/data`. Arranca o
contedor con `daw-start` antes de entrar. Escribe `exit` para volver á terminal anterior.

## Contrasinais

Ningunha das contas de Linux de DAW Dev ten contrasinal:

| Onde | Conta | Contrasinal |
|---|---|---|
| Contedor `web` | `ad` | Ningún: `sudo` non o pide |
| Distribución `linux` de WSL | `ad` | Ningún, e a conta non ten `sudo` |
| MariaDB | `dwcs` e `root` | `abc123..` |

O traballo diario na distribución non precisa `sudo`, e as ordes `daw-*` non
piden ningún contrasinal, nin de Linux nin de Windows.

## Traballar con Visual Studio Code

Executa `daw-code -Container` para abrir o proxecto no contedor de PHP.
O proxecto está en `~/daw` e o código en `~/daw/www`, como na distribución. O terminal
integrado (`Ctrl+ñ`) abre no contedor como `ad`: o prompt é `ad@php:~/daw$`.
Na distribución, en cambio, leva o nome do computador (`ad@A31EQ28:~/daw$`).

Se xa tes o proxecto aberto en WSL, podes premer `F1` e escoller
**Dev Containers: Reopen in Container** na xanela actual.

Ao abrir ou reconstruír o Dev Container arranca o servidor web. Cando
precises MariaDB, executa `daw-start-db` desde PowerShell. Para usar tamén
phpMyAdmin, executa `daw-start-all`. Podes facelo coa xanela de VS Code
aberta no contedor: o servidor web segue como está e non se pecha a xanela.

Se antes usaches `daw-start`, ao abrir o Dev Container verás que se retira
`daw-web` e se crea de novo. É normal: o Dev Container precisa a súa propia
configuración. Os teus ficheiros de `www` e as bases de datos consérvanse.
Ao pechar a xanela do contedor, o seguinte `daw-start` faino ao revés.

Xdebug só depura as peticións que o piden:

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
  `%LOCALAPPDATA%\DAW-Dev`.
- **VS Code queda en «Retrying to download VS Code Server».** O servidor
  vén no paquete da aula, pero só para a versión de VS Code dos postos: se
  `daw-code` avisa de que falta, avisa ao docente. Mentres, usa
  `daw-code -Local` para seguir editando e `daw-web-shell` para usar PHP ou
  Composer.
- **PHP non pode escribir un ficheiro (`Permission denied`).** O directorio
  necesita os permisos que indica o enunciado: Apache é `www-data`.
- **Windows non deixa gardar un ficheiro creado como `root`.** Desde
  `~/daw`, devólvello a `ad` con esta orde.

  ```bash
  docker compose exec web chown ad:ad /var/www/html/u3/t1/f.php
  ```
