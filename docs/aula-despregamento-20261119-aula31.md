# Despregamento na aula 31 (19/11/2026)

Estado dos postos da Aula 31 ao rematar a intervención do 19/11/2026, problemas atopados, solucións aplicadas e configuración de aula compartida (baixo demanda). Este repositorio é público: as contas do alumnado de cada posto rexístranse fóra del, nos documentos do docente.

## Resumo executivo

- **Subrede:** `172.21.31.0/24` | **Dominio:** `iesrodolfoucha.es` | **Equipo de xestión:** `A31EQ100` (`172.21.31.100`).
- **Postos totais no dominio:** 30 postos (`A31EQ01` a `A31EQ30`). Os postos 31 a 35 non existen no Active Directory nin no DNS do centro.
- **Postos preparados e verificados (18):** `01, 03, 04, 05, 06, 07, 08, 10, 12, 14, 16, 20, 22, 24, 25, 27, 29, 30`.
- **Postos con sesión activa de alumnado durante a intervención (11):** `02, 09, 11, 13, 15, 18, 19, 21, 23, 26, 28`. Mantivéronse intactos sen interromper o seu traballo (características Windows habilitadas en liña con `-NoRestart`; pendente completar paquete e reinicio cando queden libres).
- **Posto apagado (1):** `A31EQ17` (sen resposta ICMP; posto actualmente en reparación física polo servizo técnico).
- **Wake-on-LAN e xestión remota de enerxía:** 100% dos 29 postos operativos rexistrados con MAC en Veyon e probados con WinRM/Kerberos. Validado o ciclo completo de apagado remoto e acendido por rede en `A31EQ01` (resposta en +39 segundos).
- **Modelo de activación:** Aula compartida con outros ciclos. **Sen AutoInicio** en `HKLM Run` (impacto cero para usuarios doutros cursos). Inicialización baixo demanda mediante script lanzador (`iniciar-daw.cmd`), menú Inicio ou polo docente (`gestionar-aula.ps1 -Action InstalarUsuario`).

---

## Estado dos postos o 19/11/2026

| Postos | Estado WinRM | Características Windows | WSL 3.0.5.0 | Paquete en `C:\ProgramData\DAW-Aula` | AutoInicio (`HKLM`) | Lanzador manual |
|---|---|---|---|---|---|---|
| **01, 03, 04, 05, 06, 07, 08, 10, 12, 14, 16, 20, 22, 24, 25, 27, 29, 30** (18 postos libres) | Activo (Kerberos) | `VirtualMachinePlatform`: Enabled<br>`Microsoft-Windows-Subsystem-Linux`: Enabled (Reiniciados) | Instalado e verificado | Modelo `debian.tar.gz` (SetupRevision: 2) | Desactivado (Retirado `DAWAula`) | `iniciar-daw.cmd` e Menú Inicio (`DAW Dev`) dispoñibles |
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
- **Auditoría DNS da aula:** Auditáronse os outros 28 equipos acendidos; ningún outro posto da Aula 31 presentaba desfasamento entre o seu rexistro DNS e a IP activa.

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

### 4. Configuración de Wake-on-LAN (WoL) e saneamento de Veyon Master
- **Problema:** O docente non podía acender os equipos dos alumnos remotamente desde o posto de control (`A31EQ100`). A configuración de Veyon tiña as IPs de cada posto rexistradas pero co **enderezo MAC baleiro**, e constaban postos inexistentes (31 e 32). Sen o enderezo MAC, é imposible xerar o *Magic Packet* de Wake-on-LAN na capa de enlace de datos (L2).
- **Solución:**
  1. Durante a sesión de aula co alumnado presente, recolléronse pola táboa ARP os **29 enderezos MAC reais** dos equipos activos.
  2. Xenerouse o ficheiro de inventario `wsl/aula/a31-macs.csv` cos 30 postos (do 01 ao 16 e do 18 ao 30 coa súa MAC; o 17 sen MAC por estar en reparación).
  3. Importouse a configuración mediante `veyon-cli networkobjects import` e elimináronse os postos sobrantes (31 e 32).
  4. Saneáronse os 30 rexistros duplicados antigos sen MAC mediante `veyon-cli networkobjects remove <UID>`, deixando a aula cunha única entrada limpa por equipo.
  5. Creouse o script `wsl/aula/acender-aula.ps1` que automatiza o acendido por difusión UDP e Veyon CLI con monitorización en tempo real do tempo de resposta.

### 5. Validación experimental do ciclo completo de enerxía en `A31EQ01`
- **Apagado remoto:** Enviouse a orde por WinRM desde o equipo do profesor:
  ```powershell
  Invoke-Command -ComputerName A31EQ01 -ScriptBlock { Stop-Computer -Force }
  ```
  O equipo apagouse completamente e deixou de responder ao ping en segundos.
- **Acendido por Wake-on-LAN:** Enviouse o *Magic Packet* coa súa MAC (`e0:d5:5e:6c:d6:22`) empregando `veyon-cli power on` e difusión UDP nos portos 7 e 9.
- **Resultado:** Aos **+39 segundos**, o posto `A31EQ01` acendeu a placa base, iniciou Windows 11, recuperou a conectividade de rede e activou o servizo WinRM (`LastBootUpTime: 19/11/2026 18:34:18`).

---

## Táboa de inventario de rede e MACs (Aula 31)

