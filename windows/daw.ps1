param(
    [string]$Action = 'help',
    [string]$Distribution = 'Debian',
    # Ruta absoluta dentro de Debian, ou ruta Windows da copia habitual.
    [string]$ProjectPath,
    [ValidatePattern('^[a-z_][a-z0-9_-]*$')][string]$LinuxUser,
    [switch]$Open,
    [switch]$Local,
    [switch]$Container,
    [string]$PackageDirectory,
    [switch]$SkipVSCode,
    # daw-activate: substitúe a distribución doutro paquete e borra todo o seu contido.
    [switch]$Reinstall
)

$ErrorActionPreference = 'Stop'
# Ruta literal: a variable ProgramData non existe fóra de Windows (probas en Linux).
$classroomPackage = if ($env:DAW_PACKAGE_DIR) { $env:DAW_PACKAGE_DIR } else { 'C:\ProgramData\DAW-Dev' }
if (-not $ProjectPath) { $ProjectPath = Split-Path -Parent $PSScriptRoot }
$wslArgs = @('-d', $Distribution)
if ($LinuxUser) { $wslArgs += @('-u', $LinuxUser) }
# Angular (DWCC): imaxe publicada e, na aula, copia no paquete para cargala sen Internet.
# Ata o 27-11-2026 a imaxe era dwcc-angular:22: un paquete anterior trae ese arquivo, e
# scripts/daw.sh renomea a imaxe anterior que xa estea na distribución.
$angularImages = @('ghcr.io/miguelfm/daw-angular:22', 'ghcr.io/miguelfm/dwcc-angular:22')
$angularArchive = if ($env:DAW_ANGULAR_ARCHIVE) { $env:DAW_ANGULAR_ARCHIVE } else {
    @("$classroomPackage\daw-angular.tar.gz", "$classroomPackage\dwcc-angular.tar.gz") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
# Documentación sen conexión (daw-doc): na aula, as tres imaxes van no paquete.
$docImages = [ordered]@{
    'ghcr.io/miguelfm/daw-doc-php:en' = 'daw-doc-php.tar.gz'
    'ghcr.io/miguelfm/daw-doc-devdocs:latest' = 'daw-doc-devdocs.tar.gz'
    'ghcr.io/miguelfm/daw-doc-laravel:13.x' = 'daw-doc-laravel.tar.gz'
}
$docArchiveDirectory = if ($env:DAW_DOC_ARCHIVES) { $env:DAW_DOC_ARCHIVES } else { $classroomPackage }

function Initialize-AngularKey {
    # Chave da conta de Windows e entrada dwcc-angular de ~/.ssh/config, só a primeira vez.
    $sshDir = if ($env:DAW_SSH_DIR) { $env:DAW_SSH_DIR } else { Join-Path $HOME '.ssh' }
    New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
    $key = Join-Path $sshDir 'dwcc_angular'
    if (-not (Test-Path -LiteralPath "$key.pub")) {
        if (Test-Path -LiteralPath $key) { throw "$key exists without $key.pub. Rename it and try again." }
        $keygen = Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue
        if (-not $keygen) { throw 'The Windows OpenSSH client (ssh-keygen) is not installed.' }
        # Argumentos nunha soa cadea: -N "" (sen frase de paso) chega igual en PowerShell 5.1 e 7.
        $keyArgs = '-q -t ed25519 -N "" -C dwcc-angular -f "' + $key + '"'
        $p = Start-Process -FilePath $keygen.Source -ArgumentList $keyArgs -NoNewWindow -Wait -PassThru
        if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath "$key.pub")) { throw 'ssh-keygen could not create the dwcc_angular key.' }
    }
    $config = Join-Path $sshDir 'config'
    $text = if (Test-Path -LiteralPath $config) { [IO.File]::ReadAllText($config) } else { '' }
    if ($text -notmatch '(?im)^\s*Host\s+dwcc-angular\s*$') {
        $identity = if ($env:DAW_SSH_DIR) { '"' + $key + '"' } else { '~/.ssh/dwcc_angular' }
        $nl = "`r`n"
        $block = "Host dwcc-angular$nl    HostName 127.0.0.1$nl    Port 2222$nl    User node$nl    IdentityFile $identity$nl    IdentitiesOnly yes$nl"
        if ($text -and -not $text.EndsWith("`n")) { $block = $nl + $block }
        [IO.File]::AppendAllText($config, $block, (New-Object Text.UTF8Encoding($false)))
    }
    ([IO.File]::ReadAllText("$key.pub")).Trim()
}

