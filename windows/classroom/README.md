# Despregamento na aula

Scripts para preparar o paquete no equipo do profesor e despregalo nos postos.
O procedemento completo está na [guía de despregamento](../../docs/aula-windows11.md).

| Script | Uso |
|---|---|
| `build-package.ps1` | Crea o modelo e o paquete da aula (executa `setup-model.sh` no modelo) |
| `update-package.ps1` | Actualiza os scripts dun paquete sen reconstruír a imaxe |
| `add-package-image.ps1` | Engade ao paquete unha imaxe Docker gardada con `docker save` |
| `add-doc-images.ps1` | Descarga da última release de daw-doc as imaxes da documentación e rexístraas no paquete |
| `add-vscode-extensions.ps1` | Engade ao paquete os `.vsix` das extensións de PHP do Dev Container e de Dev Containers e WSL para VS Code, compatibles co VS Code dos postos (`-CodeVersion`); a activación instálaas sen Internet |
| `add-vscode-server.ps1` | Engade ao paquete o VS Code Server dun commit de VS Code, para non descargalo nos postos |
| `deploy.ps1` | Constrúe e completa o paquete (VS Code Server dos postos, documentación e Angular), prepara Windows con `-PrepareWindows` (WinRM, WSL e reinicios), instálao en todos os equipos dunha aula e, con `-Verify`, comproba as contas conectadas; garda un informe CSV |
| `install-package.ps1` | Instala o paquete no propio equipo, como administrador e sen WinRM (por exemplo, no do profesor) |
| `manage.ps1` | Accións nos postos por WinRM; `-ThrottleLimit` atende varios á vez |
| `check-remote.ps1`, `enable-winrm.ps1` | Diagnóstico e activación de WinRM, desde `manage.ps1` |
| `power-on.ps1`, `power-off.ps1` | Acendido por Wake-on-LAN (`a31-macs.csv`) e apagado da aula |
| `daw-classroom.psm1` | Funcións comúns. Vai no paquete, como os seguintes |
| `activate.ps1` | «Activar DAW Dev» do menú Inicio e de `C:\DAW-Dev\Activar DAW Dev.cmd`: `install-user.ps1` e despois `update-project.ps1` |
| `install-user.ps1` | Instala DAW Dev na conta que o executa, sen elevación |
| `update-project.ps1` | Copia os ficheiros do proxecto (`overlay/`) na distribución da conta |
| `verify-user.ps1` | Comproba a contorna na conta, cos seus lanzadores (acción `Verify`); non cambia a instalación |
| `autostart.ps1` | Instalación no inicio de sesión, só coa opción `-AutoStart` de `CopyPackage` |

## Rutas e nomes

Están ao comezo de `daw-classroom.psm1` e os scripts Bash recíbenos do módulo:

