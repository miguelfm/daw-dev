# Xestionar os contedores DAW Dev desde Windows 11

Esta guía permite arrancar, parar e consultar os contedores desde PowerShell ou CMD,
en calquera cartafol, cos comandos `daw-*`. Os comandos e a súa axuda están en inglés.

## Requisitos

- Windows 11 con WSL2 e a distribución **Debian**.
- Docker Engine e Docker Compose instalados dentro de Debian; o usuario de Debian
  debe poder executar `docker` sen `sudo`.
- Unha copia do repositorio en Windows ou dentro de Debian.

Para preparar o equipo, consulta a [guía de instalación](wsl2-alumnado.md).

## Instalar os comandos no PATH do usuario

### Copia do proxecto en Windows

Abre PowerShell e executa desde a raíz do proxecto:

```powershell
cd "$env:USERPROFILE\Projects\daw-dev"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\install-daw-commands.ps1
```

O instalador crea os lanzadores `daw-*.cmd` en `%USERPROFILE%\.local\bin` e engade
ese cartafol ao PATH do usuario se falta. Non require permisos de administrador. Para actualizar
unha instalación anterior, executa de novo o instalador: substitúe os lanzadores e retira
os antigos lanzadores `dwcs*.cmd` ou `daw-dev-*.cmd` cando apuntan a esta copia do repositorio ou ao seu antigo
cartafol `dwcs-php`. Véxase tamén a [guía de migración](renomeado-daw-dev.md).
A opción `ExecutionPolicy Bypass` aplícase ao proceso que executa o script.
Os lanzadores chaman a `windows/daw.ps1` do repositorio. Se moves a copia, volve
executar o instalador desde a nova raíz.
Os lanzadores instalados antes do 26/11/2026 chaman a `wsl\daw.ps1`: ao usar calquera
deles, reinstálanse coa ruta nova.

Cada orde `daw-*` repón tamén os lanzadores que falten e o cartafol no PATH,
sen substituír os existentes: despois dun `git pull` que engade unha orde nova,
como `daw-activate`, chega con executar calquera delas (por exemplo, `daw-help`)
e abrir un terminal novo. Non se fai nada se os lanzadores existentes apuntan a
outra copia ou a outra distribución.

### Copia do proxecto en Debian

En PowerShell, axusta `$project` á ruta Linux da túa copia. Este exemplo copia
os dous scripts a un cartafol temporal de Windows antes de executar o instalador.
Así podes actualizar os lanzadores directamente desde a copia activa de Debian.

```powershell
$project = '/home/uxia/proxectos/daw-dev'
wsl.exe -d Debian --exec true
$source = '\\wsl.localhost\Debian' + ($project -replace '/', '\')
$setup = Join-Path $env:TEMP ('daw-dev-setup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $setup | Out-Null
Copy-Item -LiteralPath "$source\windows\install-daw-commands.ps1", "$source\windows\daw.ps1" -Destination $setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$setup\install-daw-commands.ps1" -Distribution Debian -LinuxProjectPath $project
```

O instalador garda `daw.ps1` en `%LOCALAPPDATA%\daw-dev-launcher`. Repite o paso
cando cambies de ruta ou actualices os scripts. `daw-code` abre a copia de Debian en
VS Code a través da extensión WSL. O despregamento da aula inclúe este paso na
activación da conta. [Guía do despregamento automatizado](aula-windows11.md).

