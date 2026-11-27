# Contorno DAW Dev na aula

DAW Dev funciona na túa conta de Windows sen permisos de administración. Usa
unha distribución de WSL2 baseada en Debian, chamada `linux`, con Docker.
Para DWCS tes `backend` (Apache, PHP 8.6, Composer e Xdebug), `db` (MariaDB)
e `db-admin` (phpMyAdmin). Tamén podes arrancar Angular para DWCC e consultar
os manuais sen conexión.

Cada conta e cada computador teñen os seus propios ficheiros e bases de datos.
Para continuar noutro posto, leva o código con Git ou con unha copia dos
ficheiros. Se precisas a base de datos, expórtaa e impórtaa con phpMyAdmin.

## Activar o contorno

A primeira vez que o usas nun computador, no menú Inicio, escolle **DAW Dev
→ Activar DAW Dev**. Unha xanela amosa o progreso; tarda uns minutos e
remata con «DAW Dev está activado». Despois abre un terminal novo para que
as ordes `daw-*` estean dispoñibles. Se xa tes as ordes `daw-*`, `daw-activate`
fai o mesmo desde PowerShell ou CMD. Se o menú Inicio aínda non amosa a entrada, abre
`C:\DAW-Dev` no Explorador de ficheiros e fai dobre clic en **Activar DAW Dev.cmd**.

Repetir a activación co mesmo paquete actualiza as ordes e os ficheiros do
proxecto conservando o teu traballo e as bases de datos. Se xa tes `linux`
co proxecto en `~/daw` ou `~/workspace`, a activación move os cartafoles á
disposición descrita abaixo. Se a activación indica que `linux` procede doutro
paquete, fala co docente antes de reinstalar.

Se aínda usas a antiga distribución da aula `Debian` (co proxecto en
`~/proxectos/daw-dev`), garda antes fóra dela os datos das tarefas e os
proxectos de Angular que precises e exporta as bases de datos. A activación
garda a raíz web en `Documentos\DAW-Dev-www-<data>-Debian`, elimina esa
distribución da aula e restaura automaticamente a copia web no novo `html`.

### Comprobar o primeiro arranque

1. En PowerShell ou CMD, executa `daw-start-all` e agarda a que remate.
   No primeiro arranque, MariaDB tarda un pouco en preparar a base de datos.
2. Abre <http://localhost/index.php>. Se tes a páxina de comprobación incluída
   no modelo, podes verificar PHP, Xdebug e a conexión a MariaDB.
3. Abre <http://localhost:8081/> para entrar en phpMyAdmin. Usa o usuario
   `dwcs` e o contrasinal `abc123..` da táboa de MariaDB.

## Instalar DAW Dev na casa

En Windows 11, segue a [guía de instalación manual con Debian e WSL2][instalacion-windows].
En Linux, segue a [posta en marcha do repositorio][instalacion-linux].
A instalación persoal garda o código web en `www/` dentro do repositorio por
defecto. Para levar unha práctica, copia aí os ficheiros que tiñas en `~/html`
na aula.

## Onde están os ficheiros

O teu traballo está no teu cartafol persoal da distribución. No Explorador de
Windows:

```text
\\wsl.localhost\linux\home\ad
```

Alí hai tres cartafoles de traballo:

- **`html`** é a raíz web. Ábrea co acceso directo **DAW - Web** do
  Escritorio ou con `daw-web-root -Open`. No contedor está en `/var/www/html`
  e en `~/html`. Por exemplo, `html/U3/A4/code/index.php` ábrese en
  `http://localhost/U3/A4/code/index.php`. Respecta as maiúsculas da ruta.
- **`data`** garda os ficheiros que unha aplicación le ou escribe fóra da
  raíz web. No contedor está en `/home/ad/data`, a mesma ruta.
- **`angular`** garda os proxectos de DWCC. No contedor de Angular está en
  `/home/node/proxectos`.

