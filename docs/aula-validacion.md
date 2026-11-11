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