| Uso | Valor |
|---|---|
| Paquete no posto (`Get-DawPackageDirectory`) | `C:\ProgramData\DAW-Dev`, cos ficheiros do proxecto en `project\` |
| Estado de cada conta (`Get-DawStateDirectory`) | `%LOCALAPPDATA%\DAW-Dev`: `install-state.json`, `project-state.json`, rexistros e `install.lock` |
| Distribución WSL (`Get-DawDistribution`) | `linux`, co marcador `/etc/daw-dev-model` |
| Proxecto (`Get-DawLinuxProjectPath`) | `/home/ad/workspace`, con `www/` e `data/`; en Windows, `\\wsl.localhost\linux\home\ad\workspace` |

Ao cambiar un destes valores, as contas instaladas teñen que reinstalarse.

## Instalación limpa

Antes de eliminar unha distribución, a instalación copia o contido da súa raíz web (`WWW_DIR`, por
defecto `www`) en `Documentos\DAW-Dev-www-<data>-<distribución>` e, despois de importar a nova,
cópiao en `/home/ad/workspace/www`. O resto (`data/`, `angular/`, as bases de datos) pérdese: o
alumnado gárdao antes. A copia de Documentos consérvase; se a instalación falla antes de
restaurala, queda en `web-restore.txt` e restáurase na seguinte.

- `CopyPackage` retira do posto o paquete anterior (`C:\ProgramData\DAW-Aula`) e o
  seu autoarranque (`Run\DAWAula`). Alí deixa só `activar-dawdev.ps1`, coa ACL do paquete: o
  `daw-activate` das contas anteriores chámao e leva a `activate.ps1`.
- A primeira activación de cada conta retira a instalación anterior desa conta:
  - a distribución `Debian`, só se ten o marcador do modelo anterior (`/etc/daw-aula-modelo`);
  - `%LOCALAPPDATA%\DAW-Aula` e `%LOCALAPPDATA%\daw-dev-launcher`;
  - o acceso directo «DAW - Proxectos (www)».

  Unha Debian persoal consérvase.
- Se a conta xa ten a distribución `linux` do mesmo paquete, a activación consérvaa. Se é
  doutro paquete, detense: con `-Reinstall` (`daw-activate -Reinstall`, ou
  `manage.ps1 -Action InstallUser -Reinstall`) elimínaa con todo o seu contido e
  importa a nova.

## Ficheiros do proxecto (`overlay/`)

`overlay/` contén o que `manage.ps1 -Action UpdateProject` copia en `/home/ad/workspace`,
coa mesma ruta relativa. A copia leva tamén ficheiros do repositorio sen cambios, como
`compose.yaml`, `docker/angular/`, `.vscode/launch.json`, os comandos de terminal e as guías do
alumnado (`$sharedPaths` en `New-DawProjectStage`).
Véxase [actualizar os ficheiros dos proxectos xa importados](../../docs/aula-windows11.md#actualizar-os-ficheiros-dos-proxectos-xa-importados).

### O que contén agora

| Ficheiro | Efecto |
|---|---|
| `compose.override.yaml` | Apache como `www-data:www-data`, coa máscara `022` de Debian no canto da `002` da imaxe; `data/` en `/home/ad/data`; `www-data` sae do grupo de `ad`; `/var/lib/php/sessions` con permisos 1733; o volume `daw-vscode-extensions` coas extensións de VS Code do Dev Container |
| `docker/classroom/zz-classroom.ini` | PHP como nun servidor Debian: `output_buffering = Off`, cookie de sesión `HttpOnly` e `SameSite=Lax`, `use_strict_mode`, `save_path`, 32M nas subidas e Xdebug con `trigger` |
| `data/README.txt` | Crea `data/` co usuario `ad`, non con `root` |
| `.devcontainer/devcontainer.json` | O do repositorio, con `../compose.override.yaml` na lista: Dev Containers nomea os ficheiros de Compose e non le o *override* por si só |

O código web serve desde `/var/www/html`, como nas instalacións persoais. `daw-start` le
`compose.override.yaml` porque está ao lado de `compose.yaml`. Os cambios aplícanse ao recrear
o contedor web: no seguinte `daw-start`, co `-Restart` da acción, na activación se a copia
cambiou a definición do contedor, ou ao abrir de novo o Dev Container, porque o
`initializeCommand` (`scripts/daw.sh prepare-devcontainer`) retira o contedor anterior a eses
ficheiros.

### Regras da copia

- Non se copia nada en `www/` nin se borra ningún ficheiro.
- En `data/` só se crean ficheiros novos; os existentes son do alumnado e consérvanse.
- Os ficheiros que se substitúen gárdanse antes en `.daw-backup/<data>-<proceso>/`.
- Antes de cambiar nada compróbanse os SHA256, as rutas (sen ligazóns no destino)
  e que Compose acepte o `compose.override.yaml` novo; ao rematar, o proxecto completo.
- Unha segunda execución coa mesma revisión non cambia nada.

### Cambiar o contido

Engade ou edita ficheiros en `overlay/` coa ruta que deben ter no proxecto. Se
cambia `.devcontainer/devcontainer.json` do repositorio, actualiza a copia de aquí:
`tests/classroom.ps1` comproba que só difiren na lista de ficheiros de Compose.
`tests/overlay.py` executa a copia real en Bash e, se hai Docker, valida o resultado
con `docker compose config`.