function Get-DawWslDevContainerUri([string]$HostPath, [string]$LinuxWorkspacePath, [string]$ContainerWorkspaceFolder) {
    $cleanWorkspace = $LinuxWorkspacePath.TrimEnd('/')
    $cleanContainer = if ($ContainerWorkspaceFolder) { $ContainerWorkspaceFolder.TrimEnd('/') } else { $cleanWorkspace }
    $workspace = [ordered]@{
        hostPath = $HostPath
        localDocker = $false
        configFile = [ordered]@{
            '$mid' = 1
            path = "$cleanWorkspace/.devcontainer/devcontainer.json"
            scheme = 'vscode-fileHost'
        }
    }
    $json = ConvertTo-Json -InputObject $workspace -Depth 4 -Compress
    $authority = [BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($json)).Replace('-', '').ToLowerInvariant()
    $path = ($cleanContainer -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    "vscode-remote://dev-container+$authority$path"
}

function Get-DawDevContainerCommand([string]$CodeExe, [string]$CodeCommand) {
    $extensions = Join-Path $env:USERPROFILE '.vscode\extensions'
    $extension = Get-ChildItem -LiteralPath $extensions -Directory -Filter 'ms-vscode-remote.remote-containers-*' -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'dev-containers-user-cli\bin\devcontainer.cmd') -PathType Leaf } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $extension) { throw 'The Dev Containers extension is required for daw-code -Container.' }
    $cliLine = [regex]::Match([IO.File]::ReadAllText($CodeCommand), '%~dp0([^"%]*?resources\\app\\out\\cli\.js)')
    if (-not $cliLine.Success) { throw 'Could not determine the current VS Code app directory.' }
    $cliPath = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $CodeCommand) $cliLine.Groups[1].Value))
    if (-not (Test-Path -LiteralPath $cliPath -PathType Leaf)) { throw 'The current VS Code CLI was not found.' }
    $appRoot = Split-Path -Parent (Split-Path -Parent $cliPath)
    # The official Dev Containers CLI reads these files next to its Windows shim.
    # Keep a DAW-specific shim so the extension's usual CLI is left to VS Code.
    $directory = Join-Path $env:APPDATA 'Code\User\globalStorage\ms-vscode-remote.remote-containers\daw-cli-bin'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $metadata = @{
        'vscode-app-root' = $appRoot
        'vscode-path' = $CodeExe
        'vscode-quality' = 'stable'
        'remote-containers-path' = $extension.FullName
    }
    foreach ($entry in $metadata.GetEnumerator()) {
        [IO.File]::WriteAllText((Join-Path $directory $entry.Key), $entry.Value, (New-Object Text.UTF8Encoding($false)))
    }
    $shim = Join-Path $directory 'devcontainer.cmd'
    Copy-Item -LiteralPath (Join-Path $extension.FullName 'dev-containers-user-cli\bin\devcontainer.cmd') -Destination $shim -Force
    return $shim
}

function Initialize-DawCodeCache([string]$CodeExe, [switch]$ForContainer) {
    # Na aula, o paquete leva o VS Code Server do commit dos postos: evita descargalo
    # (e os timeouts da rede) en Remote - WSL e en Dev Containers. Noutros equipos non hai paquete.
    $module = Join-Path $classroomPackage 'daw-classroom.psm1'
    if (-not (Test-Path -LiteralPath $module -PathType Leaf)) { return }
    try {
        Import-Module $module -Force
        $result = Initialize-DawCodeServer -Distribution $Distribution -Code $CodeExe -PackageDirectory $classroomPackage -ForContainer:$ForContainer
        if ($result.Status -eq 'Missing') {
            Write-Warning "The classroom package has no VS Code Server for commit $($result.Commit); VS Code will download it."
        }
    } catch {
        Write-Warning "Could not prepare the classroom VS Code Server: $($_.Exception.Message)"
    }
}

