#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Prepara un equipo Windows 11 para a contorna DAW Dev: activa WSL2. Require administrador.

.DESCRIPTION
    1. Comproba que a virtualización por hardware está dispoñible.
    2. Activa as características de Windows VirtualMachinePlatform e Microsoft-Windows-Subsystem-Linux.
    3. Instala o paquete oficial de WSL (MSI de github.com/microsoft/WSL).
    Despois hai que reiniciar o equipo.

    Non usa `wsl --install` porque falla en sesións remotas (PowerShell Remoting, SSH);
    este método funciona igual en local e en remoto.

.PARAMETER MsiPath
    Ruta a un wsl.<versión>.x64.msi xa descargado (carpeta compartida, USB...).
    Sen este parámetro descárgase a última versión de GitHub.

.PARAMETER Reiniciar
    Reinicia o equipo ao rematar, se fai falta.

.EXAMPLE
    .\instalar-wsl-admin.ps1
.EXAMPLE
    .\instalar-wsl-admin.ps1 -MsiPath \\servidor\dwcs\wsl.3.0.1.0.x64.msi -Reiniciar
#>
param(
    [string]$MsiPath,
    [switch]$Reiniciar
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$env:WSL_UTF8 = 1
$equipo = $env:COMPUTERNAME
function Info($m) { Write-Output "[$equipo] $m" }

# 1. Virtualización por hardware (VT-x / AMD-V activada na BIOS/UEFI)
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$hipervisor = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
if (-not $cpu.VirtualizationFirmwareEnabled -and -not $hipervisor) {
    throw "[$equipo] A virtualización está desactivada na BIOS/UEFI (Intel VT-x / AMD-V / SVM). Actívaa e volve executar o script."
}
Info "Virtualización dispoñible."

# 2. Características de Windows
$reinicio = $false
foreach ($f in 'VirtualMachinePlatform', 'Microsoft-Windows-Subsystem-Linux') {
    $estado = (Get-WindowsOptionalFeature -Online -FeatureName $f).State
    if ($estado -eq 'Enabled') {
        Info "$f xa estaba activada."
    } else {
        $r = Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart
        if ($r.RestartNeeded) { $reinicio = $true }
        Info "$f activada."
    }
}

# 3. Paquete de WSL
$wslInstalado = $false
try { wsl.exe --version *> $null; $wslInstalado = ($LASTEXITCODE -eq 0) } catch { }
if ($wslInstalado) {
    Info "WSL xa estaba instalado: $((wsl.exe --version | Select-Object -First 1))"
} else {
    if (-not $MsiPath) {
        $rel = Invoke-RestMethod https://api.github.com/repos/microsoft/WSL/releases/latest
        $asset = $rel.assets | Where-Object name -like '*.x64.msi' | Select-Object -First 1
        $MsiPath = Join-Path $env:TEMP $asset.name
        Info "Descargando WSL $($rel.tag_name)..."
        Invoke-WebRequest -UseBasicParsing $asset.browser_download_url -OutFile $MsiPath
    }
    Info "Instalando $(Split-Path $MsiPath -Leaf)..."
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$MsiPath`" /qn /norestart" -Wait -PassThru
    if ($p.ExitCode -notin 0, 3010) { throw "[$equipo] msiexec rematou co código $($p.ExitCode)" }
    if ($p.ExitCode -eq 3010) { $reinicio = $true }
    Info "WSL instalado."
}

if ($reinicio) {
    if ($Reiniciar) { Info "Reiniciando..."; Restart-Computer -Force }
    else { Info "FEITO. Reinicia o equipo para rematar a instalación." }
} else {
    Info "FEITO. Non fai falta reiniciar."
}
