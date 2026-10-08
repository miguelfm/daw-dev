# Preparar os equipos Windows 11 para DWCS (administración)

Este documento é para quen administra os equipos da aula. Os pasos **requiren permisos de administrador de
Windows** e fanse **unha soa vez por equipo**. O que vén despois (instalar Debian, Docker e a contorna) faino
cada alumno coa súa conta, sen permisos de administrador: [wsl2-alumnado.md](wsl2-alumnado.md).

| Quen | Que | Permisos | Cantas veces |
|---|---|---|---|
| Administración | Virtualización na BIOS/UEFI | Acceso á BIOS | Unha por equipo |
| Administración | Activar WSL2 (script `wsl/instalar-wsl-admin.ps1`) e reiniciar | Administrador de Windows | Unha por equipo |
| Alumnado | Instalar Debian, Docker Engine e a contorna DWCS | Ningún (só o seu contrasinal de Linux) | Unha por usuario |

Non se usa **Docker Desktop**: Docker Engine instálase directamente dentro de Debian, que é máis lixeiro e non
precisa licenza nin servizo en Windows.

## Requisitos dos equipos

- Windows 11 de 64 bits (probado en 25H2, compilación 26200).
- Procesador con virtualización (Intel VT-x ou AMD-V) **activada na BIOS/UEFI**.
- Recomendable 8 GB de RAM ou máis (WSL2 usa como máximo a metade da memoria do equipo).
- Uns 6 GB libres de disco por cada usuario que use a contorna (Debian, Docker e as imaxes).
- Acceso a Internet, sen bloqueo do proxy ou cortalumes do centro, a:
  - `github.com` e `objects.githubusercontent.com` (paquete de WSL e Composer)
  - os servidores de Microsoft (descarga de Debian para WSL)
  - `deb.debian.org` e `download.docker.com` (paquetes)
  - `registry-1.docker.io`, `auth.docker.io` e `production.cloudflare.docker.com` (imaxes Docker)
  - `ghcr.io` e `pkg-containers.githubusercontent.com` (imaxe PHP xa construída do proxecto)
  - `repo.packagist.org` (Composer)

## Paso 1: virtualización na BIOS/UEFI

Entra na BIOS/UEFI e activa a opción de virtualización: *Intel Virtualization Technology (VT-x)*,
*AMD-V* ou *SVM Mode*, segundo o fabricante. Moitos equipos xa a traen activada.

Para comprobalo desde Windows: *Administrador de tarefas → Rendemento → CPU → Virtualización: Habilitado*.
O script do paso 2 tamén o comproba e avisa se non está activada.

## Paso 2: activar WSL2

### Instalación local nun equipo persoal

Se preparas o teu propio equipo e vas usar a mesma conta de Windows, abre **PowerShell como administrador**:

```powershell
wsl --install -d Debian --no-launch
```

Reinicia Windows se o instalador o solicita. Despois, en PowerShell normal coa túa conta habitual:

```powershell
wsl --install -d Debian
wsl -d Debian
```

