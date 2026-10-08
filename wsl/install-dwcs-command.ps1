$ErrorActionPreference = 'Stop'
$binPath = Join-Path $env:USERPROFILE '.local\bin'
$scriptPath = Join-Path $PSScriptRoot 'dwcs.ps1'
New-Item -ItemType Directory -Path $binPath -Force | Out-Null

$commands = [ordered]@{
    'dwcs-start' = 'start'
    'dwcs-start-all' = 'start-all'
    'dwcs-start-db' = 'start-db'
    'dwcs-stop' = 'stop'
    'dwcs-status' = 'status'
    'dwcs-logs' = 'logs'
    'dwcs-help' = 'help'
}
foreach ($entry in $commands.GetEnumerator()) {
    $wrapperPath = Join-Path $binPath ($entry.Key + '.cmd')
    $wrapper = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$scriptPath"" -Action $($entry.Value) %*`r`nexit /b %ERRORLEVEL%`r`n"
    [System.IO.File]::WriteAllText($wrapperPath, $wrapper, [System.Text.Encoding]::Default)
    Write-Output "Installed: $wrapperPath"
}

# Remove the old launcher only if it belongs to this checkout.
$legacyPath = Join-Path $binPath 'dwcs.cmd'
if (Test-Path -LiteralPath $legacyPath) {
    $legacyContent = [System.IO.File]::ReadAllText($legacyPath)
    if ($legacyContent.Contains("-File ""$scriptPath"" %*")) {
        Remove-Item -LiteralPath $legacyPath
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
Write-Output 'Open a new terminal and run: dwcs-help'