A configuración de Docker Compose e os scripts están no cartafol oculto
`~/.daw`. Garda os teus ficheiros nos tres cartafoles de traballo.

Apache executa PHP como `www-data`, que non pode escribir en `html` nin en
`data`. Se unha tarefa necesita que PHP cree ficheiros nun directorio,
executa as ordes de permisos do enunciado no terminal do contedor
(véxase *Abrir un terminal de Linux*).

## Ordes diarias

Escríbense nun terminal de PowerShell ou CMD de Windows:

| Orde | Que fai |
|---|---|
| `daw-start` | Arranca só o contedor `backend` |
| `daw-start-db` | Arranca o backend e MariaDB |
| `daw-start-all` | Arranca o backend, MariaDB e phpMyAdmin |
| `daw-start-frontend` | Arranca o contedor de Angular (DWCC) |
| `daw-start-doc` | Arranca a documentación sen conexión |
| `daw-status` | Amosa os contedores, o seu estado e os portos |
| `daw-logs` | Segue os rexistros dos contedores. Preme `Ctrl+C` para saír |
| `daw-code` | Abre `~/html` en Visual Studio Code conectado a WSL |
| `daw-code -Container` | Abre `~/html` no Dev Container de PHP |
| `daw-web-root -Open` | Abre a raíz web no Explorador |
| `daw-wsl-shell` | Abre a distribución `linux` no teu cartafol persoal |
| `daw-shell` | Abre a terminal do contedor de Apache e PHP |
| `daw-stop` | Para DAW Dev ao rematar e conserva os ficheiros e a base de datos |
| `daw-help` | Lista as ordes |

Para Angular, executa `daw-start-frontend` e conéctate en VS Code por
**Remote - SSH** a `dwcc-angular`. Consulta a [guía de Angular para DWCC][guia-angular].

## Enderezos dos servizos

| Servizo | Enderezo | Arranque |
|---|---|---|
| Web | <http://localhost/> | `daw-start` |
| phpMyAdmin | <http://localhost:8081/> | `daw-start-all` |
| MariaDB | `localhost`, porto `3306` | `daw-start-db` |
| Manual de PHP | <http://localhost:8080/> | `daw-start-doc` |
| HTML, HTTP e CSS (MDN) | <http://localhost:5042/> | `daw-start-doc` |
| Documentación de Laravel 13.x | <http://localhost:8088/> | `daw-start-doc` |

Na aula, estes portos son accesibles desde o propio computador. Apache amosa
a listaxe de ficheiros ao abrir un cartafol. Para executar un `index.php`,
abre o seu enderezo completo.

As contas incluídas en MariaDB son as seguintes.

| Usuario | Contrasinal | Uso |
|---|---|---|
| `dwcs` | `abc123..` | Aplicacións; base de datos `dwcs` |
| `root` | `abc123..` | Administración |

Desde PHP, usa `db` como servidor de MariaDB. O contedor pasa os datos
de conexión ao código nas variables `DB_HOST`, `DB_NAME`, `DB_USER` e
`DB_PASSWORD`, que podes ler con `getenv()`.

Na aula, `daw-start-doc` pode cargar os manuais desde o paquete do equipo
a primeira vez. `daw-stop-doc` para só os manuais. Avisa ao docente se falta
algunha imaxe nunha sesión sen Internet.

## Abrir un terminal de Linux

Desde PowerShell ou CMD, estas ordes abren terminais en sitios distintos:

```powershell
daw-wsl-shell
daw-shell
```

`daw-wsl-shell` abre `linux` no teu cartafol persoal (`~`, con `html`, `data`
e `angular`). Podes usar Git, Docker ou consultar `curl --manual`. A terminal
abre mesmo con Docker parado. Traballas como `ad`, sen `sudo` en WSL.