A instalación manual crea os lanzadores para PowerShell e CMD. A entrada
**DAW Dev → Activar DAW Dev** do menú Inicio procede do despregamento da aula:
`CopiarModelo` copia o paquete ao equipo e prepara a entrada común. Co
paquete despregado, `daw-activate` invoca o mesmo activador desde o terminal.
[Activación desde o menú Inicio](aula-windows11.md#activación-manual-desde-o-menú-inicio).

### Comprobar os lanzadores

Abre unha nova xanela de PowerShell ou CMD e comproba:

```powershell
daw-help
daw-status
daw-web-root
```

## Abrir a raíz web no Explorador de ficheiros

En PowerShell ou CMD, `daw-web-root` amosa primeiro a ruta para o Explorador e
na liña seguinte a ruta para a terminal de Debian. `daw-web-root -Open` abre
o cartafol no Explorador. `daw-www` segue dispoñible e só amosa a ruta de Windows.
O comando consulta a montaxe do contedor
web, mesmo se está parado. Antes de crear o contedor, usa a
configuración de Compose, que resolve `WWW_DIR` (`./www` por defecto). Se cambias
`WWW_DIR` co contedor xa creado, executa `daw-start` para aplicar a nova montaxe.

| Onde se gardou o proxecto | Ruta no Explorador | Ruta en Debian |
|---|---|---|
| En Windows | `C:\Users\<usuario>\Projects\daw-dev\www` | `/mnt/c/Users/<usuario>/Projects/daw-dev/www` |
| En Debian, cunha instalación manual | `\\wsl.localhost\Debian\home\<usuario>\proxectos\daw-dev\www` | `/home/<usuario>/proxectos/daw-dev/www` |
| Na distribución `linux` da aula | `\\wsl.localhost\linux\home\ad\workspace\www` | `/home/ad/workspace/www` |
| En Debian, coa montaxe opcional descrita abaixo | `\\wsl.localhost\Debian\home\ad\www` | `/home/ad/www` |

Para explorar Debian, pega `\\wsl.localhost\Debian\` na barra de enderezos.
`\\wsl$` lista as distribucións dispoñibles. Desde un terminal de Debian tamén
podes executar `explorer.exe .` no cartafol que queiras abrir. Para os ficheiros
gardados en `C:`, usa a ruta de Windows, que Debian ve baixo `/mnt/c/`.

Dentro do contedor, Compose monta o cartafol web en `/var/www/html`, de onde
serve Apache. Na aula, os datos das tarefas (`data/`) están en `/home/ad/data`.

### Ruta fixa opcional nunha instalación manual

Se a copia activa está en Debian, podes expoñer o seu `www` en `/home/ad/www`
cunha montaxe *bind*. Déixase `WWW_DIR=./www` para que Apache, Git e Xdebug usen
o `www` da mesma copia. A ruta fixa é independente do nome da conta de Windows.

1. Se migras desde Windows, copia o repositorio completo a Debian, incluídos
   `.git`, `.env` e os ficheiros locais de `www/`. Comproba `git status` e
   `docker compose config --quiet` na copia nova. Garda a de Windows como
   respaldo. Instala os lanzadores para a ruta de Debian segundo o apartado
   anterior e executa `daw-start` para que Apache use a copia nova. Mantén o
   mesmo nome de proxecto e o mesmo volume de MariaDB no `.env`.
2. En Debian, confirma que `/home/ad/www` está libre e que `/etc/fstab` carece
   dunha entrada para ela. Nunha instalación manual cunha ruta libre, crea o
   punto de montaxe e garda unha copia de `/etc/fstab`:

   ```bash
   sudo install -d -m 0755 /home/ad/www
   sudo cp -p --no-clobber /etc/fstab /etc/fstab.before-daw-dev
   sudoedit /etc/fstab
   ```

3. Engade esta liña, substituíndo a primeira ruta polo `www` da túa copia activa:

   ```fstab
   /home/uxia/proxectos/daw-dev/www /home/ad/www none bind,nofail 0 0
   ```

4. Valida e activa a montaxe:

   ```bash
   sudo findmnt --verify && sudo systemctl daemon-reload && sudo mount /home/ad/www
   findmnt --mountpoint /home/ad/www
   ```

En Windows, abre `\\wsl.localhost\Debian\home\ad\www` e comproba no navegador
que Apache serve os mesmos ficheiros. `daw-web-root` seguirá amosando a ruta
que Docker monta directamente. WSL procesa `/etc/fstab` ao iniciar Debian.
[Configuración de WSL sobre as montaxes ao arrancar](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#automount-settings).

### Rendemento

O rendemento depende de onde se gardan os ficheiros e de onde se executan as
ferramentas. Para o Explorador e ferramentas nativas de Windows, o acceso directo
a `C:` evita cruzar entre Windows e WSL. Para Docker, Git ou Composer en Debian,
un proxecto baixo `/home/<usuario>/` evita que Linux lea ficheiros a través de
`/mnt/c/`. A diferenza adoita notarse máis en operacións con moitos ficheiros.
Abrir un cartafol desde o Explorador non altera a montaxe que usa Docker.
[Guía de Microsoft sobre os sistemas de ficheiros de WSL](https://learn.microsoft.com/en-us/windows/wsl/interop).

## Comandos de uso diario

| Comando | Resultado |
|---|---|
| `daw-start` | Arranca só `daw-web`, sen arrancar dependencias; agarda ata que estea preparado. |
| `daw-start-db` | Arranca MariaDB e o web xuntos; agarda ata que estean preparados. |
| `daw-start-all` | Arranca o web, MariaDB e phpMyAdmin; agarda ata que estean preparados. |
| `daw-stop` | Para os contedores DAW Dev. Conserva contedores e datos. |
| `daw-status` | Mostra unha táboa compacta co nome, estado e portos, tamén dos contedores parados. |
| `daw-web-root [-Open]` | Amosa as rutas de Windows e Debian. Con `-Open` tamén abre o cartafol no Explorador. |
| `daw-code [-Local]` | Abre o proxecto en VS Code. Para unha copia en Debian, conecta coa extensión WSL. Con `-Local` abre o editor en Windows. |
| `daw-web-shell` | Abre Bash no contedor de Apache e PHP como `ad`. `daw-shell` segue funcionando como alias. |
| `daw-wsl-shell` | Abre Debian no cartafol do proxecto, tamén con Docker parado. |
| `daw-logs` | Mostra as últimas 100 liñas por servizo e segue os novos logs. `Ctrl+C` sae da consulta. |
| `daw-help` | Mostra a axuda. |

`daw-start` permite traballar con PHP sen base de datos. Se os outros contedores
xa estaban en marcha, seguen en marcha. Para pasar da contorna completa a só web:

```powershell
daw-stop
daw-start
```

Sen MariaDB, o código que precise a BD fallará e a páxina de comprobación mostrará
un erro na conexión á BD. Para arrancar a BD e o web, executa `daw-start-db`.
Para volver á contorna completa, executa `daw-start-all`.

WSL arranca Debian automaticamente ao executar estes comandos. Docker debe estar
configurado para iniciar con Debian. Se non responde, executa:

```powershell
wsl -d Debian -- sudo systemctl enable --now docker
```

Os comandos usan sempre a configuración `compose.yaml` e o `.env` deste repositorio,
independentemente do cartafol actual do terminal. Respecta os portos que configures no `.env`. Non borra volumes nin a base de datos.

Os comandos de arranque manteñen unha sesión de WSL en segundo plano mentres
haxa servizos do proxecto en marcha. Isto evita que WSL peche Debian ao rematar
o lanzador e pare tamén os contedores. Non se abre ningunha xanela adicional.
Tras `daw-stop`, a sesión remata nun máximo de 20 segundos. Un peche explícito
con `wsl --shutdown` segue parando o contorno.

## Consola do contedor web

Desde PowerShell ou CMD, escolle a terminal segundo onde queiras traballar:

```powershell
daw-wsl-shell
daw-web-shell
```

`daw-wsl-shell` abre a distribución Debian e usa a súa conta Linux. Alí podes
consultar `curl --manual` ou usar Docker e Git. `daw-web-shell` entra como `ad`
no contedor que executa Apache e PHP. Alí podes usar `php -v` ou `composer -V`.
Se o contedor está parado, arráncao antes con `daw-start`.

Se precisas unha consola como root no contedor:

```powershell
wsl -d Debian -- docker exec -it -u root daw-web bash
```

Escribe `exit` para volver á terminal anterior. Substitúe `Debian` se usas
outra distribución de WSL.

Se tes Docker dispoñible directamente en Windows, podes executar
`docker exec -it -u ad daw-web bash` sen o prefixo `wsl -d Debian --`.
O [README](../README.md#consola-do-contedor-web) explica tamén a alternativa con Docker Compose
e o acceso desde outro equipo por SSH ao anfitrión.

## Integración con VS Code en Windows 11

Hai dúas formas de integrar o editor cos contedores Docker que se executan en WSL2:

### Opción A: Executar todo dentro do contedor (Dev Containers - Recomendada)

Esta opción executa VS Code e todas as súas ferramentas directamente **dentro do contedor `daw-web`**, sen precisar Docker Desktop nin instalar PHP en Windows:

1. **Requisitos:**
   - Extensión **Dev Containers** (`ms-vscode-remote.remote-containers`) en VS Code.
   - Extensión **WSL** (`ms-vscode-remote.remote-wsl`).
   *(Nas aulas con despregamento automatizado, ambas extensións instálanse de xeito automático no perfil do alumno).*
2. **Configuración incluída no proxecto:**
   - O ficheiro [`.vscode/settings.json`](../.vscode/settings.json) xa inclúe os axustes necesarios para que Dev Containers se comunique co Docker de WSL:
     ```json
     "dev.containers.executeInWSL": true,
     "dev.containers.executeInWSLDistro": "Debian"
     ```
     *(No modelo de aula e no proxecto, o valor predeterminado é `"Debian"`).*
   - O ficheiro [`.devcontainer/compose.devcontainer.yaml`](../.devcontainer/compose.devcontainer.yaml) usa `build: !reset null` para reutilizar a imaxe web local (`ghcr.io/miguelfm/dwcs-php:8.6-ad`) ou descargala de GHCR.
3. **Uso:**
   - Executa a orde `daw-code` en PowerShell ou CMD (ou abre a carpeta do proxecto en VS Code en Windows).
   - Ao detectar a configuración, VS Code amosará a mensaxe emerxente para reabrir no contedor. Fai clic en **«Reopen in Container»** (ou preme **`F1`** / `Ctrl+Shift+P` e selecciona `Dev Containers: Reopen in Container`).
   - O espazo de traballo abrirase en `/workspace` dentro do contedor.
   - Cando abras un novo terminal (`Ctrl+` `), estarás directamente na liña de ordes de Linux como usuario `ad`, con PHP 8.6, Composer, Git e o cliente de MariaDB dispoñibles.