# Repón os lanzadores daw-* que falten e o PATH, sen tocar os existentes: unha instalación
# anterior recibe así as ordes novas (como daw-activate) ao usar calquera delas.
$launcherInstaller = Join-Path $PSScriptRoot 'install-daw-commands.ps1'
if ($env:USERPROFILE -and -not $env:DAW_SKIP_LAUNCHER_REPAIR -and (Test-Path -LiteralPath $launcherInstaller -PathType Leaf)) {
    $repairArgs = @{ Distribution = $Distribution; Repair = $true }
    if ($ProjectPath.StartsWith('/')) { $repairArgs.LinuxProjectPath = $ProjectPath }
    if ($LinuxUser) { $repairArgs.LinuxUser = $LinuxUser }
    try { & $launcherInstaller @repairArgs | Out-Null }
    catch { Write-Warning "Could not restore the missing daw-* launchers: $($_.Exception.Message)" }
}

switch ($Action.ToLowerInvariant()) {
    { $_ -in 'help', '--help' } {
        Write-Output 'Usage: daw-start | daw-start-all | daw-start-db | daw-start-frontend | daw-start-doc'
        Write-Output '       daw-stop | daw-stop-all | daw-stop-doc | daw-status | daw-logs | daw-code'
        Write-Output '       daw-shell | daw-wsl-shell | daw-web-root [-Open] | daw-activate | daw-help'
        Write-Output '  daw-activate: install or update the classroom setup from its deployed package.'
        Write-Output '                -Reinstall replaces a distribution from another package and deletes all its files.'
        Write-Output '  daw-start: start only the backend (PHP and Apache) without starting dependencies.'
        Write-Output '  daw-star: alias for daw-start.'
        Write-Output '  daw-start-all: start backend, db (MariaDB) and db-admin (phpMyAdmin).'
        Write-Output '  daw-start-db: start MariaDB and the backend together.'
        Write-Output '  daw-start-frontend: start the frontend (Angular); connect VS Code by SSH to dwcc-angular.'
        Write-Output '  daw-start-angular: alias for daw-start-frontend.'
        Write-Output '  daw-start-doc: start the offline docs: PHP (8080), web: HTML, HTTP and CSS (5042) and Laravel (8088).'
        Write-Output '  Other running containers are left running.'
        Write-Output '  daw-stop: stop DAW Dev containers, frontend and docs included, without deleting data.'
        Write-Output '  daw-stop-all: stop all containers: backend, db, db-admin, frontend and docs.'
        Write-Output '  daw-stop-doc: stop only the offline documentation containers.'
        Write-Output '  daw-status: show names, status and ports, including stopped containers.'
        Write-Output '  daw-logs: follow container logs; press Ctrl+C to exit.'
        Write-Output '  daw-shell: open Bash in the backend (Apache and PHP) as user ad.'
        Write-Output '  daw-web-shell: alias for daw-shell.'
        Write-Output '  daw-wsl-shell: open the WSL distribution at your home (html, data, angular) or project, without starting Docker.'
        Write-Output '  daw-code: open the project directly in VS Code.'
        Write-Output '  daw-code -Container: open the project directly in its PHP Dev Container.'
        Write-Output '  daw-code -Local: edit in Windows without VS Code Server.'
        Write-Output '  daw-web-root: show the Windows and WSL paths to the Apache web root.'
        Write-Output '                Add -Open to open the Windows path in File Explorer.'
        Write-Output '  daw-www: show only the Windows path (also accepts -Open).'
        Write-Output '  Containers: backend-c, db-c, db-admin-c, frontend-c, doc-php-c, doc-web-c and doc-laravel-c.'
        exit 0
    }
    'activate' {
        $package = if ($PackageDirectory) { $PackageDirectory } else { $classroomPackage }
        $activator = Join-Path $package 'activate.ps1'
        if (-not (Test-Path -LiteralPath $activator -PathType Leaf)) {
            throw "The classroom package has not been deployed to $package."
        }
        & $activator -Distribution $Distribution -Reinstall:$Reinstall -SkipVSCode:$SkipVSCode -NoPause
        exit $LASTEXITCODE
    }
    'code' {
        if ($Local -and $Container) { throw 'Choose either -Local or -Container.' }
        $codeCmd = 'C:\Program Files\Microsoft VS Code\bin\code.cmd'
        if (-not (Test-Path -LiteralPath $codeCmd -PathType Leaf)) {
            $command = Get-Command code.cmd -ErrorAction SilentlyContinue
            if (-not $command) { throw 'Non se atopou VS Code no equipo.' }
            $codeCmd = $command.Source
        }
        $codeExe = Join-Path (Split-Path -Parent (Split-Path -Parent $codeCmd)) 'Code.exe'
        if (-not (Test-Path -LiteralPath $codeExe -PathType Leaf)) { throw 'Non se atopou Code.exe.' }

        $targetPath = $ProjectPath
        $workspacePath = $ProjectPath
        $useWslRemote = $ProjectPath.StartsWith('/') -and -not $Local
        if ($ProjectPath.StartsWith('/')) {
            & wsl.exe @wslArgs --exec test -d $ProjectPath
            if ($LASTEXITCODE -ne 0) { throw "The project directory is unavailable in ${Distribution}:$ProjectPath" }
            # Na aula, a contorna está en ~/.daw e o espazo de traballo de VS Code é o código web,
            # ~/html, coa súa configuración (.vscode e .devcontainer).
            if ($ProjectPath.TrimEnd('/') -match '^(.*)/\.daw$') {
                $html = $Matches[1] + '/html'
                & wsl.exe @wslArgs --exec test -d "$html/.devcontainer"
                if ($LASTEXITCODE -eq 0) { $workspacePath = $html }
            }
            if ($workspacePath.Length -gt 1) { $workspacePath = $workspacePath.TrimEnd('/') }
            $targetPath = "\\wsl.localhost\$Distribution" + ($workspacePath -replace '/', '\')
        }
        if ($useWslRemote) { Initialize-DawCodeCache $codeExe -ForContainer:$Container }
        if ($Container) {
            if ($useWslRemote) {
                $extensions = Join-Path $env:USERPROFILE '.vscode\extensions'
                $extension = Get-ChildItem -LiteralPath $extensions -Directory -Filter 'ms-vscode-remote.remote-containers-*' -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                if (-not $extension) { throw 'The Dev Containers extension is required for daw-code -Container.' }
                # Tamén o fai initializeCommand, pero desde Windows pode non chegar a WSL: retira o
                # contedor web que non teña a definición actual do Dev Container, que o reutilizaría.
                & wsl.exe @wslArgs --cd $ProjectPath --exec bash scripts/daw.sh prepare-devcontainer
                if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not check the web container before opening the Dev Container.' }
                $rawConfig = & wsl.exe @wslArgs --exec cat "$workspacePath/.devcontainer/devcontainer.json"
                if ($LASTEXITCODE -ne 0) {
                    throw "devcontainer.json was not found in ${Distribution}:$workspacePath/.devcontainer"
                }
                $containerFolder = $workspacePath
                try {
                    $configJson = ($rawConfig | Where-Object { $_ -notmatch '^\s*//' }) -join "`n" | ConvertFrom-Json
                    if ($configJson.workspaceFolder -and $configJson.workspaceFolder.StartsWith('/')) {
                        $containerFolder = $configJson.workspaceFolder.TrimEnd('/')
                    }
                } catch { }
                # En WSL, a CLI de Dev Containers falla en VS Code >= 1.122 con rutas \\wsl.localhost
                # (ERR_UNC_HOST_NOT_ALLOWED) e non pasa localDocker=false nin configFile: ábrese co URI directo.
                $uri = Get-DawWslDevContainerUri -HostPath $targetPath -LinuxWorkspacePath $workspacePath -ContainerWorkspaceFolder $containerFolder
                Start-Process -FilePath $codeExe -ArgumentList @('--folder-uri', $uri) -WorkingDirectory $env:USERPROFILE
                exit 0
            }
            $devContainer = Get-DawDevContainerCommand $codeExe $codeCmd
            # Tamén o fai initializeCommand, pero desde Windows pode non chegar a WSL: retira o
            # contedor web que non teña a definición actual do Dev Container, que o reutilizaría.
            & wsl.exe @wslArgs --cd $ProjectPath --exec bash scripts/daw.sh prepare-devcontainer
            if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not check the web container before opening the Dev Container.' }
            & $devContainer open $targetPath --disable-telemetry
            exit $LASTEXITCODE
        }
        $codeArgs = if ($useWslRemote) {
            $path = ($workspacePath -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
            @('--folder-uri', "vscode-remote://wsl+$Distribution$path")
        } else {
            '"' + $targetPath + '"'
        }
        Start-Process -FilePath $codeExe -ArgumentList $codeArgs -WorkingDirectory $env:USERPROFILE
        exit 0
    }
    'wsl-shell' {
        # Na aula, o home (html, data e angular), non a contorna oculta en ~/.daw.
        $shellPath = if ($ProjectPath.TrimEnd('/') -match '^(.*)/\.daw$') { $Matches[1] } else { $ProjectPath }
        & wsl.exe @wslArgs --cd $shellPath
        exit $LASTEXITCODE
    }
    # Compose vai sempre por scripts/daw.sh do proxecto. Este script non nomea servizos, así que
    # vale tamén cun proxecto doutra versión, por exemplo antes ou despois dun UpdateProject.
    { $_ -in 'start', 'start-all', 'start-db', 'start-doc', 'stop', 'stop-all', 'stop-doc', 'status', 'logs' } { $dawAction = $_ }
    { $_ -in 'start-frontend', 'start-angular' } { $dawAction = 'start-frontend' }
    'shell' { $dawAction = 'web-shell' }
    { $_ -in 'web-root', 'www' } { }
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
if ($Action -in 'web-root', 'www') {
    $previousEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
        # As rutas en Linux, de scripts/daw.sh: le as montaxes do backend ou, sen contedor, Compose.
        $sources = @(& wsl.exe @wslArgs --cd $ProjectPath --exec bash scripts/daw.sh web-root | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        if (-not $sources) { throw 'The backend has no host directory mounted at /var/www/html.' }
        $paths = foreach ($source in ($sources | Select-Object -Unique)) {
            $windowsPath = & wsl.exe @wslArgs --exec wslpath -w $source
            if ($LASTEXITCODE -ne 0 -or -not $windowsPath) { throw "Could not translate the web directory to a Windows path: $source" }
            [pscustomobject]@{ Windows = $windowsPath; Debian = $source }
        }
    } finally {
        [Console]::OutputEncoding = $previousEncoding
    }
    foreach ($path in $paths) {
        Write-Output $path.Windows
        if ($Action -eq 'web-root') { Write-Output $path.Debian }
        if ($Open) { Invoke-Item -LiteralPath $path.Windows }
    }
    exit 0
}
if ($dawAction -eq 'start-frontend') {
    # A chave pública vai ao proxecto (docker/angular/ssh-key.pub); os proxectos, a angular/.
    $pub = Initialize-AngularKey
    if ($pub -notmatch '^(ssh-ed25519) ([A-Za-z0-9+/=]+)(\s.*)?$') { throw 'Unexpected format of dwcc_angular.pub.' }
    $keyType = $Matches[1]
    $keyBody = $Matches[2]
    if ($ProjectPath.StartsWith('/')) {
        # Tipo e chave como argumentos: unha canalización a wsl.exe pode engadir un BOM,
        # e sshd non recoñece entón a liña de authorized_keys.
        # Na aula (~/.daw), os proxectos de Angular van en ../angular, non en ~/.daw/angular.
        $angularDir = if ($ProjectPath.TrimEnd('/').EndsWith('/.daw')) { '../angular' } else { 'angular' }
        & wsl.exe @wslArgs --cd $ProjectPath --exec sh -c 'mkdir -p "$1" docker/angular && echo "$2" "$3" > docker/angular/ssh-key.pub' sh $angularDir $keyType $keyBody
        if ($LASTEXITCODE -ne 0) { throw 'Could not copy the public key to the project.' }
    } else {
        New-Item -ItemType Directory -Force -Path (Join-Path $ProjectPath 'angular'), (Join-Path $ProjectPath 'docker\angular') | Out-Null
        [IO.File]::WriteAllText((Join-Path $ProjectPath 'docker\angular\ssh-key.pub'), $pub + "`n", (New-Object Text.UTF8Encoding($false)))
    }
    # A redirección vai en sh: en PowerShell 5.1, redirixir stderr dun programa con Stop é un erro.
    & wsl.exe @wslArgs --exec sh -c 'docker image inspect "$1" >/dev/null 2>&1 || docker image inspect "$2" >/dev/null 2>&1' sh @angularImages
    if ($LASTEXITCODE -ne 0 -and $angularArchive -and (Test-Path -LiteralPath $angularArchive)) {
        Write-Output 'Loading the Angular image from the classroom package (only the first time)...'
        $linuxArchive = ((& wsl.exe @wslArgs --exec wslpath -u $angularArchive) -join '').Trim()
        & wsl.exe @wslArgs --exec docker load -i $linuxArchive
        if ($LASTEXITCODE -ne 0) { throw 'Could not load the Angular image.' }
    }
}
if ($dawAction -eq 'start-doc') {
    foreach ($image in $docImages.Keys) {
        $archive = Join-Path $docArchiveDirectory $docImages[$image]
        & wsl.exe @wslArgs --exec sh -c 'docker image inspect $1 >/dev/null 2>&1' sh $image
        if ($LASTEXITCODE -ne 0 -and (Test-Path -LiteralPath $archive)) {
            Write-Output "Loading $image from the classroom package (only the first time)..."
            $linuxArchive = ((& wsl.exe @wslArgs --exec wslpath -u $archive) -join '').Trim()
            & wsl.exe @wslArgs --exec docker load -i $linuxArchive
            if ($LASTEXITCODE -ne 0) { throw "Could not load $image." }
        }
    }
}
# scripts/daw.sh decide como arrancar cada servizo (por exemplo, non recrea un Dev Container
# aberto) e migra a .env e os servizos anteriores: a mesma lóxica en Linux e en Windows.
# DAW_SKIP_SSH_SETUP: a chave de Angular é a da conta de Windows, que xa se copiou.
& wsl.exe @wslArgs --cd $ProjectPath --exec env DAW_SKIP_SSH_SETUP=1 bash scripts/daw.sh $dawAction
$composeExitCode = $LASTEXITCODE
if ($composeExitCode -eq 2 -and $dawAction -eq 'start-frontend') {
    # Un proxecto anterior ao 27-11-2026, sen UpdateProject: o servizo chamábase angular.
    & wsl.exe @wslArgs --cd $ProjectPath --exec docker compose --profile angular up -d --wait --wait-timeout 300 angular
    $composeExitCode = $LASTEXITCODE
}
if ($composeExitCode -eq 0 -and $dawAction -in @('start', 'start-db', 'start-all', 'start-frontend', 'start-doc')) {
    # Un proceso WSL activo evita que Debian se peche cos contedores en marcha.
    Start-Process -FilePath 'wsl.exe' -WindowStyle Hidden -ArgumentList ($wslArgs + @(
        '--cd', ('"' + $ProjectPath + '"'),
        '--exec', 'bash', 'scripts/keep-alive.sh'
    )) | Out-Null
}
exit $composeExitCode