`daw-shell` entra no contedor `backend` como `ad`, en `/var/www/html`. Tes
PHP, Composer e os datos das tarefas en `/home/ad/data`. Se o contedor está
parado, arráncao con `daw-start`. Dentro do contedor, `sudo` funciona sen
contrasinal. Escribe `exit` para volver á terminal anterior.

## Traballar con Visual Studio Code

Executa `daw-code -Container` para abrir o teu código web no contedor de PHP.
VS Code abre `~/html`, a mesma ruta ca na distribución, e o Explorador amosa
directamente os teus cartafoles. Abre **Terminal → New Terminal** para
traballar como `ad` dentro do contedor. Verás `ad@backend:~/html$` na liña
de ordes.

Se xa tes o proxecto aberto en WSL, podes premer `F1` e escoller
**Dev Containers: Reopen in Container** na xanela actual.

Ao abrir ou reconstruír o Dev Container arranca o servidor web. Cando
precises MariaDB, executa `daw-start-db` desde PowerShell ou CMD, ou
`daw-start-all` para usar tamén phpMyAdmin. Podes facelo coa xanela do Dev
Container aberta e seguir traballando nela.

Se antes usaches `daw-start`, VS Code recrea `backend-c` coa configuración
do Dev Container. Ao pechar a xanela do Dev Container, podes volver iniciar
o servidor web con `daw-start`. Conservas os ficheiros dos cartafoles de
traballo e a base de datos.

Para depurar unha petición na aula, abre VS Code dentro do contedor.

1. Pon un punto de interrupción e preme `F5` coa configuración
   **Escoitar Xdebug**.
2. Abre a páxina engadindo `?XDEBUG_TRIGGER=1` ao enderezo, por exemplo
   `http://localhost/U3/A4/code/index.php?XDEBUG_TRIGGER=1`. Se o enderezo
   xa ten parámetros, engade `&XDEBUG_TRIGGER=1`.

## Problemas habituais

- **`http://localhost/` non responde.** Executa `daw-status`. Se `backend-c`
  está parado ou aínda non aparece, executa `daw-start`.
- **phpMyAdmin non abre ou non conecta.** Arranca con `daw-start-all`.
- **VS Code repite «Cannot reconnect. Please reload the window.».** O
  contedor do Dev Container parouse, por exemplo cun `daw-stop`. Preme
  **Reload Window** e, se non conecta, `F1` → **Dev Containers: Reopen in
  Container**: o contedor arranca de novo, cos teus ficheiros.
- **Windows non recoñece `daw-start`.** Abre un terminal novo. Se persiste,
  escolle **DAW Dev → Activar DAW Dev** no menú Inicio.
- **A activación remata cun erro.** Avisa ao docente. En
  `%LOCALAPPDATA%\DAW-Dev` están `install.log` e `project.log`.
- **VS Code queda en «Retrying to download VS Code Server».** O servidor
  vén no paquete da aula, pero só para a versión de VS Code dos postos: se
  `daw-code` avisa de que falta, avisa ao docente. Mentres, usa
  `daw-code -Local` para seguir editando e `daw-shell` para usar PHP ou
  Composer.
- **PHP non pode escribir un ficheiro (`Permission denied`).** O directorio
  necesita os permisos que indica o enunciado: Apache é `www-data`.
- **Windows non deixa gardar un ficheiro creado como `root`.** Devólvello
  a `ad`. Abre `daw-shell` e executa esta orde coa ruta do teu ficheiro.

  ```bash
  sudo chown ad /var/www/html/U3/A4/code/index.php
  ```

[guia-angular]: https://github.com/miguelfm/daw-dev/blob/main/docs/guia-angular-alumnado.md
[instalacion-windows]: https://github.com/miguelfm/daw-dev/blob/main/docs/wsl2-alumnado.md#1-instalaci%C3%B3n-s%C3%B3-a-primeira-vez
[instalacion-linux]: https://github.com/miguelfm/daw-dev#posta-en-marcha
