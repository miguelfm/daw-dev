#requires -Version 5.1
<#
.SYNOPSIS
Importa o modelo DAW na conta Windows do alumno e instala os comandos sen administrador.
Configura o usuario Linux 'ad' e a ruta directa \\wsl.localhost\Debian-DAW\home\ad\www.
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
        $manifest.LinuxUser -notin @('alumno', 'ad')) {
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

    # Configuración e migración ao usuario 'ad' e ruta /home/ad/www
    & wsl.exe -d $Distribution -u root --exec bash -c '
        if id alumno >/dev/null 2>&1; then
            pkill -u alumno 2>/dev/null || true
            usermod -l ad -d /home/ad -m alumno
            groupmod -n ad alumno 2>/dev/null || true
            ln -sfn /home/ad /home/alumno
        fi
        mkdir -p /home/ad/proxectos/daw-dev/www
        ln -sfn /home/ad/proxectos/daw-dev/www /home/ad/www
        chown -h ad:ad /home/ad/www 2>/dev/null || true
        chown -R ad:ad /home/ad 2>/dev/null || true
        
        # Configurar ad como usuario predeterminado de WSL
        if [ -f /etc/wsl.conf ]; then
            sed -i "/default *=/d" /etc/wsl.conf
            sed -i "/\[user\]/d" /etc/wsl.conf
        fi
        printf "\n[user]\ndefault=ad\n" >> /etc/wsl.conf
    '

    $marker = (& wsl.exe -d $Distribution -u ad --exec cat /etc/daw-aula-modelo) -join ''
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

    & wsl.exe -d $Distribution -u ad --exec bash -c 'for i in {1..60}; do docker info >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'
    if ($LASTEXITCODE -ne 0) { throw 'Docker non respondeu sen sudo na conta ad.' }
    & wsl.exe -d $Distribution -u ad --cd /home/ad/proxectos/daw-dev --exec docker compose config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'A configuración de Compose non é válida.' }
    if ($importedNow) {
        $settingsPath = "\\wsl.localhost\$Distribution\home\ad\proxectos\daw-dev\.vscode\settings.json"
        if (Test-Path -LiteralPath $settingsPath) {
            $settings = [IO.File]::ReadAllText($settingsPath)
            $settings = $settings.Replace('"Debian"', ('"' + $Distribution + '"'))
            [IO.File]::WriteAllText($settingsPath, $settings, (New-Object Text.UTF8Encoding($false)))
        }
    }
    & (Join-Path $PackageDirectory 'install-daw-commands.ps1') -Distribution $Distribution -LinuxProjectPath '/home/ad/proxectos/daw-dev'

    # Preinstalar extensións de VS Code para Dev Containers e WSL se VS Code está dispoñible
    try {
        $codePath = 'C:\Program Files\Microsoft VS Code\bin\code.cmd'
        if (-not (Test-Path -LiteralPath $codePath)) {
            $cmdCheck = Get-Command code -ErrorAction SilentlyContinue
            if ($cmdCheck) { $codePath = $cmdCheck.Source }
        }
        if (Test-Path -LiteralPath $codePath) {
            & $codePath --install-extension ms-vscode-remote.remote-containers --force | Out-Null
            & $codePath --install-extension ms-vscode-remote.remote-wsl --force | Out-Null
        }
    } catch { }

    # Crear acceso directo no Escritorio de Windows apuntando a \\wsl.localhost\Debian-DAW\home\ad\www
    try {
        $desktopPath = [Environment]::GetFolderPath('Desktop')
        if (Test-Path -LiteralPath $desktopPath) {
            $wsh = New-Object -ComObject WScript.Shell
            $shortcut = $wsh.CreateShortcut((Join-Path $desktopPath 'DAW - Proxectos (www).lnk'))
            $shortcut.TargetPath = "\\wsl.localhost\$Distribution\home\ad\www"
            $shortcut.Description = "Cartafol de proxectos web DAW Dev (Document Root)"
            $shortcut.Save()
        }
    } catch { }

    $status.Success = $true
    Write-Output 'Instalación rematada. Abre unha terminal nova: daw-start, daw-start-all, daw-stop, daw-status.'
    Write-Output "Ruta rápida de proxectos web: \\wsl.localhost\$Distribution\home\ad\www"
} catch {
    $status.Error = $_.Exception.Message
    throw
} finally {
    $status.CheckedUtc = [DateTime]::UtcNow.ToString('o')
    $status | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stateDir 'estado.json') -Encoding UTF8
    if ($transcriptStarted) { Stop-Transcript | Out-Null }
    $lock.Dispose()
}
