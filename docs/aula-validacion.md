# Validación do despregamento de DAW Dev na aula

Rexistro das comprobacións realizadas sobre o equipamento piloto (`A31EQ01.iesrodolfoucha.es`) o 11 de novembro de 2026.

## Contorna de proba

- **Equipo de administración (profesor):** `172.21.34.100` (Windows 11).
- **Equipo de proba (alumnado):** `A31EQ01.iesrodolfoucha.es` (`172.21.34.1`, Windows 11 x64, build 26100).
- **Dominio:** `iesrodolfoucha.es`, autenticación Kerberos mediante conta de profesor con dereitos de administración local.

---

## Fases comprobadas

### 1. Conectividade e activación de WinRM
- **Mecanismo:** Descarga e execución de PsExec (`PsExec64.exe`) asinado oficialmente por Microsoft para habilitar o servizo WinRM sen requirir interacción manual nin contrasinais en claro.
- **Resultado:**
  - Servizo WinRM configurado e escoitando en HTTP (porto 5985), restrinxido ao IP do profesor.
  - Autenticación Kerberos validada mediante `Invoke-Command` sen solicitar credenciais adicionais.
  - Comprobado que os portos de Veyon (`11100`) e WinRM responden adecuadamente.

### 2. Instalación de WSL2 e reinicio limpo
- **Mecanismo:** `instalar-wsl-admin.ps1` executado remotamente.
- **Validación de seguridade:** Comprobación da sinatura dixital Authenticode de Microsoft sobre o paquete MSI oficial de WSL (`wsl.3.0.5.0.x64.msi`).
- **Resultado:**
  - Habilitadas características de virtualización e plataforma WSL.
  - Reinicio planificado e executado; WinRM restablecido correctamente tralo reinicio.

### 3. Construción e verificación do modelo Debian
- **Mecanismo:** `preparar-modelo.ps1` executado no equipo do profesor sobre a distribución illada `DAW-Modelo`.
- **Integración de compoñentes:**
  - Base limpa de Debian WSL verificada con SHA256 contra o repositorio oficial.
  - Docker Engine (`29.9.3`) e Docker Compose (`v5.7.1`) instalados dentro da distribución.
  - Imaxes base precargadas: `ghcr.io/miguelfm/dwcs-php:8.5`, `mariadb:lts`, `phpmyadmin:latest`.
  - Proxecto empaquetado mediante `git archive HEAD` excluindo `.env` persoais, claves e históricos non versionados.
  - Empaquetado comprimido xerado en `C:\Users\miguelfm\Projects\daw-aula-paquete-20261111-final\debian-daw.tar.gz` (1,4 GB) con `manifest.json` e sumas SHA256 verificadas.

### 4. Distribución á máquina piloto
- **Mecanismo:** `gestionar-aula.ps1 -Action CopiarModelo` cara a `\\A31EQ01.iesrodolfoucha.es\c$\ProgramData\DAW-Aula`.
- **Permisos e integridade:**
  - Control de acceso restrinxido: escritura exclusiva para `SYSTEM` e `Administradores`; lectura/execución para o grupo `Usuarios`.
  - Verificación SHA256 coincidente antes e despois do transporte.
  - Rexistro da entrada Run en `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` para autoimportación sen elevación no inicio de sesión de Windows.

### 5. Proba funcional con usuario estándar local (`daw-proba`)
- **Configuración:** Conta local `daw-proba` sen privilexios de administrador de Windows (`WindowsAdmin: false`).
- **Execución de proba (`proba.json`):**
  - Importación correcta da distribución `Debian-DAW` no espazo de usuario (`%LOCALAPPDATA%\DAW-Aula`).
  - Creación de lanzadores en `%USERPROFILE%\.local\bin` (`daw-start`, `daw-star`, `daw-start-all`, `daw-start-db`, `daw-stop`, `daw-status`, `daw-logs`, `daw-help`).
  - **Arranque web:** `daw-start` / `daw-star` levantou exclusivamente o contedor web (Apache + PHP). Resposta HTTP `200` en `http://localhost/index.php`.
  - **Arranque completo:** `daw-start-all` levantou MariaDB e phpMyAdmin. Resposta HTTP `200` en `http://localhost:8081`.
  - **Persistencia de base de datos:** Inserción dun rexistro de proba en MariaDB, parada dos servizos con `daw-stop`, novo arranque e lectura con integridade confirmada (`DatabasePersisted: true`).
  - **Idempotencia:** A reexecución do instalador non sobrescribiu nin eliminou os datos existentes da distribución.

