param(
    [string]$Action = 'help',
    [string]$Distribution = 'Debian',
    # Ruta absoluta dentro de Debian, ou ruta Windows da copia habitual.
    [string]$ProjectPath,
    [ValidatePattern('^[a-z_][a-z0-9_-]*$')][string]$LinuxUser
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectPath) { $ProjectPath = Split-Path -Parent $PSScriptRoot }
$wslArgs = @('-d', $Distribution)
if ($LinuxUser) { $wslArgs += @('-u', $LinuxUser) }
$startArgs = @('up', '-d', '--wait', '--wait-timeout', '300')
# Angular (DWCC): imaxe publicada e, na aula, copia no paquete para cargala sen Internet.
$angularImage = 'ghcr.io/miguelfm/dwcc-angular:22'
$angularArchive = if ($env:DAW_ANGULAR_ARCHIVE) { $env:DAW_ANGULAR_ARCHIVE } else { 'C:\ProgramData\DAW-Aula\dwcc-angular.tar.gz' }
# O paquete da aula tamén pode levar o VS Code Server (vscode-server-linux-x64.tar.gz).
$packageDirectory = Split-Path -Parent $angularArchive
$angularWorkspace = 'docker/angular/DWCC-Angular.code-workspace'
# Proxecto con cliente e servidor: angular/ e www/, cun terminal en cada contedor.
$proxectoWorkspace = 'docker/angular/DAW-Proxecto.code-workspace'

function Find-CodeCmd {
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Microsoft VS Code\bin\code.cmd'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'))) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    $found = Get-Command code -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.Source }
}

function Get-LinuxProjectPath {
    if ($ProjectPath.StartsWith('/')) { return $ProjectPath.TrimEnd('/') }
    $path = ((& wsl.exe @wslArgs --exec wslpath -u $ProjectPath) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or -not $path) { throw "Could not translate $ProjectPath to a Linux path." }
    $path
}

function Test-AngularImage {
    # A imaxe actual executa como node; a anterior, con SSH, executaba como root.
    # Formato sen comiñas: PowerShell 5.1 non as escapa nos argumentos de wsl.exe.
    $user = ((& wsl.exe @wslArgs --exec sh -c 'docker image inspect --format={{.Config.User}} $1 2>/dev/null' sh $angularImage) -join '').Trim()
    ($LASTEXITCODE -eq 0 -and $user -eq 'node')
}

function Initialize-AngularImage {
    if (Test-AngularImage) { return }
    if (Test-Path -LiteralPath $angularArchive) {
        Write-Output 'Loading the Angular image from the classroom package (only the first time)...'
        $linuxArchive = ((& wsl.exe @wslArgs --exec wslpath -u $angularArchive) -join '').Trim()
        & wsl.exe @wslArgs --exec docker load -i $linuxArchive
        if ($LASTEXITCODE -ne 0) { throw 'Could not load the Angular image.' }
        if (Test-AngularImage) { return }
        throw 'The classroom package has the previous Angular image (with SSH). Ask the teacher to update the package.'
    }
    # Fóra da aula: a imaxe publicada. Unha copia anterior (con SSH) substitúese.
    Write-Output 'Downloading the Angular image...'
    & wsl.exe @wslArgs --cd $ProjectPath --exec docker compose --profile angular pull angular
    if ($LASTEXITCODE -eq 0 -and (Test-AngularImage)) { return }
    throw 'The Angular image is missing or is the previous one (with SSH). Build it with: docker compose --profile angular build angular'
}

