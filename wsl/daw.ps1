param(
    [string]$Action = 'help',
    [string]$Distribution = 'Debian',
    # Ruta absoluta dentro de Debian, ou ruta Windows da copia habitual.
    [string]$ProjectPath,
    [ValidatePattern('^[a-z_][a-z0-9_-]*$')][string]$LinuxUser,
    [switch]$Open,
    [switch]$Local
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectPath) { $ProjectPath = Split-Path -Parent $PSScriptRoot }
$wslArgs = @('-d', $Distribution)
if ($LinuxUser) { $wslArgs += @('-u', $LinuxUser) }
$startArgs = @('up', '-d', '--wait', '--wait-timeout', '300')
# Angular (DWCC): imaxe publicada e, na aula, copia no paquete para cargala sen Internet.
$angularImage = 'ghcr.io/miguelfm/dwcc-angular:22'
$angularArchive = if ($env:DAW_ANGULAR_ARCHIVE) { $env:DAW_ANGULAR_ARCHIVE } else { 'C:\ProgramData\DAW-Aula\dwcc-angular.tar.gz' }
# Documentación sen conexión (daw-doc): na aula, as tres imaxes van no paquete.
$docImages = [ordered]@{
    'ghcr.io/miguelfm/daw-doc-php:en' = 'daw-doc-php.tar.gz'
    'ghcr.io/miguelfm/daw-doc-devdocs:latest' = 'daw-doc-devdocs.tar.gz'
    'ghcr.io/miguelfm/daw-doc-laravel:13.x' = 'daw-doc-laravel.tar.gz'
}
$docArchiveDirectory = if ($env:DAW_DOC_ARCHIVES) { $env:DAW_DOC_ARCHIVES } else { 'C:\ProgramData\DAW-Aula' }

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

