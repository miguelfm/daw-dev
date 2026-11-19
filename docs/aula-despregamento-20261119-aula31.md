# Despregamento na aula 31 (19/11/2026)

Estado dos postos da Aula 31 ao rematar a intervención do 19/11/2026, problemas atopados, solucións aplicadas e configuración de aula compartida (baixo demanda). Este repositorio é público: as contas do alumnado de cada posto rexístranse fóra del, nos documentos do docente.

## Resumo executivo

- **Subrede:** `172.21.31.0/24` | **Dominio:** `iesrodolfoucha.es` | **Equipo de xestión:** `A31EQ100` (`172.21.31.100`).
- **Postos totais no dominio:** 30 postos (`A31EQ01` a `A31EQ30`). Os postos 31 a 35 non existen no Active Directory nin no DNS do centro.
- **Postos preparados e verificados (18):** `01, 03, 04, 05, 06, 07, 08, 10, 12, 14, 16, 20, 22, 24, 25, 27, 29, 30`.
- **Postos con sesión activa de alumnado durante a intervención (11):** `02, 09, 11, 13, 15, 18, 19, 21, 23, 26, 28`. Mantivéronse intactos sen interromper o seu traballo (características Windows habilitadas en liña con `-NoRestart`; pendente completar paquete e reinicio cando queden libres).
- **Posto apagado (1):** `A31EQ17` (sen resposta ICMP).
- **Modelo de activación:** Aula compartida con outros ciclos. **Sen AutoInicio** en `HKLM Run` (impacto cero para usuarios doutros cursos). Inicialización baixo demanda mediante script lanzador (`iniciar-daw.cmd`), menú Inicio ou polo docente (`gestionar-aula.ps1 -Action InstalarUsuario`).

---

## Estado dos postos o 19/11/2026

| Postos | Estado WinRM | Características Windows | WSL 3.0.5.0 | Paquete en `C:\ProgramData\DAW-Aula` | AutoInicio (`HKLM`) | Lanzador manual |
|---|---|---|---|---|---|---|
| **01, 03, 04, 05, 06, 07, 08, 10, 12, 14, 16, 20, 22, 24, 25, 27, 29, 30** (18 postos libres) | Activo (Kerberos) | `VirtualMachinePlatform`: Enabled<br>`Microsoft-Windows-Subsystem-Linux`: Enabled (Reiniciados) | Instalado e verificado | Modelo `debian-daw.tar.gz` (SetupRevision: 2) | Desactivado (Retirado `DAWAula`) | `iniciar-daw.cmd` e Menú Inicio (`DAW Dev`) dispoñibles |
| **02, 09, 11, 13, 15, 18, 19, 21, 23, 26, 28** (11 postos con sesión activa) | Activo (Kerberos) | `VirtualMachinePlatform`: Enabled<br>`Microsoft-Windows-Subsystem-Linux`: Enabled (`-NoRestart`, require reinicio) | Pendente de instalar MSI | Pendente de copia | Non configurado | Pendente |
| **17** | Apagado | Pendente | Pendente | Pendente | Non configurado | Pendente |

---

## Incidencias atopadas e solucións

### 1. Incoherencia de DNS e fallo Kerberos en `A31EQ02`
- **Problema:** Ao intentar conectar por WinRM a `A31EQ02.iesrodolfoucha.es`, a conexión fallaba co erro `WSManFault 2150859046: The destination computer is unknown`. O servidor DNS institucional (`172.30.1.4`) devolvía a IP antiga `172.20.2.12`, mentres o posto tiña asignada a IP `172.21.31.2`. Kerberos rexeitaba o ticket de servizo ao non coincidir o SPN co host real.
- **Solución:** Engadiuse a resolución directa no ficheiro `hosts` local do equipo de xestión (`A31EQ100`):
  ```text
  172.21.31.2 A31EQ02.iesrodolfoucha.es A31EQ02
  ```
  Con isto, a autenticación Kerberos e WinRM acadaron o 100% de éxito.
- **Auditoría DNS da aula:** Auditáronse os outros 28 equipos encendidos; ningún outro posto da Aula 31 presentaba desfasamento entre o seu rexistro DNS e a IP activa.