### Opción B: VS Code en Windows con terminal integrado no contedor

Se prefires manter a interface e extensións de VS Code executándose localmente en Windows, pero queres que o **terminal integrado** abra automaticamente a shell do contedor:

- O proxecto vén preconfigurado con este perfil predeterminado en [`.vscode/settings.json`](../.vscode/settings.json):
  ```json
  "terminal.integrated.profiles.windows": {
      "Contedor DAW Dev": {
          "path": "wsl.exe",
          "args": ["-d", "Debian", "--", "docker", "exec", "-it", "-u", "ad", "daw-web", "bash"],
          "icon": "server-process"
      }
  },
  "terminal.integrated.defaultProfile.windows": "Contedor DAW Dev"
  ```
- Cada vez que abras un novo terminal en VS Code (`Ctrl+` ` ou menú *Terminal → New Terminal*), entrará directamente como usuario `ad` no contedor `daw-web`. Se o contedor non estivese iniciado, arráncao antes con `daw-start`.

## Acceso aos servizos

Cos portos por defecto:

| Servizo | Acceso |
|---|---|
| PHP + Apache | <http://localhost> |
| phpMyAdmin | <http://localhost:8081> |
| MariaDB desde Windows | `localhost:3306` |
| Portainer CE, se está instalado | <https://localhost:9443> |

O código PHP está en `www/`; os cambios vense ao recargar o navegador.
Ao abrir <http://localhost> ou un subdirectorio, móstrase a listaxe de ficheiros,
mesmo se existe `index.php` ou `index.html`. Para executar a páxina de comprobación,
abre <http://localhost/index.php>. Para outros exercicios ou demostracións (por exemplo
subcarpetas como `www/dwcs/`), abre o ficheiro ou subdirectorio concreto.
As subcarpetas de demostración locais como `www/dwcs/` están excluídas no `.gitignore`
para evitar versionar material privado ou solucións no repositorio público.
Este comportamento vén configurado por defecto en Apache.
As credenciais de exemplo da BD son usuario `dwcs`, contrasinal `abc123..` e base
de datos `dwcs`. Dentro dos contedores, o servidor da BD é `db`.

Portainer permite consultar e xestionar os contedores graficamente. O seu certificado
inicial é autofirmado. `daw-stop` non para Portainer, porque pertence a outro proxecto.
Non despregues unha segunda copia de DAW Dev desde Portainer: os nomes dos contedores son fixos.

## Comprobar a contorna

Se o proxecto está en Debian, abre a súa raíz nun terminal de Debian e executa:

```bash
bash scripts/check.sh
```

Se está en Windows, abre PowerShell na raíz do proxecto e executa:

```powershell
wsl -d Debian --cd (Get-Location).Path -- bash scripts/check.sh
```

Comproba PHP, conexión coa BD, Composer, permisos de ficheiros, actualización dos
cambios, Xdebug e phpMyAdmin. O comprobador arranca a contorna se está parada.

### VS Code queda en «Retrying to download VS Code Server»

Desde a paleta de VS Code, abre **WSL: Show Log** se falla a conexión a Debian,
ou **Dev Containers: Show Container Log** se falla ao reabrir no contedor.
Busca a primeira mensaxe de erro xusto antes de **Retrying**.

Se aparece un erro de conexión, proba en PowerShell a URL que figura no
rexistro. `curl.exe` segue a redirección e limita a comprobación a 20 segundos:

```powershell
curl.exe -fIL --connect-timeout 8 --max-time 20 '<URL de descarga que aparece no rexistro>'
```

Se a primeira resposta é `302` e o destino esgota o tempo, comproba que a rede
deixa saír por HTTPS a `update.code.visualstudio.com` e
`vscode.download.prss.microsoft.com`. Nun centro con proxy, usa a configuración
do sistema que indique a administración. Dev Containers descarga o servidor
no equipo local e despois cópiao ao contedor. [Requisitos de rede de Dev Containers](https://code.visualstudio.com/docs/devcontainers/faq#_what-are-the-connectivity-requirements-for-the-vs-code-server-when-it-is-running-in-a-container).

Para seguir editando os ficheiros da copia activa mentres se resolve a descarga,
usa `daw-code -Local` desde Windows e `daw-web-shell` para executar PHP ou
Composer. Para retomar a depuración no contedor, conecta con `daw-code` e escolle
**Dev Containers: Reopen in Container** cando a descarga volva funcionar.

Se `daw-start` non se recoñece, abre un terminal novo ou executa de novo o instalador.
Se un porto está ocupado, cambia o valor correspondente no `.env` e executa `daw-start`.

### Localhost deixa de responder pouco despois do arranque

En Windows con Docker Engine dentro dunha distribución WSL2, o comando de
arranque pode rematar correctamente e o navegador deixar de conectar despois.
WSL pode pechar a distribución cando xa non queda unha sesión activa; ter Docker
habilitado en systemd non garante que a distribución permaneza aberta.
Este diagnóstico corresponde a Docker dentro de WSL2. En Linux nativo ou con
Docker Desktop hai que comprobar o estado do motor e dos contedores antes de
atribuír o fallo á mesma causa.

Para diagnosticalo desde PowerShell:

```powershell
curl.exe --noproxy '*' --max-time 8 -I http://localhost/
wsl --list --verbose
daw-status
```

Consulta primeiro a listaxe de WSL: `daw-status` volve abrir a distribución e
pode ocultar que estaba parada. Se non tes os lanzadores, consulta os contedores
con `wsl -d Debian -- docker ps -a`. Substitúe Debian pola túa distribución e
axusta a URL se configuraches outro porto. Unha conexión rexeitada xunto coa
distribución parada é compatíbel con este fallo; non proba un problema de Apache.

Os lanzadores actuais resólveno mediante `scripts/keep-alive.sh`, iniciado en segundo
plano por `windows/daw.ps1` tras un arranque correcto. O script mantén unha sesión
activa mentres haxa servizos deste proxecto en marcha; un bloqueo con `flock`
evita duplicala nos arranques sucesivos. Actualiza a copia do proxecto conservando
os cambios locais e usa `daw-start`, `daw-start-db` ou `daw-start-all`.
Se os lanzadores xa apuntan a esa copia, non cómpre reinstalalos.

Esta protección só se aplica aos arranques feitos con `windows/daw.ps1`. Os alias
que chaman directamente a `wsl ... docker compose up -d` non a inclúen. Se tes o
proxecto dentro de Debian e segues a guía do alumnado, mantén aberta unha terminal
de Debian mentres traballas. Non copies unha ruta de Windows a unha instalación
co proxecto en Linux; adapta primeiro a distribución e a localización do proxecto.

Para quen revise ou modifique estes scripts, a comprobación debe incluír pechar
as sesións interactivas de Debian, agardar polo menos 90 segundos e repetir a
petición HTTP desde Windows antes de executar outro comando WSL. Comproba tamén
que `daw-stop` libera a sesión de mantemento e que un novo arranque funciona.
Un HTTP 200 inmediatamente despois do arranque non acredita a permanencia.
Non borres contedores nin volumes para resolver este síntoma.

O 21-10-2026 reproduciuse e comprobouse a corrección neste equipo con Windows,
Debian 13 en WSL2, Docker Engine 29.9.0 e Compose 5.6.0: acceso HTTP despois do
intervalo de inactividade, parada, liberación da sesión e novo arranque.
Non se comprobou esta corrección noutras distribucións, con Docker Desktop nin
despois dun reinicio completo de Windows. Tras reiniciar, segue sendo necesario
arrancar os servizos; non se configura un inicio automático con Windows.