O primeiro comando completa a instalación de Debian se quedou pendente; o segundo abre a distribución.
Crea o usuario e contrasinal de Linux e continúa coa [guía do alumnado](wsl2-alumnado.md#12-descargar-o-proxecto).
Comproba `wsl --list --verbose`: Debian debe mostrar `VERSION 2`.

Durante a instalación, WSL pode indicar que a virtualización non está dispoñible ata completar o reinicio.
Se o aviso persiste despois de reiniciar, revisa a BIOS/UEFI e a característica Plataforma de máquina virtual.
Este procedemento segue a [documentación de Microsoft](https://learn.microsoft.com/en-us/windows/wsl/install).

### Preparación dos equipos da aula

O script [`wsl/instalar-wsl-admin.ps1`](../wsl/instalar-wsl-admin.ps1) fai o seguinte:

1. Comproba a virtualización.
2. Activa as características *Plataforma de máquina virtual* e *Subsistema de Windows para Linux*.
3. Instala o paquete oficial de WSL (MSI de [github.com/microsoft/WSL](https://github.com/microsoft/WSL/releases)).

Se algo xa está feito, sáltao, así que pódese executar varias veces sen problema.
Non usa `wsl --install` porque ese comando falla cando se executa en remoto (comprobado nas probas). O método
do script funciona igual en local e en remoto.

### Opción A: en cada equipo

1. Copia a carpeta `wsl/` do proxecto ao equipo (ou déixaa nunha carpeta compartida).
2. Abre **PowerShell como administrador** e executa:

   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\instalar-wsl-admin.ps1
   ```

3. Reinicia o equipo cando o script o indique. Se engades `-Reiniciar`, o script reinicia o equipo el só.

Se os equipos non teñen acceso a GitHub, descarga unha vez o `wsl.<versión>.x64.msi` desde
[as versións de WSL](https://github.com/microsoft/WSL/releases) e indícao co parámetro `-MsiPath`:

```powershell
.\instalar-wsl-admin.ps1 -MsiPath D:\wsl.3.0.1.0.x64.msi -Reiniciar
```

### Opción B: desde o equipo do profesor, en todos os equipos á vez

Con PowerShell Remoting pódese lanzar o script en todos os equipos da aula desde o equipo do profesor.

**Requisitos:**
- WinRM activado nos equipos do alumnado (`Enable-PSRemoting -Force`, ou por directiva de grupo nun dominio).
- Unha conta con permisos de administrador neses equipos.
- Fóra dun dominio, os equipos teñen que estar en `TrustedHosts` do equipo do profesor.

**Pasos:**

1. Crea un ficheiro `equipos.txt` co nome dun equipo por liña.
2. Nun PowerShell **como administrador** no equipo do profesor, desde a carpeta do proxecto:

```powershell
$equipos = Get-Content .\equipos.txt
$cred = Get-Credential          # conta de administrador dos equipos

# Con Internet nos equipos: cada un descarga WSL de GitHub
Invoke-Command -ComputerName $equipos -Credential $cred -FilePath .\wsl\instalar-wsl-admin.ps1

# Reiniciar todos e agardar a que volvan estar dispoñibles
Restart-Computer -ComputerName $equipos -Credential $cred -Force -Wait -For PowerShell
```

Sen Internet nos equipos, copia antes o MSI a cada un. Desde unha sesión remota non se pode ler unha carpeta
compartida (é o problema do «dobre salto» de credenciais), así que hai que copialo así:

```powershell
$msi = '.\wsl.3.0.1.0.x64.msi'
foreach ($pc in $equipos) {
    $s = New-PSSession -ComputerName $pc -Credential $cred
    Copy-Item $msi -Destination 'C:\Windows\Temp\' -ToSession $s
    Remove-PSSession $s
}
Invoke-Command -ComputerName $equipos -Credential $cred -FilePath .\wsl\instalar-wsl-admin.ps1 `
    -ArgumentList 'C:\Windows\Temp\wsl.3.0.1.0.x64.msi'
```

Cada liña da saída leva o nome do equipo diante (`[PC01] ...`), así que se ve doadamente en cal fallou algo.

> O script probouse en remoto mediante SSH. PowerShell Remoting usa o mesmo tipo de sesión non interactiva,
> pero non se probou nunha aula real: proba primeiro cun ou dous equipos.

## Paso 3: comprobación

Despois do reinicio, con **calquera usuario e sen administrador**:

```powershell
wsl --version
wsl --status
```

Debe mostrar a versión de WSL e `Default Version: 2`. A partir de aquí, o alumnado segue
[wsl2-alumnado.md](wsl2-alumnado.md).

## Que **non** ten que facer a administración

- **Instalar Debian para o alumnado.** As distribucións de WSL son de cada usuario de Windows: se a instala o
  administrador, só a ve o administrador.
- **Instalar Docker Desktop.** Non se usa.

## Mantemento

- **Actualizar WSL:** `wsl --update` como administrador, ou volver executar o script cun MSI máis novo.
- **Disco:** cada usuario ten o seu disco virtual en `%LOCALAPPDATA%\wsl\` (ou `%LOCALAPPDATA%\Packages\...` en
  instalacións antigas). Ocupa o que ocupen Debian e as imaxes Docker, e non se reduce só ao borrar ficheiros.

## Desinstalar

1. Cada usuario elimina a súa distribución, o que borra tamén os seus datos (sen administrador):
   `wsl --unregister Debian`
2. A administración desinstala WSL e desactiva as características:

   ```powershell
   Get-Package -Name 'Windows Subsystem for Linux*' | Uninstall-Package
   Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
   Disable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
   Restart-Computer
   ```

## Problemas habituais

| Síntoma | Causa e solución |
|---|---|
| O script di que a virtualización está desactivada | Actívaa na BIOS/UEFI (paso 1). |
| `WslRegisterDistribution failed with error: 0x80370102` ao instalar Debian | A virtualización non está activa ou falta o reinicio despois do script. |
| `wsl` responde «O Subsistema de Windows para Linux non está instalado» | Non se executou o script ou non se reiniciou o equipo. |
| As descargas fallan (Debian, Docker, imaxes) | O proxy ou o cortalumes do centro bloquean algún dominio da lista de requisitos. |
| Nun equipo concreto, `wsl --install -d Debian` pide permisos de administrador | Non debería pasar: instalar unha distribución é por usuario. Comproba que WSL está instalado (`wsl --version`). |

## Validación

O procedemento probouse en Windows 11 Pro 25H2 (compilación 26200) con WSL 3.0.1, Debian 13 e Docker Engine
29.8:

- Instalación de WSL co método do script (DISM + MSI) desde unha sesión remota.
- Contorna DWCS completa dentro de WSL, con Apache.
- Acceso desde o navegador de Windows a `http://localhost` e a phpMyAdmin.
- Xdebug con VS Code conectado a WSL.

Ademais, a instalación local con `wsl --install -d Debian --no-launch` e reinicio verificouse en Windows 11
Pro Education (compilación 26200), Debian 13, Docker Engine 29.8.2 e Compose 5.6.0. A contorna Apache superou
`scripts/comprobar.sh`, incluída a conexión de Xdebug. Portainer CE 2.45.1 conectouse ao socket Docker e
permitiu consultar os contedores; PHP e Portainer responderon desde Windows.

Non se probaron:
- Docker Desktop.
- PowerShell Remoting nunha aula real.
- A instalación de Debian cunha conta sen permisos de administrador.
- Os comandos de desinstalación desta páxina: a máquina de proba eliminouse enteira.
