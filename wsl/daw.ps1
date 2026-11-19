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
        Write-Output 'Usage: daw-start | daw-start-all | daw-start-db | daw-start-angular'
        Write-Output '       daw-stop | daw-status | daw-logs | daw-code | daw-help'
        Write-Output '  daw-start: start only the web service without starting dependencies.'
        Write-Output '  daw-star: alias for daw-start.'
        Write-Output '  daw-start-all: start web, MariaDB and phpMyAdmin.'
        Write-Output '  daw-start-db: start MariaDB and the web service together.'
        Write-Output '  daw-start-angular: start the Angular container; connect VS Code by SSH to dwcc-angular.'
        Write-Output '  Other running containers are left running.'
        Write-Output '  daw-stop: stop DAW Dev containers, Angular included, without deleting data.'
        Write-Output '  daw-status: show names, status and ports, including stopped containers.'
        Write-Output '  daw-logs: follow container logs; press Ctrl+C to exit.'
        Write-Output '  daw-code: open the project in VS Code (ready for Dev Containers).'
        exit 0
    }
    'code' {
        $targetPath = if ($ProjectPath.StartsWith('/')) {
            "\\wsl.localhost\$Distribution" + ($ProjectPath -replace '/', '\')
        } else {
            $ProjectPath
        }
        $codeCmd = 'C:\Program Files\Microsoft VS Code\bin\code.cmd'
        if (-not (Test-Path -LiteralPath $codeCmd)) {
            $cmdCheck = Get-Command code -ErrorAction SilentlyContinue
            if ($cmdCheck) { $codeCmd = $cmdCheck.Source }
        }
        if (Test-Path -LiteralPath $codeCmd) {
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
    'start-angular' { $composeArgs = @('--profile', 'angular') + $startArgs + @('angular') }
    # Compose só para os servizos dun perfil se se lle indica o perfil.
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
& wsl.exe @wslArgs --cd $ProjectPath --exec docker compose @composeArgs
$composeExitCode = $LASTEXITCODE
if ($composeExitCode -eq 0 -and $Action.ToLowerInvariant() -eq 'start-angular') {
    Write-Output 'Angular is running. In VS Code: F1 > Remote-SSH: Connect to Host... > dwcc-angular,'
    Write-Output 'open /home/node/proxectos and run: ng serve --host 0.0.0.0  (http://localhost:4200)'
}
if ($composeExitCode -eq 0 -and $Action.ToLowerInvariant() -in @('start', 'start-db', 'start-all', 'start-angular')) {
    # Un proceso WSL activo evita que Debian se peche cos contedores en marcha.
    Start-Process -FilePath 'wsl.exe' -WindowStyle Hidden -ArgumentList ($wslArgs + @(
        '--cd', ('"' + $ProjectPath + '"'),
        '--exec', 'bash', 'wsl/keep-alive.sh'
    )) | Out-Null
}
exit $composeExitCode
