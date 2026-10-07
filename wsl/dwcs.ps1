param(
    [string]$Action = 'help',
    [ValidateSet('all', 'web')]
    [string]$Target = 'all',
    [string]$Distribution = 'Debian'
)

$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot

switch ($Action.ToLowerInvariant()) {
    { $_ -in 'help', '--help' } {
        Write-Output 'Usage: dwcs start [all|web] | stop | status | logs'
        Write-Output '  start / start all: start PHP, MariaDB and phpMyAdmin.'
        Write-Output '  start web: start only the web service without starting dependencies.'
        Write-Output '             Other running containers are left running.'
        Write-Output '  stop: stop DWCS containers without deleting data.'
        Write-Output '  status: show container status, including stopped containers.'
        Write-Output '  logs: follow container logs; press Ctrl+C to exit.'
        exit 0
    }
    'start' {
        $composeArgs = @('up', '-d', '--wait', '--wait-timeout', '300')
        if ($Target -eq 'web') { $composeArgs += @('--no-deps', 'web') }
    }
    'stop' { $composeArgs = @('--profile', 'mail', 'stop') }
    'status' { $composeArgs = @('--profile', 'mail', 'ps', '-a') }
    'logs' { $composeArgs = @('--profile', 'mail', 'logs', '--tail', '100', '-f') }
    default { Write-Error "Unknown command: $Action. Use: dwcs help"; exit 2 }
}

if (!(Test-Path -LiteralPath (Join-Path $projectPath 'compose.yaml'))) {
    throw "compose.yaml was not found in $projectPath"
}
& wsl.exe -d $Distribution --cd $projectPath -- docker compose @composeArgs
exit $LASTEXITCODE