switch ($Action.ToLowerInvariant()) {
    { $_ -in 'help', '--help' } {
        Write-Output 'Usage: daw-start | daw-start-all | daw-start-db | daw-start-angular | daw-start-doc'
        Write-Output '       daw-stop | daw-stop-all | daw-stop-doc | daw-status | daw-logs | daw-code'
        Write-Output '       daw-web-shell | daw-wsl-shell | daw-web-root [-Open] | daw-help'
        Write-Output '  daw-start: start only the web service without starting dependencies.'
        Write-Output '  daw-star: alias for daw-start.'
        Write-Output '  daw-start-all: start web, MariaDB and phpMyAdmin.'
        Write-Output '  daw-start-db: start MariaDB and the web service together.'
        Write-Output '  daw-start-angular: start the Angular container; connect VS Code by SSH to dwcc-angular.'
        Write-Output '  daw-start-doc: start the offline PHP manual (8080), DevDocs (5042) and Laravel docs (8088).'
        Write-Output '  Other running containers are left running.'
        Write-Output '  daw-stop: stop DAW Dev containers, Angular and the docs included, without deleting data.'
        Write-Output '  daw-stop-all: stop all containers: development, documentation and Angular.'
        Write-Output '  daw-stop-doc: stop only the offline documentation containers.'
        Write-Output '  daw-status: show names, status and ports, including stopped containers.'
        Write-Output '  daw-logs: follow container logs; press Ctrl+C to exit.'
        Write-Output '  daw-web-shell: open Bash in the Apache/PHP web container as user ad.'
        Write-Output '  daw-shell: alias for daw-web-shell.'
        Write-Output '  daw-wsl-shell: open Debian in WSL at the project directory without starting Docker.'
        Write-Output '  daw-code: open the project in VS Code; add -Local to edit in Windows without VS Code Server.'
        Write-Output '  daw-web-root: show the Windows and Debian paths to the Apache web root.'
        Write-Output '                Add -Open to open the Windows path in File Explorer.'
        Write-Output '  daw-www: show only the Windows path (also accepts -Open).'
        exit 0
    }
    'code' {
        $targetPath = $ProjectPath
        $useWslRemote = $ProjectPath.StartsWith('/') -and -not $Local
        $codeArgs = if ($useWslRemote) {
            @('--remote', ('"wsl+' + $Distribution + '"'), ('"' + $ProjectPath.TrimEnd('/') + '/"'))
        } else {
            if ($ProjectPath.StartsWith('/')) {
                & wsl.exe @wslArgs --exec test -d $ProjectPath
                if ($LASTEXITCODE -ne 0) { throw "The project directory is unavailable in ${Distribution}:$ProjectPath" }
                $targetPath = "\\wsl.localhost\$Distribution" + ($ProjectPath -replace '/', '\')
            }
            '"' + $targetPath + '"'
        }
        $codeCmd = 'C:\Program Files\Microsoft VS Code\bin\code.cmd'
        if (-not (Test-Path -LiteralPath $codeCmd)) {
            $cmdCheck = Get-Command code -ErrorAction SilentlyContinue
            if ($cmdCheck) { $codeCmd = $cmdCheck.Source }
        }
        if (Test-Path -LiteralPath $codeCmd) {
            Start-Process -FilePath $codeCmd -ArgumentList $codeArgs
            Write-Output "VS Code aberto no proxecto: $targetPath"
            if ($Local) {
                Write-Output 'Local editing in Windows. Use daw-web-shell for PHP and Composer.'
            } else {
                Write-Output "Para traballar no contedor, preme F1 e selecciona: Dev Containers: Reopen in Container"
            }
        } else {
            Write-Error "Non se atopou VS Code no equipo."
        }
        exit 0
    }
    'wsl-shell' {
        & wsl.exe @wslArgs --cd $ProjectPath
        exit $LASTEXITCODE
    }
    'start' { $composeArgs = $startArgs + @('--no-deps', 'web') }
    'start-all' { $composeArgs = $startArgs }
    'start-db' { $composeArgs = $startArgs + @('db', 'web') }
    'start-angular' { $composeArgs = @('--profile', 'angular') + $startArgs + @('angular') }
    'start-doc' { $composeArgs = @('--profile', 'doc') + $startArgs + @('doc-php', 'doc-devdocs', 'doc-laravel') }
    # Compose só para os servizos dun perfil se se lle indica o perfil.
    'stop' { $composeArgs = @('--profile', 'angular', '--profile', 'doc', 'stop') }
    'stop-all' { $composeArgs = @('--profile', 'angular', '--profile', 'doc', 'stop') }
    'stop-doc' { $composeArgs = @('--profile', 'doc', 'stop', 'doc-php', 'doc-devdocs', 'doc-laravel') }
    'status' { $composeArgs = @('ps', '--all', '--format', 'table {{.Name}}\t{{.Status}}\t{{.Ports}}') }
    'logs' { $composeArgs = @('--profile', 'angular', '--profile', 'doc', 'logs', '--tail', '100', '-f') }
    'shell' { $composeArgs = @('exec', '-u', 'ad', 'web', 'bash') }
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
        $webRoots = @('/var/www/html', '/home/ad/html')
        $containers = @(& wsl.exe @wslArgs --cd $ProjectPath --exec docker compose ps --all --quiet web)
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

        # Excluír contedores temporais de `docker compose run`.
        $mountJson = if ($containers.Count) {
            $mountFormat = '{{if ne (index .Config.Labels `com.docker.compose.oneoff`) `True`}}{{json .Mounts}}{{end}}'
            $inspect = & wsl.exe @wslArgs --exec docker inspect --type container --format $mountFormat @containers
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            $inspect | Where-Object { $_ }
        }
        $sources = if ($mountJson) {
            foreach ($entry in $mountJson) {
                $mounts = ConvertFrom-Json -InputObject $entry
                $mounts | Where-Object { $_.Type -eq 'bind' -and $_.Destination -cin $webRoots } | ForEach-Object { $_.Source }
            }
        } else {
            $config = & wsl.exe @wslArgs --cd $ProjectPath --exec docker compose config --format json web
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            ($config -join "`n" | ConvertFrom-Json).services.web.volumes |
                Where-Object { $_.type -eq 'bind' -and $_.target -cin $webRoots } | ForEach-Object { $_.source }
        }
        if (-not $sources) { throw 'The web service has no host directory mounted at /var/www/html or /home/ad/html.' }
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
if ($Action.ToLowerInvariant().StartsWith('start')) {
    # Un .env anterior ao 24-11-2026 leva o contrasinal por defecto anterior de MariaDB.
    & wsl.exe @wslArgs --cd $ProjectPath --exec bash scripts/daw.sh migrar-env
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not check the MariaDB password in .env.' }
}
if ($Action.ToLowerInvariant() -eq 'start-angular') {
    # A chave pública vai ao proxecto (docker/angular/chave.pub); os proxectos, a angular/.
    $pub = Initialize-AngularKey
    if ($pub -notmatch '^(ssh-ed25519) ([A-Za-z0-9+/=]+)(\s.*)?$') { throw 'Unexpected format of dwcc_angular.pub.' }
    if ($ProjectPath.StartsWith('/')) {
        # Tipo e chave como argumentos: unha canalización a wsl.exe pode engadir un BOM,
        # e sshd non recoñece entón a liña de authorized_keys.
        & wsl.exe @wslArgs --cd $ProjectPath --exec sh -c 'mkdir -p angular docker/angular && echo $1 $2 > docker/angular/chave.pub' sh $Matches[1] $Matches[2]
        if ($LASTEXITCODE -ne 0) { throw 'Could not copy the public key to the project.' }
    } else {
        New-Item -ItemType Directory -Force -Path (Join-Path $ProjectPath 'angular'), (Join-Path $ProjectPath 'docker\angular') | Out-Null
        [IO.File]::WriteAllText((Join-Path $ProjectPath 'docker\angular\chave.pub'), $pub + "`n", (New-Object Text.UTF8Encoding($false)))
    }
    # A redirección vai en sh: en PowerShell 5.1, redirixir stderr dun programa con Stop é un erro.
    & wsl.exe @wslArgs --exec sh -c 'docker image inspect $1 >/dev/null 2>&1' sh $angularImage
    if ($LASTEXITCODE -ne 0 -and (Test-Path -LiteralPath $angularArchive)) {
        Write-Output 'Loading the Angular image from the classroom package (only the first time)...'
        $linuxArchive = ((& wsl.exe @wslArgs --exec wslpath -u $angularArchive) -join '').Trim()
        & wsl.exe @wslArgs --exec docker load -i $linuxArchive
        if ($LASTEXITCODE -ne 0) { throw 'Could not load the Angular image.' }
    }
}
if ($Action.ToLowerInvariant() -eq 'start-doc') {
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
& wsl.exe @wslArgs --cd $ProjectPath --exec docker compose @composeArgs
$composeExitCode = $LASTEXITCODE
if ($composeExitCode -eq 0 -and $Action.ToLowerInvariant() -eq 'start-angular') {
    Write-Output 'Angular is running. In VS Code: F1 > Remote-SSH: Connect to Host... > dwcc-angular,'
    Write-Output 'open /home/node/proxectos and run: ng serve --host 0.0.0.0  (http://localhost:4200)'
}
if ($composeExitCode -eq 0 -and $Action.ToLowerInvariant() -eq 'start-doc') {
    Write-Output 'PHP manual: http://localhost:8080/   DevDocs: http://localhost:5042/   Laravel: http://localhost:8088/'
}
if ($composeExitCode -eq 0 -and $Action.ToLowerInvariant() -in @('start', 'start-db', 'start-all', 'start-angular', 'start-doc')) {
    # Un proceso WSL activo evita que Debian se peche cos contedores en marcha.
    Start-Process -FilePath 'wsl.exe' -WindowStyle Hidden -ArgumentList ($wslArgs + @(
        '--cd', ('"' + $ProjectPath + '"'),
        '--exec', 'bash', 'wsl/keep-alive.sh'
    )) | Out-Null
}
exit $composeExitCode
