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

switch ($Action.ToLowerInvariant()) {
    { $_ -in 'help', '--help' } {
        Write-Output 'Usage: daw-start | daw-start-all | daw-start-db'
        Write-Output '       daw-stop | daw-status | daw-logs | daw-code | daw-help'
        Write-Output '  daw-start: start only the web service without starting dependencies.'
        Write-Output '  daw-star: alias for daw-start.'
        Write-Output '  daw-start-all: start web, MariaDB and phpMyAdmin.'
        Write-Output '  daw-start-db: start MariaDB and the web service together.'
        Write-Output '  Other running containers are left running.'
        Write-Output '  daw-stop: stop DAW Dev containers without deleting data.'
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
    'stop' { $composeArgs = @('stop') }
    'status' { $composeArgs = @('ps', '--all', '--format', 'table {{.Name}}\t{{.Status}}\t{{.Ports}}') }
    'logs' { $composeArgs = @('logs', '--tail', '100', '-f') }
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
& wsl.exe @wslArgs --cd $ProjectPath --exec docker compose @composeArgs
$composeExitCode = $LASTEXITCODE
if ($composeExitCode -eq 0 -and $Action.ToLowerInvariant() -in @('start', 'start-db', 'start-all')) {
    # Un proceso WSL activo evita que Debian se peche cos contedores en marcha.
    Start-Process -FilePath 'wsl.exe' -WindowStyle Hidden -ArgumentList ($wslArgs + @(
        '--cd', ('"' + $ProjectPath + '"'),
        '--exec', 'bash', 'wsl/keep-alive.sh'
    )) | Out-Null
}
exit $composeExitCode
