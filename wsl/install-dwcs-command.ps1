$ErrorActionPreference = 'Stop'
$binPath = Join-Path $env:USERPROFILE '.local\bin'
$scriptPath = Join-Path $PSScriptRoot 'dwcs.ps1'
New-Item -ItemType Directory -Path $binPath -Force | Out-Null

$wrapper = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$scriptPath"" %*`r`nexit /b %ERRORLEVEL%`r`n"
[System.IO.File]::WriteAllText((Join-Path $binPath 'dwcs.cmd'), $wrapper, [System.Text.Encoding]::Default)

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$entries = @($userPath -split ';' | Where-Object { $_ })
if ($entries.TrimEnd('\') -notcontains $binPath.TrimEnd('\')) {
    [Environment]::SetEnvironmentVariable('Path', (($entries + $binPath) -join ';'), 'User')
}
if (($env:Path -split ';').TrimEnd('\') -notcontains $binPath.TrimEnd('\')) {
    $env:Path += ";$binPath"
}
Write-Output "Installed: $binPath\dwcs.cmd"
Write-Output 'Open a new terminal and run: dwcs help'
