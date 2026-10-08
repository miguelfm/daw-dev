param(
    [string]$Action = 'help',
    [string]$Distribution = 'Debian'
)

$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
$startArgs = @('up', '-d', '--wait', '--wait-timeout', '300')

switch ($Action.ToLowerInvariant()) {
    { $_ -in 'help', '--help' } {
        Write-Output 'Usage: daw-dev-start | daw-dev-start-all | daw-dev-start-db'
        Write-Output '       daw-dev-stop | daw-dev-status | daw-dev-logs | daw-dev-help'
        Write-Output '  daw-dev-start: start only the web service without starting dependencies.'
        Write-Output '  daw-dev-start-all: start web, MariaDB and phpMyAdmin.'
        Write-Output '  daw-dev-start-db: start MariaDB and the web service together.'
        Write-Output '  Other running containers are left running.'
        Write-Output '  daw-dev-stop: stop DAW Dev containers without deleting data.'
        Write-Output '  daw-dev-status: show names, status and ports, including stopped containers.'
        Write-Output '  daw-dev-logs: follow container logs; press Ctrl+C to exit.'
        exit 0
    }
    'start' { $composeArgs = $startArgs + @('--no-deps', 'web') }
    'start-all' { $composeArgs = $startArgs }
    'start-db' { $composeArgs = $startArgs + @('db', 'web') }
    'stop' { $composeArgs = @('stop') }
    'status' { $composeArgs = @('ps', '--all', '--format', 'table {{.Name}}\t{{.Status}}\t{{.Ports}}') }
    'logs' { $composeArgs = @('logs', '--tail', '100', '-f') }
    default { Write-Error "Unknown command: $Action. Use: daw-dev-help"; exit 2 }
}

if (!(Test-Path -LiteralPath (Join-Path $projectPath 'compose.yaml'))) {
    throw "compose.yaml was not found in $projectPath"
}
& wsl.exe -d $Distribution --cd $projectPath -- docker compose @composeArgs
exit $LASTEXITCODE
