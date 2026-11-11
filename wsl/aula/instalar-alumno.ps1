#requires -Version 5.1
<#
.SYNOPSIS
Importa o modelo DAW na conta Windows do alumno e instala os comandos sen administrador.
.DESCRIPTION
Executar na sesión do alumno. Repetible: non substitúe unha distribución existente.
O paquete local debe estar protexido contra escritura do alumnado.
#>
[CmdletBinding()]
param(
    [string]$PackageDirectory = $PSScriptRoot,
    [ValidatePattern('^[a-zA-Z0-9._-]+$')][string]$Distribution = 'Debian-DAW'
)
$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
    [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
    throw 'Executa o instalador na conta do alumno, nunha consola sen elevación.'
}
$stateDir = Join-Path $env:LOCALAPPDATA 'DAW-Aula'
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
# Impide dúas importacións simultáneas na mesma conta (Veyon + inicio de sesión).
$lock = [IO.File]::Open((Join-Path $stateDir 'instalacion.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
$status = [ordered]@{ User = [Security.Principal.WindowsIdentity]::GetCurrent().Name; Distribution = $Distribution; Success = $false; Error = $null }
$transcriptStarted = $false
try {
    Start-Transcript -LiteralPath (Join-Path $stateDir 'instalacion.log') -Append | Out-Null
    $transcriptStarted = $true
    $manifest = Get-Content -LiteralPath (Join-Path $PackageDirectory 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.Schema -ne 1 -or $manifest.Marker -ne 'daw-aula-v1' -or
        $manifest.Image -notin @('debian-daw.tar','debian-daw.tar.gz') -or $manifest.Sha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        $manifest.LinuxUser -ne 'alumno' -or $manifest.LinuxProjectPath -ne '/home/alumno/proxectos/daw-dev') {
        throw 'Manifesto de modelo non recoñecido.'
    }
    $status.ModelSha256 = $manifest.Sha256
    $installed = @(& wsl.exe --list --quiet) -replace "`0", ''
    if ($LASTEXITCODE -ne 0) { throw 'WSL non está preparado. Avisa ao profesorado.' }
    $importedNow = $false
    if ($installed -notcontains $Distribution) {
        $image = Join-Path $PackageDirectory $manifest.Image
        if ((Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash -ne $manifest.Sha256) {
            throw 'O SHA256 do modelo non coincide. Non se importou Debian.'
        }
        $installDir = Join-Path $env:LOCALAPPDATA "wsl\$Distribution"
        if (Test-Path -LiteralPath $installDir) {
            if (-not (Test-Path -LiteralPath $installDir -PathType Container) -or
                (Get-Item -LiteralPath $installDir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint -or
                @(Get-ChildItem -LiteralPath $installDir -Force).Count -gt 0) {
                throw "Xa existe $installDir con contido. Non se sobrescribe."
            }
        } else { New-Item -ItemType Directory -Path $installDir -Force | Out-Null }
        & wsl.exe --import $Distribution $installDir $image --version 2
        if ($LASTEXITCODE -ne 0) { throw 'Fallou a importación. Consulta o log; non se borrou ningunha distribución.' }
        $importedNow = $true
    }
    $marker = (& wsl.exe -d $Distribution -u alumno --exec cat /etc/daw-aula-modelo) -join ''
    if ($LASTEXITCODE -ne 0 -or $marker.Trim() -ne $manifest.Marker) {
        throw 'A distribución existente non é un modelo DAW recoñecido. Non se modifica.'
    }
    # Gardar a orixe só na primeira instalación. Os modelos novos non substitúen traballos existentes.
    $originPath = Join-Path $stateDir ($Distribution + '.sha256')
    if (Test-Path -LiteralPath $originPath) {
        if ((Get-Content -LiteralPath $originPath -Raw).Trim() -ne $manifest.Sha256) {
            throw 'Esta conta usa outro modelo. A actualización dos datos existentes require un procedemento propio.'
        }
    } else { Set-Content -LiteralPath $originPath -Value $manifest.Sha256 -Encoding ASCII }
    & wsl.exe -d $Distribution -u alumno --exec bash -c 'for i in {1..60}; do docker info >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'
    if ($LASTEXITCODE -ne 0) { throw 'Docker non respondeu sen sudo na conta alumno.' }
    & wsl.exe -d $Distribution -u alumno --cd $manifest.LinuxProjectPath --exec docker compose config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'A configuración de Compose non é válida.' }
    if ($importedNow) {
        # O modelo ten os perfís Windows do repositorio apuntando a Debian. Esta copia
        # debe usar o nome rexistrado na conta do alumno. Non modifica axustes existentes.
        $settingsPath = "\\wsl.localhost\$Distribution\home\alumno\proxectos\daw-dev\.vscode\settings.json"
        $settings = [IO.File]::ReadAllText($settingsPath)
        $settings = $settings.Replace('"Debian"', ('"' + $Distribution + '"'))
        [IO.File]::WriteAllText($settingsPath, $settings, (New-Object Text.UTF8Encoding($false)))
    }
    & (Join-Path $PackageDirectory 'install-daw-commands.ps1') -Distribution $Distribution -LinuxProjectPath $manifest.LinuxProjectPath
    $status.Success = $true
    Write-Output 'Instalación rematada. Abre unha terminal nova: daw-start, daw-start-all, daw-stop, daw-status.'
} catch {
    $status.Error = $_.Exception.Message
    throw
} finally {
    $status.CheckedUtc = [DateTime]::UtcNow.ToString('o')
    $status | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stateDir 'estado.json') -Encoding UTF8
    if ($transcriptStarted) { Stop-Transcript | Out-Null }
    $lock.Dispose()
}