function Install-CodeServer {
    # Ao conectar por WSL, VS Code descarga o seu servidor desde Debian. Se xa está
    # instalado ou hai un .tar.gz do mesmo commit (paquete da aula, Descargas ou curl.exe),
    # non depende dese acceso. Se nada funciona, VS Code tenta a descarga habitual.
    param([string]$CodeCmd, [string]$LinuxProject)
    $commit = [string](@(& $CodeCmd --version) | Select-Object -Skip 1 -First 1)
    if ($commit -notmatch '^[0-9a-fA-F]{40}$') { Write-Warning 'Could not read the VS Code version; VS Code will install its server itself.'; return }
    $commit = $commit.ToLowerInvariant()
    $arch = @{ x86_64 = 'x64'; aarch64 = 'arm64' }[((& wsl.exe @wslArgs --exec uname -m) -join '').Trim()]
    $script = "$LinuxProject/wsl/vscode-server.sh"
    & wsl.exe @wslArgs --exec test -f $script
    if (-not $arch -or $LASTEXITCODE -ne 0) { Write-Warning 'VS Code will install its server itself.'; return }
    & wsl.exe @wslArgs --exec bash $script comprobar $commit
    if ($LASTEXITCODE -eq 0) { return }

    $file = "vscode-server-linux-$arch.tar.gz"
    $url = "https://update.code.visualstudio.com/commit:$commit/server-linux-$arch/stable"
    $downloads = Join-Path $env:USERPROFILE 'Downloads'
    $shellFolders = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
    if ($shellFolders.'{374DE290-123F-4565-9164-39C4925E467B}') {
        $downloads = [Environment]::ExpandEnvironmentVariables($shellFolders.'{374DE290-123F-4565-9164-39C4925E467B}')
    }
    $install = {
        param([string]$Archive)
        $linuxArchive = ((& wsl.exe @wslArgs --exec wslpath -u $Archive) -join '').Trim()
        # Out-Host: as mensaxes non se mesturan co resultado do bloque.
        & wsl.exe @wslArgs --exec bash $script instalar $commit $linuxArchive | Out-Host
        $LASTEXITCODE -eq 0
    }
    foreach ($candidate in @((Join-Path $packageDirectory $file), (Join-Path $downloads $file))) {
        if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and (& $install $candidate)) { return }
    }
    $curl = Get-Command curl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($curl) {
        $temporary = Join-Path $env:TEMP ('daw-' + [guid]::NewGuid().ToString('N') + '-' + $file)
        try {
            Write-Output 'Downloading VS Code Server (only the first time for each VS Code version)...'
            & $curl.Source --location --fail --silent --show-error --connect-timeout 15 --max-time 900 --output $temporary $url
            if ($LASTEXITCODE -eq 0 -and (& $install $temporary)) { return }
        } finally {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Warning "VS Code Server is not installed in $Distribution. VS Code will try to download it; if that fails, download $url with the browser, keep it in $downloads as $file and run daw-code-angular again."
}

function Open-AngularCode {
    param([string]$Workspace)
    $codeCmd = Find-CodeCmd
    if (-not $codeCmd) { throw 'VS Code was not found on this computer.' }
    $linuxProject = Get-LinuxProjectPath
    $workspacePath = "$linuxProject/$Workspace"
    & wsl.exe @wslArgs --exec test -f $workspacePath
    if ($LASTEXITCODE -ne 0) { throw "$workspacePath was not found. Update the project files (Activar DAW Dev)." }
    Install-CodeServer $codeCmd $linuxProject
    Write-Output "Opening VS Code in WSL: $Distribution. Its terminals run in the containers."
    & $codeCmd --new-window --remote "wsl+$Distribution" $workspacePath
    if ($LASTEXITCODE -ne 0) { throw 'VS Code could not open the workspace.' }
    Write-Output 'In the Angular terminal: ng serve --host 0.0.0.0  (http://localhost:4200)'
}

switch ($Action.ToLowerInvariant()) {
    { $_ -in 'help', '--help' } {
        Write-Output 'Usage: daw-start | daw-start-all | daw-start-db | daw-start-angular'
        Write-Output '       daw-stop | daw-status | daw-logs | daw-code | daw-code-angular | daw-help'
        Write-Output '  daw-start: start only the web service without starting dependencies.'
        Write-Output '  daw-star: alias for daw-start.'
        Write-Output '  daw-start-all: start web, MariaDB and phpMyAdmin.'
        Write-Output '  daw-start-db: start MariaDB and the web service together.'
        Write-Output '  daw-start-angular: start the Angular container (Node.js and Angular CLI).'
        Write-Output '  Other running containers are left running.'
        Write-Output '  daw-stop: stop DAW Dev containers, Angular included, without deleting data.'
        Write-Output '  daw-status: show names, status and ports, including stopped containers.'
        Write-Output '  daw-logs: follow container logs; press Ctrl+C to exit.'
        Write-Output '  daw-code: open the project in VS Code (ready for Dev Containers).'
        Write-Output '  daw-code-angular: start the Angular container and open its projects in VS Code;'
        Write-Output '    the VS Code terminal runs in the container.'
        Write-Output '  daw-code-proxecto: start web, MariaDB and Angular and open angular and www in VS Code,'
        Write-Output '    with a terminal in each container (projects with client and server).'
        exit 0
    }
    'code' {
        $targetPath = if ($ProjectPath.StartsWith('/')) {
            "\\wsl.localhost\$Distribution" + ($ProjectPath -replace '/', '\')
        } else {
            $ProjectPath
        }
        $codeCmd = Find-CodeCmd
        if ($codeCmd) {
            Start-Process -FilePath $codeCmd -ArgumentList ('"' + $targetPath + '"')
            Write-Output "VS Code aberto no proxecto: $targetPath"
            Write-Output "Para traballar no contedor, preme F1 e selecciona: Dev Containers: Reopen in Container"
        } else {
            Write-Error "Non se atopou VS Code no equipo."
        }
        exit 0
    }
    'start' { $composeArgs = $startArgs + @('--no-deps', 'web') }
    'start-all' { $composeArgs = $startArgs }
    'start-db' { $composeArgs = $startArgs + @('db', 'web') }
    { $_ -in 'start-angular', 'code-angular' } { $composeArgs = @('--profile', 'angular') + $startArgs + @('angular') }
    'code-proxecto' { $composeArgs = @('--profile', 'angular') + $startArgs + @('db', 'web', 'angular') }
    # Compose só para os servizos dun perfil se se lle indica o perfil (ps si os lista sen el).
    'stop' { $composeArgs = @('--profile', 'angular', 'stop') }
    'status' { $composeArgs = @('ps', '--all', '--format', 'table {{.Name}}\t{{.Status}}\t{{.Ports}}') }
    'logs' { $composeArgs = @('--profile', 'angular', 'logs', '--tail', '100', '-f') }
    default { Write-Error "Unknown command: $Action. Use: daw-help"; exit 2 }
}

if ($ProjectPath.StartsWith('/')) {
    & wsl.exe @wslArgs --exec test -f ($ProjectPath.TrimEnd('/') + '/compose.yaml')
    if ($LASTEXITCODE -ne 0) { throw "compose.yaml was not found in ${Distribution}:$ProjectPath" }
} elseif (!(Test-Path -LiteralPath (Join-Path $ProjectPath 'compose.yaml'))) {
    throw "compose.yaml was not found in $ProjectPath"
}
# systemd pode estar rematando o arranque de Docker cando WSL acaba de abrir.
& wsl.exe @wslArgs --exec bash -c 'for i in {1..30}; do docker info >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'
if ($LASTEXITCODE -ne 0) { throw 'Docker did not start in WSL. Ask the teacher to check the Docker service.' }
$angular = $Action.ToLowerInvariant() -in @('start-angular', 'code-angular', 'code-proxecto')
if ($angular) {
    # Os proxectos van en angular/. Se falta, Docker crearíao como root e node non podería escribir.
    if ($ProjectPath.StartsWith('/')) {
        & wsl.exe @wslArgs --cd $ProjectPath --exec mkdir -p angular
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the angular folder in the project.' }
    } else {
        New-Item -ItemType Directory -Force -Path (Join-Path $ProjectPath 'angular') | Out-Null
    }
    Initialize-AngularImage
}
& wsl.exe @wslArgs --cd $ProjectPath --exec docker compose @composeArgs
$composeExitCode = $LASTEXITCODE
if ($composeExitCode -eq 0 -and $Action.ToLowerInvariant() -in @('start', 'start-db', 'start-all', 'start-angular', 'code-angular', 'code-proxecto')) {
    # Un proceso WSL activo evita que Debian se peche cos contedores en marcha.
    Start-Process -FilePath 'wsl.exe' -WindowStyle Hidden -ArgumentList ($wslArgs + @(
        '--cd', ('"' + $ProjectPath + '"'),
        '--exec', 'bash', 'wsl/keep-alive.sh'
    )) | Out-Null
}
if ($composeExitCode -eq 0 -and $Action.ToLowerInvariant() -eq 'start-angular') {
    Write-Output 'Angular is running. Open its projects in VS Code with: daw-code-angular'
    Write-Output 'In the VS Code terminal (the container): ng serve --host 0.0.0.0  (http://localhost:4200)'
}
if ($composeExitCode -eq 0 -and $Action.ToLowerInvariant() -eq 'code-angular') { Open-AngularCode $angularWorkspace }
if ($composeExitCode -eq 0 -and $Action.ToLowerInvariant() -eq 'code-proxecto') {
    Open-AngularCode $proxectoWorkspace
    Write-Output 'PHP from www: http://localhost   phpMyAdmin: http://localhost:8081 (daw-start-all)'
}
exit $composeExitCode
