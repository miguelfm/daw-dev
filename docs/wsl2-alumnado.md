# Contorna DWCS en Windows 11 con WSL2 (alumnado)

Con esta guía instalas a contorna de PHP do módulo no teu usuario de Windows. **Non necesitas permisos de
administrador**: o profesorado xa preparou o equipo ([wsl2-administracion.md](wsl2-administracion.md)).

A contorna funciona dentro de **Debian**, un Linux que corre integrado en Windows grazas a WSL2. O navegador
e VS Code seguen sendo os de Windows.

## 1. Instalación (só a primeira vez)

### 1.1. Instalar Debian

Abre **PowerShell** (normal, non como administrador) e executa:

```powershell
wsl --install -d Debian
```

Ao rematar ábrese Debian e pide un **nome de usuario** e un **contrasinal** de Linux. Escolle un nome sen
espazos nin maiúsculas (por exemplo `uxia`) e **apunta o contrasinal**: pedirácheo `sudo` cando instales algo.
Mentres o escribes non se ve nada na pantalla; é normal.

Desde agora podes abrir **Debian** desde o menú Inicio ou desde PowerShell / Windows Terminal:

```powershell
wsl -d Debian
```

Para entrar cun usuario concreto, por exemplo `ad`, usa `wsl -d Debian -u ad`. O usuario de Linux é
independente do de Windows; usa o nome que creaches e o contrasinal indicado polo profesorado.
Todos os comandos que seguen, salvo os que digan PowerShell, escríbense **dentro de Debian**.

Comproba en PowerShell que Debian usa WSL2:

```powershell
wsl --list --verbose
```

Debe aparecer `Debian` con `VERSION 2`. Se aparece `1`, executa `wsl --set-version Debian 2`.

### 1.2. Descargar o proxecto

Primeiro actualiza os paquetes de Debian e instala as ferramentas de descarga:

```bash
sudo apt update && sudo apt upgrade
sudo apt install -y git wget
mkdir -p ~/proxectos
git clone https://github.com/miguelfm/dwcs-php.git ~/proxectos/dwcs-php
```

`apt upgrade` pide confirmación para actualizar os paquetes instalados; `wget` instálase explicitamente
co segundo comando. O instalador de Docker tamén inclúe `wget` entre as dependencias.

Se o profesorado che indica outro repositorio, usa esa URL. Se en vez diso che dan un `.zip`, descomprímeo en Windows, executa
`cd ~ && explorer.exe .` en Debian e arrastra o cartafol `dwcs` á xanela que se abre.

> **Garda sempre o proxecto dentro de Debian (`~/proxectos/dwcs-php`), nunca en `C:`**. En `C:` todo vai moito máis lento.
> Se xa o descargaches en `~/dwcs`, conserva esa ruta e substitúe a ruta dos exemplos seguintes pola túa.

### 1.3. Instalar Docker

```bash
sudo bash ~/proxectos/dwcs-php/wsl/instalar-docker.sh
```

Cando remate:

1. Pecha a xanela de Debian.
2. En **PowerShell** executa `wsl --shutdown`.
3. Volve abrir Debian e comproba que Docker funciona:

```bash
sudo systemctl enable --now docker
docker run --rm hello-world
```

Ten que aparecer `Hello from Docker!`.

### 1.4. Primeiro arranque da contorna

```bash
cd ~/proxectos/dwcs-php
cp .env.example .env
docker compose up -d
```

A primeira vez descarga as imaxes e tarda uns minutos. Despois abre no navegador de Windows:

- <http://localhost>: listaxe de ficheiros e subdirectorios.
- <http://localhost/index.php>: páxina de comprobación. Debe saír todo en verde.
- <http://localhost:8081>: phpMyAdmin (usuario `dwcs`, contrasinal `abc123.`).

Para comprobar todo (servidor, base de datos, Composer, permisos e Xdebug):

```bash
./scripts/comprobar.sh
```

Ao final ten que poñer `OK todo correcto`.

Para limitar os servizos ao equipo local, antes do primeiro arranque pon estes valores no `.env`:

```dotenv
WEB_PORT=127.0.0.1:80
PMA_PORT=127.0.0.1:8081
DB_PORT=127.0.0.1:3306
MAIL_PORT=127.0.0.1:8025
```