### 2. Porto WinRM pechado nos postos 05 e 29
- **Problema:** Os postos `A31EQ05` e `A31EQ29` respondían a ICMP pero tiñan o porto 5985 pechado.
- **Solución:** Habilitouse o servizo remotamente mediante PsExec64 asinado por Microsoft:
  ```powershell
  .\wsl\aula\gestionar-aula.ps1 -Action HabilitarWinRM -Aula 31 -Numero @(5, 29)
  ```
  Ambos os postos quedaron inmediatamente operativos con WinRM e autenticación Kerberos.

### 3. Actualización de integridade do paquete (`SetupRevision: 2`)
- **Problema:** A copia inicial rexeitaba o paquete `daw-aula-paquete-20261111-final` mediante `Assert-DawPackage` porque os scripts foran actualizados con posterioridade ao cómputo de hashes do `manifest.json`.
- **Solución:** Executouse `actualizar-paquete.ps1` no paquete local antes de proceder á réplica nos 18 postos, rexistrando as sinaturas SHA-256 actuais con `SetupRevision: 2`.

---

## Modelo de aula compartida (Activación baixo demanda)

A Aula 31 é utilizada por diversos cursos e materias que non precisan nin deben interactuar con contedores Docker nin co subsistema Linux. Para garantir a convivencia:

1. **Retirada de `DAWAula` en `HKLM Run`:**
   - Eliminouse a entrada `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\DAWAula` dos 18 equipos preparados.
   - Cando un alumno alleo inicia sesión, Windows non executa ningún script nin proceso de comprobación. Non se xera atraso no inicio de sesión nin consumo de disco no perfil do usuario (`%LOCALAPPDATA%\wsl`).

2. **Lanzador manual para o alumnado de DAW (`iniciar-daw.cmd`):**
   - Instalouse en `C:\ProgramData\DAW-Aula\iniciar-daw.cmd` (con permisos de lectura e execución para o grupo `Users`).
   - Creouse o acceso directo en `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\DAW Dev\Inicializar DAW Dev.lnk`.
   - Ao executarse sen elevación polo alumno conectado:
     1. Importa a imaxe `debian-daw.tar.gz` en `%LOCALAPPDATA%\wsl\Debian-DAW`.
     2. Configura o usuario Linux `ad` (contrasinal `abc123..`).
     3. Arranca o servizo Docker e valida `docker info` e o Compose do proxecto.
     4. Xera os scripts CLI de control (`daw-start`, `daw-stop`, etc.) no seu `%USERPROFILE%\.local\bin`.
     5. Coloca o acceso directo `DAW - Proxectos (www).lnk` no escritorio dese alumno.

3. **Activación remota polo profesor:**
   - Cando os alumnos de DAW estean sentados nos seus postos, o docente pode lanzar a activación interactiva cunha soa orde desde `A31EQ100`:
     ```powershell
     .\wsl\aula\gestionar-aula.ps1 -Action InstalarUsuario -Aula 31
     ```

---

## Procedemento para completar os equipos restantes

Unha vez que os alumnos desconecten dos 11 equipos ocupados (`02, 09, 11, 13, 15, 18, 19, 21, 23, 26, 28`):

1. **Instalar MSI de WSL e copiar paquete:**
   ```powershell
   $pendentes = @(2, 9, 11, 13, 15, 18, 19, 21, 23, 26, 28)
   # Copiar e instalar wsl.3.0.5.0.x64.msi en remoto
   # Copiar C:\ProgramData\DAW-Aula desde o paquete actualizado
   ```
2. **Reiniciar equipos para consolidar características:**
   ```powershell
   $hosts = $pendentes | ForEach-Object { "A31EQ{0:D2}.iesrodolfoucha.es" -f $_ }
   Invoke-Command -ComputerName $hosts -Authentication Kerberos -ScriptBlock {
       shutdown.exe /r /t 5 /f /d p:2:4
   }
   ```
3. **Desactivar AutoInicio e engadir `iniciar-daw.cmd`:**
   Executar o script `scratch/despregar_iniciar_daw.ps1` adaptado para eses 11 postos.
4. **Equipo 17:** Encender fisicamente e executar o fluxo completo.
