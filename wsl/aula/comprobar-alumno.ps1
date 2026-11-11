#requires -Version 5.1
<#
.SYNOPSIS
Proba de integración para unha conta de proba: arranca/para servizos e verifica a persistencia.
.DESCRIPTION
Executar sen elevación DESPOIS de instalar o modelo. Usa a configuración predeterminada
da aula. Crea e elimina unha táboa de proba. Ao rematar deixa os contedores parados.
#>
[CmdletBinding()]
param([string]$Distribution = 'Debian-DAW')
$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'A proba debe executarse sen elevación.' }
$stateDir = Join-Path $env:LOCALAPPDATA 'DAW-Aula'
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
Start-Transcript -LiteralPath (Join-Path $stateDir 'proba.log') -Append | Out-Null
$report = [ordered]@{ User = [Security.Principal.WindowsIdentity]::GetCurrent().Name; WindowsAdmin = $false; Success = $false; Error = $null }
$token = [Guid]::NewGuid().ToString('N')
$project = '/home/alumno/proxectos/daw-dev'
$fixture = (& wsl.exe -d $Distribution --exec wslpath -a -u (Join-Path $PSScriptRoot 'proba-persistencia.sh')) -join ''
$fixture = $fixture.Trim()
function Invoke-NativeChecked([scriptblock]$Command) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Command 2>&1 | ForEach-Object { "$_" }; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    if ($code -ne 0) { throw "A orde rematou con $code" }
}
function Daw([string]$Name) {
    $path = Join-Path $env:USERPROFILE ".local\bin\$Name.cmd"
    Invoke-NativeChecked { & $path }
}
try {
    $report.LinuxUid = ((& wsl.exe -d $Distribution --exec id -u) -join '').Trim()
    if ($report.LinuxUid -ne '1000') { throw 'O usuario Linux predeterminado non é alumno (UID 1000).' }
    $report.DockerVersion = ((& wsl.exe -d $Distribution --exec docker version --format '{{.Server.Version}}') -join '').Trim()
    $report.ComposeVersion = ((& wsl.exe -d $Distribution --exec docker compose version) -join '').Trim()
    Daw 'daw-start'
    $running = @(& wsl.exe -d $Distribution --cd $project --exec docker compose ps --status running --services | Where-Object { $_.Trim() })
    if ($running.Count -ne 1 -or $running[0].Trim() -ne 'web') { throw 'daw-start non deixou só o web na conta de proba.' }
    $report.WebOnly = $true
    Daw 'daw-stop'
    Daw 'daw-star'
    $report.StartAlias = $true
    Daw 'daw-start-all'
    $report.WebHttpStatus = (Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost/index.php' -TimeoutSec 15).StatusCode
    $report.PhpMyAdminStatus = (Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:8081' -TimeoutSec 15).StatusCode
    Invoke-NativeChecked { & wsl.exe -d $Distribution --exec bash $fixture write $token }
    Daw 'daw-stop'
    Daw 'daw-start-all'
    $saved = ((& wsl.exe -d $Distribution --exec bash $fixture read $token) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or $saved -ne $token) { throw 'Non se conservou a proba de BD entre parada e arranque.' }
    $report.DatabasePersisted = $true
    Invoke-NativeChecked { & wsl.exe -d $Distribution --exec bash $fixture clean $token }
    $before = ((& wsl.exe -d $Distribution --exec cat /etc/machine-id) -join '').Trim()
    # Reinstalar os lanzadores non debe alterar a distribución nin o seu identificador.
    & (Join-Path $PSScriptRoot 'instalar-alumno.ps1') -PackageDirectory $PSScriptRoot
    $after = ((& wsl.exe -d $Distribution --exec cat /etc/machine-id) -join '').Trim()
    if ($before -ne $after) { throw 'Reexecutar a instalación substituíu a distribución.' }
    $report.ReinstallPreservedDistribution = $true
    Daw 'daw-status'
    Daw 'daw-stop'
    $running = @(& wsl.exe -d $Distribution --cd $project --exec docker compose ps --status running --services | Where-Object { $_.Trim() })
    if ($running.Count -ne 0) { throw 'daw-stop deixou servizos en marcha.' }
    $report.StopPreservedContainers = @(& wsl.exe -d $Distribution --cd $project --exec docker compose ps --all --services | Where-Object { $_.Trim() }).Count -eq 3
    if (-not $report.StopPreservedContainers) { throw 'daw-stop non conservou os tres contedores.' }
    $report.Success = $true
} catch { $report.Error = $_.Exception.Message; throw }
finally {
    $report.CheckedUtc = [DateTime]::UtcNow.ToString('o')
    $report | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stateDir 'proba.json') -Encoding UTF8
    Stop-Transcript | Out-Null
}
