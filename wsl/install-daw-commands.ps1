$ErrorActionPreference = 'Stop'
$binPath = Join-Path $env:USERPROFILE '.local\bin'
$scriptPath = Join-Path $PSScriptRoot 'daw.ps1'
New-Item -ItemType Directory -Path $binPath -Force | Out-Null

$commands = [ordered]@{
    'daw-start' = 'start'
    'daw-start-all' = 'start-all'
    'daw-start-db' = 'start-db'
    'daw-stop' = 'stop'
    'daw-status' = 'status'
    'daw-logs' = 'logs'
    'daw-help' = 'help'
}
foreach ($entry in $commands.GetEnumerator()) {
    $wrapperPath = Join-Path $binPath ($entry.Key + '.cmd')
    $wrapper = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$scriptPath"" -Action $($entry.Value) %*`r`nexit /b %ERRORLEVEL%`r`n"
    [System.IO.File]::WriteAllText($wrapperPath, $wrapper, [System.Text.Encoding]::Default)
    Write-Output "Installed: $wrapperPath"
}

# Remove old launchers only when they target this checkout or its old directory.
$projectPath = Split-Path -Parent $PSScriptRoot
$projectsPath = Split-Path -Parent $projectPath
$legacyScriptPaths = @(
    $scriptPath
    (Join-Path $PSScriptRoot 'dwcs.ps1')
    (Join-Path $PSScriptRoot 'daw-dev.ps1')
    (Join-Path $projectsPath 'dwcs-php\wsl\dwcs.ps1')
)
$legacyNames = @('dwcs', 'dwcs-start', 'dwcs-start-all', 'dwcs-start-db', 'dwcs-stop', 'dwcs-status', 'dwcs-logs', 'dwcs-help', 'daw-dev-start', 'daw-dev-start-all', 'daw-dev-start-db', 'daw-dev-stop', 'daw-dev-status', 'daw-dev-logs', 'daw-dev-help')
foreach ($legacyName in $legacyNames) {
    $legacyPath = Join-Path $binPath ($legacyName + '.cmd')
    if (Test-Path -LiteralPath $legacyPath) {
        $legacyContent = [System.IO.File]::ReadAllText($legacyPath)
        foreach ($legacyScriptPath in $legacyScriptPaths) {
            if ($legacyContent.Contains("-File ""$legacyScriptPath""")) {
                Remove-Item -LiteralPath $legacyPath
                break
            }
        }
    }
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$entries = @($userPath -split ';' | Where-Object { $_ })
if (@($entries | ForEach-Object { $_.TrimEnd('\') }) -notcontains $binPath.TrimEnd('\')) {
    [Environment]::SetEnvironmentVariable('Path', (($entries + $binPath) -join ';'), 'User')
}
if (($env:Path -split ';').TrimEnd('\') -notcontains $binPath.TrimEnd('\')) {
    $env:Path += ";$binPath"
}
Write-Output 'Open a new terminal and run: daw-help'