### 6. Proba de inicio de sesión real de dominio (`RED_ALUMNOS\infdamd2`)
- **Acción:** Inicio de sesión dunha conta estándar de dominio no equipo piloto 01.
- **Resultado:**
  - A tarefa de inicio lanzou `iniciar-usuario.ps1` en segundo plano con token estándar de usuario (sen UAC nin permisos de administración).
  - Distribución `Debian-DAW` importada satisfactoriamente en `C:\Users\infdamd2\AppData\Local\DAW-Aula`.
  - Lanzadores `.cmd` rexistrados no PATH do usuario.
  - Estado confirmado en remoto como `Success: True` mediante `gestionar-aula.ps1 -Action Estado -Aula 31 -Numero 1`.

---

## Estado final e peche de seguridade

1. **Conta temporal de probas:**
   - A conta local `daw-proba` creada puntualmente para a validación no equipo 01 foi desactivada (`Enabled: False`).
2. **Sesión activa de dominio:**
   - A sesión do usuario de dominio `RED_ALUMNOS\infdamd2` mantense intacta, sen forzar reinicios nin peches de proceso.
3. **Sen credenciais residuais:**
   - Ningún contrasinal de usuario nin token persistiu en ficheiros de script ou rexistros públicos.

---

## Limitacións observadas e recomendacións

1. **Espazo e perfil local:**
   - WSL almacena o disco virtual (`ext4.vhdx`) no perfil local do equipo. Se un alumno cambia de posto de traballo, nese novo equipo iniciarase unha copia limpa do modelo e deberá sincronizar os seus proxectos mediante Git.
2. **Tempo da primeira importación:**
   - A primeira vez que un alumno inicia sesión nun equipo novo, a descompresión e importación de Debian-DAW require entre 1 e 3 minutos (segundo o rendemento do disco NVMe/SSD). Os arranques posteriores son inmediatos.
3. **Concorrencia de portos:**
   - Os servizos mapean os portos `80`, `8081` e `3306` na interface `127.0.0.1` de Windows. Débese lembrar ao alumnado que execute `daw-stop` ao rematar a sesión de clase para evitar colisións con futuros inicios no mesmo equipo.

---

## Validación do despregamento masivo na Aula 34 (11 de novembro de 2026)

Rexistro da execución completa de instalación, paralelización e verificación post-reinicio na Aula 34.

### 1. Alcance do despregamento
- **Equipo de administración (profesor):** `A34EQ100` (`172.21.34.100`), Windows 11 x64.
- **Equipos obxectivo despregados con éxito (28 postos):**  
  `A34EQ01` ata `A34EQ13`, `A34EQ15` ata `A34EQ17`, `A34EQ19` ata `A34EQ27`, `A34EQ30`, `A34EQ32` e `A34EQ33`.
- **Equipos non activos (apagados / fóra de rede):**  
  `A34EQ14`, `A34EQ18`, `A34EQ28`, `A34EQ29`, `A34EQ31`, `A34EQ34` e `A34EQ35`.

### 2. Rendemento e paralelización (`gestionar-aula-paralelo.ps1`)
- **Fase WinRM:** Habilitación secuencial mediante PsExec asinado por Microsoft (~50 s por máquina).
- **Fase WSL2:** Habilitación de características DISM e instalación do MSI oficial en lotes concorrentes de 5 equipos mediante *jobs* de PowerShell. Redución do tempo de DISM de 11 minutos por lote a só 2 minutos e 50 segundos.
- **Fase de Copia SMB:** Distribución de `debian-daw.tar.gz` (1,41 GB) e scripts en lotes paralelos de 5 equipos (~1 min por lote, ~22 MB/s por equipo sen saturar a ligazón Gigabit do profesor).
- **Reinicio remoto limpo:** Executado mediante `Invoke-Command` con `shutdown.exe /r /t 5 /f /d p:2:4` a través de WinRM, superando a limitación de `Restart-Computer` bloqueada polo cortalumes RPC (0x800706BA).

### 3. Simplificación da ruta de traballo para o alumnado (`ad`) e xestión de aula compartida
- Adaptouse `instalar-alumno.ps1` para que na importación de `Debian-DAW`:
  - Renomee de forma transparente o usuario interno a `ad` e configure `default=ad` en `/etc/wsl.conf`.
  - Enlace `/home/ad/www` cara a `/home/ad/proxectos/daw-dev/www`, permitindo o acceso directo desde Windows Explorer en `\\wsl.localhost\Debian-DAW\home\ad\www`.
  - Cree automaticamente no Escritorio de Windows o acceso directo `DAW - Proxectos (www).lnk`.
  - Manteña a ligazón de compatibilidade `/home/alumno -> /home/ad`.
