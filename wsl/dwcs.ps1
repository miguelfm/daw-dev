param(
    [string]$Action = 'help',
    [ValidateSet('all', 'web', 'db')]
    [string]$Target = 'web',
    [string]$Distribution = 'Debian'
)

$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot

switch ($Action.ToLowerInvariant()) {
    { $_ -in 'help', '--help' } {
        Write-Output 'Usage: dwcs start [web|db|all] | stop | status | logs'
        Write-Output '  start / start web: start only the web service without starting dependencies.'
        Write-Output '  start db: start MariaDB and the web service together.'
        Write-Output '  start all: start PHP, MariaDB, phpMyAdmin and Mailpit.'
        Write-Output '             Other running containers are left running.'
        Write-Output '  stop: stop DWCS containers without deleting data.'
        Write-Output '  status: show container status, including stopped containers.'
        Write-Output '  logs: follow container logs; press Ctrl+C to exit.'
        exit 0
    }
    'start' {
        $composeArgs = @('up', '-d', '--wait', '--wait-timeout', '300')
        if ($Target -eq 'web') { $composeArgs += @('--no-deps', 'web') }
        elseif ($Target -eq 'db') { $composeArgs += @('db', 'web') }
        elseif ($Target -eq 'all') { $composeArgs = @('--profile', 'mail') + $composeArgs }
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