Se xa arrancaches os contedores, aplica o cambio con `docker compose up -d`. Os datos da BD consérvanse.

### 1.5. VS Code

1. Instala [VS Code](https://code.visualstudio.com) en Windows. O instalador de usuario non pide permisos de
   administrador.
2. Instala a extensión **WSL** (`ms-vscode-remote.remote-wsl`).
3. En Debian, desde o proxecto:

   ```bash
   cd ~/proxectos/dwcs-php
   code .
   ```

   VS Code ábrese conectado a Debian: abaixo á esquerda pon **WSL: Debian**. A primeira vez tarda un pouco
   porque se instala o seu servidor dentro de Debian.
4. VS Code proporá as extensións recomendadas do proxecto (PHP Debug, Intelephense). Instálaas: quedan
   instaladas **en WSL: Debian**.

## 2. Uso diario

1. Abre **Debian** desde Inicio ou executa `wsl -d Debian` en PowerShell.
2. Arranca a contorna:

   ```bash
   cd ~/proxectos/dwcs-php && docker compose up -d
   ```

3. Abre VS Code con `code .` e o navegador en <http://localhost>.

O teu código vai en `~/proxectos/dwcs-php/www/`. Os cambios vense ao recargar o navegador.
Para saír do terminal de Debian escribe `exit`.

> Despois de reiniciar Windows ou executar `wsl --shutdown`, abre Debian e volve executar
> `docker compose up -d` no proxecto. Docker inicia con Debian; os contedores DWCS necesitan ese arranque.
> Non se configura o inicio automático da contorna ao iniciar sesión en Windows.

Os demais comandos (shell no contedor, MariaDB, Composer, logs...) están no [README](../README.md#comandos-do-día-a-día).

### Atallos opcionais para a terminal

Podes definir `dwcs-up`, `dwcs-up-all`, `dwcs-down` e `dwcs-status` seguindo a
[sección de atallos do README](../README.md#atallos-dwcs-para-a-terminal). Tes exemplos para Bash dentro
de Debian e para PowerShell desde Windows, que chama a Docker a través de WSL2.

Se usas Bash, cambia a ruta dos exemplos a `$HOME/proxectos/dwcs-php/compose.yaml` e garda os alias en `~/.bashrc`.
En PowerShell, usa a ruta de Debian `/home/<o-teu-usuario>/proxectos/dwcs-php/compose.yaml`.
Se conservas unha instalación anterior en `~/dwcs`, usa esa ruta nos atallos.

- `dwcs-up`: arranca só PHP + Apache, para exercicios sen base de datos.
- `dwcs-up-all`: arranca tamén MariaDB e phpMyAdmin; úsao para a contorna completa desta guía.
- `dwcs-down`: para os contedores, conservando os datos.
- `dwcs-status`: mostra os contedores existentes da contorna, incluídos os parados.

### Depurar con Xdebug

1. Abre o proxecto **desde Debian con `code .`** (ten que poñer **WSL: Debian** abaixo á esquerda).
2. Pon un punto de interrupción nun `.php` de `www/`.
3. Pulsa **F5** («Escoitar Xdebug») e recarga a páxina no navegador.

Se abres o cartafol desde Windows (por exemplo pola ruta `\\wsl$\...`) sen a extensión WSL, os puntos de
interrupción **non paran**: Xdebug só chega a VS Code cando este está conectado a Debian.

### Ver os ficheiros desde Windows

En Debian, `explorer.exe .` abre o cartafol actual no Explorador de Windows. Tamén podes ir a
`\\wsl.localhost\Debian\home\<o-teu-usuario>\proxectos\dwcs-php` no Explorador.

### Portainer CE: xestión gráfica opcional

[Portainer CE](https://docs.portainer.io/start/install-ce/server/docker/linux) execútase como un contedor
adicional sobre Docker Engine. Permite consultar logs, abrir consolas e xestionar contedores, imaxes,
volumes e redes desde o navegador. Non require Docker Desktop.

Dentro de Debian, crea `~/portainer/compose.yaml`:

```bash
mkdir -p ~/portainer
nano ~/portainer/compose.yaml
```

Copia este contido e gárdao (en nano: Ctrl+O, Intro e Ctrl+X):

```yaml
name: portainer
services:
  portainer:
    image: portainer/portainer-ce:lts
    container_name: portainer
    restart: unless-stopped
    ports:
      - "127.0.0.1:9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
volumes:
  portainer_data:
    name: portainer_data
```

Arráncao e consulta o token de configuración:

```bash
docker compose -f ~/portainer/compose.yaml up -d
docker logs portainer
```

Abre <https://localhost:9443> no navegador de Windows. O certificado inicial é autofirmado e o navegador
mostra un aviso. Na configuración inicial, copia o valor `setup_token=` dos logs e crea unha conta
administradora cun contrasinal que cumpra os requisitos da pantalla. É unha conta propia de Portainer,
independente de Linux e da BD; non gardes o contrasinal nin o token no repositorio.

Completa a configuración nos primeiros cinco minutos. Se caduca, executa `docker restart portainer`,
consulta de novo os logs e recarga. Véxase a [guía oficial do token](https://docs.portainer.io/faqs/installing/setup-token).

Selecciona o contorno local (ou engádeo como Docker Standalone mediante Socket, usando
`/var/run/docker.sock`). En **Containers** deben aparecer `dwcs-web`, `dwcs-db` e `dwcs-phpmyadmin`.
Portainer ten acceso administrativo ao motor Docker a través dese socket.

O proxecto DWCS segue xestionándose co seu `compose.yaml` e `docker compose up -d` desde o terminal.
Non despregues unha segunda copia desde Portainer: os nomes dos contedores son fixos e entrarían en conflito.
Os datos de Portainer persisten no volume `portainer_data`; inicia con Docker salvo que o pares expresamente.

## 3. Problemas habituais

Executa primeiro `cd ~/proxectos/dwcs-php && ./scripts/comprobar.sh`: indica que parte falla. Se non o sabes arranxar,
pásalle a saída ao profesorado.

| Síntoma | Solución |
|---|---|
| <http://localhost> non carga | Abre Debian e executa `cd ~/proxectos/dwcs-php && docker compose up -d`. |
| `permission denied ... docker.sock` | Non fixeches o `wsl --shutdown` despois de instalar Docker (paso 1.3). |
| `Cannot connect to the Docker daemon` | Dentro de Debian executa `sudo systemctl enable --now docker`. Se persiste, executa `wsl --shutdown` en PowerShell e volve abrir Debian. |
| `port is already allocated` | Outro programa usa ese porto. Párao ou cambia o porto no `.env` do proxecto; por exemplo `WEB_PORT=127.0.0.1:8080`. |
| Os puntos de interrupción non paran | Abre o proxecto desde Debian con `code .` e comproba que abaixo á esquerda pon **WSL: Debian**. |
| `wsl --install` dá o erro `0x80370102` ou di que falta virtualización | Se acabas de activar WSL, reinicia Windows. Se persiste, avisa ao profesorado para revisar a BIOS/UEFI e Plataforma de máquina virtual. |
| Debian non aparece / `WSL_E_DISTRO_NOT_FOUND` | Despois de reiniciar, executa `wsl --install -d Debian` co teu usuario de Windows. |
| Esquecín o contrasinal de Linux | En PowerShell: `wsl -d Debian -u root passwd <o-teu-usuario>`. |

## 4. Empezar de cero ou desinstalar

Isto **borra Debian e todo o que haxa dentro**, incluído o teu código. Garda antes o teu traballo (en git, por
exemplo). En PowerShell:

```powershell
wsl --unregister Debian
```

Despois podes volver ao paso 1.1.

## 5. Instalación verificada

Probado en Windows 11 Pro Education (compilación 26200), Debian 13 en WSL2, Docker Engine 29.8.2,
Compose 5.6.0 e Portainer CE 2.45.1. A contorna Apache superou `scripts/comprobar.sh`: PHP 8.5,
MariaDB, Composer, permisos, actualización dos ficheiros e conexión de Xdebug. Comprobáronse o acceso
desde Windows a PHP e Portainer e a consulta dos catro contedores mediante a API de Portainer.