- **Aulas compartidas:** Retirouse a clave `DAWAula` de `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` nos 28 equipos para evitar a execución automática en inicios de sesión de alumnos doutras materias (cero impacto, cero consumo de disco para outros cursos). A activación do contedor queda configurada baixo demanda mediante `gestionar-aula.ps1 -Action InstalarUsuario -Aula 34`.

### 4. Resultados da verificación masiva en directo (Post-Reinicio)

Execución simultánea con `Invoke-Command -ThrottleLimit 28` sobre os 28 equipos:

```text
Equipo   WSL_Plataforma  WSL_Version            Paquete_Arquivos  Paquete_Imaxe  AutoInicio_Run  Estado_Global
-------  --------------  ---------------------  ----------------  -------------  --------------  -------------
A34EQ01       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ02       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ03       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ04       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ05       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ06       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ07       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ08       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ09       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ10       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ11       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ12       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ13       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ15       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ16       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ17       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ19       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ20       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ21       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ22       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ23       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ24       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ25       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ26       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ27       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ30       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ32       True       Versión de WSL: 3.0.5.0       6               True           True           True
A34EQ33       True       Versión de WSL: 3.0.5.0       6               True           True           True
```

Taxa de éxito de verificación: **100% (28/28 equipos)**.
Todos os compoñentes de virtualización, arquivos base e integridade SHA256 atopanse plenamente operativos.

---

### 5. Integración con VS Code Dev Containers e Soporte para Aula Compartida

- **Aula compartida (Opción A):** Eliminouse a entrada de inicio automático `DAWAula` de `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` nos 28 equipos para que os alumnos doutros ciclos ou módulos non experimenten ningún atraso nin consumo de espazo no seu inicio de sesión. A preparación de `Debian-DAW` para o grupo de DAW lánzase baixo demanda polo profesorado mediante `gestionar-aula.ps1 -Action InstalarUsuario -Aula 34`.
- **Integración con Dev Containers:**
  - Engadiuse a orde `daw-code` para abrir o proxecto en VS Code con todas as rutas resoltas.
  - O instalador (`instalar-alumno.ps1`) preinstala automaticamente as extensións `ms-vscode-remote.remote-containers` e `ms-vscode-remote.remote-wsl` no perfil do alumno se VS Code está presente.
  - `.vscode/settings.json` adáptase para que `dev.containers.executeInWSLDistro` apunte a `Debian-DAW`.
  - `.devcontainer/compose.devcontainer.yaml` utiliza a imaxe precompilada local con `build: !reset null`, garantindo que premendo **«Reopen in Container»** o contedor inicie en poucos segundos sen requirir compilación nin descargas de Docker Hub.
  - Distribuíronse os scripts actualizados a tódolos equipos da aula en `C:\ProgramData\DAW-Aula\`.

---

### 6. Validación do procedemento de apagado remoto da aula

Ao rematar as probas de despregamento e validación de Aula 34, probouse e validouse o procedemento de apagado masivo da aula desde o posto do profesor (`.100`):

- **Fase 1 (WinRM en paralelo):** Apagáronse de forma simultánea os equipos activos que dispoñían de WinRM configurado polo porto 5985.
- **Fase 2 (Rescate por SMB/RPC directo e PsExec):** Os equipos 14, 18, 28, 29 e 31 non responderan por WinRM polo seguinte:
  - *Equipo 14:* Anomalía no rexistro DNS do dominio (resolvía a `172.20.14.3`), pero tiña conectividade directa en `172.21.34.14`. Apagouse mediante `PsExec` sobre o seu IP.
  - *Equipos 18, 28, 29 e 31:* Ao estaren apagados durante o despregamento inicial pola tarde, non tiñan aínda a regra de cortalumes de WinRM activa. Apagáronse de xeito instantáneo mediante `shutdown.exe /m \\172.21.34.X /s /t 0 /f` e `PsExec` sobre o porto SMB 445.
- **Verificación final:** Varrido completo de ping sobre a subrede (`172.21.34.1` a `172.21.34.35`):
  - **100% dos equipos de alumnos apagados (0 equipos con ping).**
  - **Posto docente (`.100`) preservado e en execución normal.**
- **Automatización implementada:** Creouse o script `wsl/aula/apagar-aula.ps1` e engadiuse a acción `-Action Apagar` a `gestionar-aula.ps1` para automatizar este procedemento híbrido en futuros usos.