| Posto | Hostname FQDN | IP | Enderezo MAC | Estado WinRM | Estado WoL |
|---|---|---|---|:---:|:---:|
| **01** | `A31EQ01.iesrodolfoucha.es` | `172.21.31.1` | `e0:d5:5e:6c:d6:22` | Operativo | Verificado |
| **02** | `A31EQ02.iesrodolfoucha.es` | `172.21.31.2` | `e0:d5:5e:6f:bc:fe` | Operativo | Operativo |
| **03** | `A31EQ03.iesrodolfoucha.es` | `172.21.31.3` | `e0:d5:5e:6f:de:dd` | Operativo | Operativo |
| **04** | `A31EQ04.iesrodolfoucha.es` | `172.21.31.4` | `e0:d5:5e:6f:dc:c8` | Operativo | Operativo |
| **05** | `A31EQ05.iesrodolfoucha.es` | `172.21.31.5` | `e0:d5:5e:6f:d7:b0` | Operativo | Operativo |
| **06** | `A31EQ06.iesrodolfoucha.es` | `172.21.31.6` | `e0:d5:5e:6f:dc:c6` | Operativo | Operativo |
| **07** | `A31EQ07.iesrodolfoucha.es` | `172.21.31.7` | `e0:d5:5e:6f:dc:a3` | Operativo | Operativo |
| **08** | `A31EQ08.iesrodolfoucha.es` | `172.21.31.8` | `e0:d5:5e:6f:d7:c6` | Operativo | Operativo |
| **09** | `A31EQ09.iesrodolfoucha.es` | `172.21.31.9` | `e0:d5:5e:6f:bd:0d` | Operativo | Operativo |
| **10** | `A31EQ10.iesrodolfoucha.es` | `172.21.31.10` | `e0:d5:5e:6e:a3:d8` | Operativo | Operativo |
| **11** | `A31EQ11.iesrodolfoucha.es` | `172.21.31.11` | `e0:d5:5e:6f:bc:a5` | Operativo | Operativo |
| **12** | `A31EQ12.iesrodolfoucha.es` | `172.21.31.12` | `e0:d5:5e:6f:d9:fc` | Operativo | Operativo |
| **13** | `A31EQ13.iesrodolfoucha.es` | `172.21.31.13` | `3c:7c:3f:2a:4e:bc` | Operativo | Operativo |
| **14** | `A31EQ14.iesrodolfoucha.es` | `172.21.31.14` | `e0:d5:5e:6f:df:a0` | Operativo | Operativo |
| **15** | `A31EQ15.iesrodolfoucha.es` | `172.21.31.15` | `e0:d5:5e:6f:a4:ad` | Operativo | Operativo |
| **16** | `A31EQ16.iesrodolfoucha.es` | `172.21.31.16` | `e0:d5:5e:6f:d7:c8` | Operativo | Operativo |
| **17** | `A31EQ17.iesrodolfoucha.es` | `172.21.31.17` | *(En reparación)* | Pendente | Pendente |
| **18** | `A31EQ18.iesrodolfoucha.es` | `172.21.31.18` | `e0:d5:5e:6f:c3:85` | Operativo | Operativo |
| **19** | `A31EQ19.iesrodolfoucha.es` | `172.21.31.19` | `e0:d5:5e:6f:b8:18` | Operativo | Operativo |
| **20** | `A31EQ20.iesrodolfoucha.es` | `172.21.31.20` | `e0:d5:5e:6f:d9:af` | Operativo | Operativo |
| **21** | `A31EQ21.iesrodolfoucha.es` | `172.21.31.21` | `e0:d5:5e:6f:d7:c4` | Operativo | Operativo |
| **22** | `A31EQ22.iesrodolfoucha.es` | `172.21.31.22` | `e0:d5:5e:6f:d7:c0` | Operativo | Operativo |
| **23** | `A31EQ23.iesrodolfoucha.es` | `172.21.31.23` | `e0:d5:5e:6f:dc:b9` | Operativo | Operativo |
| **24** | `A31EQ24.iesrodolfoucha.es` | `172.21.31.24` | `e0:d5:5e:6f:bc:d6` | Operativo | Operativo |
| **25** | `A31EQ25.iesrodolfoucha.es` | `172.21.31.25` | `e0:d5:5e:6d:04:7e` | Operativo | Operativo |
| **26** | `A31EQ26.iesrodolfoucha.es` | `172.21.31.26` | `e0:d5:5e:6f:c3:82` | Operativo | Operativo |
| **27** | `A31EQ27.iesrodolfoucha.es` | `172.21.31.27` | `e0:d5:5e:6f:9b:c4` | Operativo | Operativo |
| **28** | `A31EQ28.iesrodolfoucha.es` | `172.21.31.28` | `e0:d5:5e:6f:df:9e` | Operativo | Operativo |
| **29** | `A31EQ29.iesrodolfoucha.es` | `172.21.31.29` | `e0:d5:5e:6f:bd:12` | Operativo | Operativo |
| **30** | `A31EQ30.iesrodolfoucha.es` | `172.21.31.30` | `e0:d5:5e:6f:d7:b8` | Operativo | Operativo |

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
     1. Importa a imaxe `debian.tar.gz` en `%LOCALAPPDATA%\wsl\Debian`.
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
4. **Equipo 17:** Acender fisicamente e executar o fluxo completo.
