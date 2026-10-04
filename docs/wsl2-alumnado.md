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

Desde agora tes **Debian** no menú Inicio e en Windows Terminal. Todos os comandos que seguen, salvo os que
digan PowerShell, escríbense **na xanela de Debian**.

### 1.2. Descargar o proxecto

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/miguelfm/dwcs-php.git ~/dwcs
```

Se o profesorado che indica outro repositorio, usa esa URL. Se en vez diso che dan un `.zip`, descomprímeo en Windows, executa
`cd ~ && explorer.exe .` en Debian e arrastra o cartafol `dwcs` á xanela que se abre.

> **Garda sempre o proxecto dentro de Debian (`~/dwcs`), nunca en `C:`**. En `C:` todo vai moito máis lento.

### 1.3. Instalar Docker

```bash
sudo bash ~/dwcs/wsl/instalar-docker.sh
```

Cando remate:

1. Pecha a xanela de Debian.
2. En **PowerShell** executa `wsl --shutdown`.
3. Volve abrir Debian e comproba que Docker funciona:

```bash
docker run --rm hello-world
```

Ten que aparecer `Hello from Docker!`.

### 1.4. Primeiro arranque da contorna

```bash
cd ~/dwcs
docker compose up -d
```

A primeira vez descarga as imaxes e tarda uns minutos. Despois abre no navegador de Windows:

- <http://localhost>: páxina de comprobación. Debe saír todo en verde.
- <http://localhost:8081>: phpMyAdmin (usuario `dwcs`, contrasinal `abc123.`).

Para comprobar todo (servidor, base de datos, Composer, permisos e Xdebug):

```bash
./scripts/comprobar.sh
```

Ao final ten que poñer `OK todo correcto`.

### 1.5. VS Code

1. Instala [VS Code](https://code.visualstudio.com) en Windows. O instalador de usuario non pide permisos de
   administrador.
2. Instala a extensión **WSL** (`ms-vscode-remote.remote-wsl`).
3. En Debian, desde o proxecto:

   ```bash
   cd ~/dwcs
   code .
   ```

   VS Code ábrese conectado a Debian: abaixo á esquerda pon **WSL: Debian**. A primeira vez tarda un pouco
   porque se instala o seu servidor dentro de Debian.
4. VS Code proporá as extensións recomendadas do proxecto (PHP Debug, Intelephense). Instálaas: quedan
   instaladas **en WSL: Debian**.

## 2. Uso diario

1. Abre **Debian**.
2. Arranca a contorna:

   ```bash
   cd ~/dwcs && docker compose up -d
   ```

3. Abre VS Code con `code .` e o navegador en <http://localhost>.

O teu código vai en `~/dwcs/www/`. Os cambios vense ao recargar o navegador.

> **Importante:** cando pechas todas as xanelas de Debian (e VS Code), Windows apaga Debian ao pouco e a
> contorna párase. Se <http://localhost> non carga, abre Debian e volve executar `docker compose up -d`.

Os demais comandos (shell no contedor, MariaDB, Composer, logs...) están no [README](../README.md#comandos-do-día-a-día).

### Depurar con Xdebug

1. Abre o proxecto **desde Debian con `code .`** (ten que poñer **WSL: Debian** abaixo á esquerda).
2. Pon un punto de interrupción nun `.php` de `www/`.
3. Pulsa **F5** («Escoitar Xdebug») e recarga a páxina no navegador.

Se abres o cartafol desde Windows (por exemplo pola ruta `\\wsl$\...`) sen a extensión WSL, os puntos de
interrupción **non paran**: Xdebug só chega a VS Code cando este está conectado a Debian.

### Ver os ficheiros desde Windows

En Debian, `explorer.exe .` abre o cartafol actual no Explorador de Windows. Tamén podes ir a
`\\wsl$\Debian\home\<o-teu-usuario>\dwcs` no Explorador.

## 3. HTTPS con FrankenPHP (só se o pide o profesorado)

Para activar FrankenPHP, sigue os pasos do [README](../README.md#servidor-alternativo-frankenphp). Para que o
navegador non avise de que o certificado non é fiable:

1. En Debian, copia o certificado ao proxecto e abre o cartafol en Windows:

   ```bash
   cd ~/dwcs
   docker compose cp web:/data/caddy/pki/authorities/local/root.crt ./caddy-root.crt
   explorer.exe .
   ```

2. No Explorador, dobre clic en `caddy-root.crt` → **Instalar certificado** → **Usuario actual**.
3. Escolle **Colocar todos os certificados no seguinte almacén** → **Examinar** →
   **Entidades de certificación raíz de confianza** → Aceptar → Seguinte → Finalizar.
4. Acepta o aviso de seguridade e reinicia o navegador.

Edge e Chrome usan este almacén. Firefox ten o seu propio: *Axustes → Privacidade e seguranza → Ver
certificados → Autoridades → Importar* e marca «Confiar nesta CA para identificar sitios web».

## 4. Problemas habituais

Executa primeiro `cd ~/dwcs && ./scripts/comprobar.sh`: indica que parte falla. Se non o sabes arranxar,
pásalle a saída ao profesorado.

| Síntoma | Solución |
|---|---|
| <http://localhost> non carga | A contorna está parada: abre Debian e executa `cd ~/dwcs && docker compose up -d`. |
| `permission denied ... docker.sock` | Non fixeches o `wsl --shutdown` despois de instalar Docker (paso 1.3). |
| `Cannot connect to the Docker daemon` | Executa `wsl --shutdown` en PowerShell e volve abrir Debian. Se persiste, volve executar `sudo bash ~/dwcs/wsl/instalar-docker.sh`. |
| `port is already allocated` | Outro programa de Windows usa ese porto (XAMPP, Skype, IIS...). Párao ou cambia `WEB_PORT`, `DB_PORT` ou `PMA_PORT` en `~/dwcs/.env` (copia `.env.example`). |
| Os puntos de interrupción non paran | Abre o proxecto desde Debian con `code .` e comproba que abaixo á esquerda pon **WSL: Debian**. |
| `wsl --install` dá o erro `0x80370102` | O equipo non está preparado: avisa ao profesorado. |
| Esquecín o contrasinal de Linux | En PowerShell: `wsl -d Debian -u root passwd <o-teu-usuario>`. |

## 5. Empezar de cero ou desinstalar

Isto **borra Debian e todo o que haxa dentro**, incluído o teu código. Garda antes o teu traballo (en git, por
exemplo). En PowerShell:

```powershell
wsl --unregister Debian
```

Despois podes volver ao paso 1.1.
