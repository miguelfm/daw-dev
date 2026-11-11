[CmdletBinding()]
param(
    [string]$Distribution = 'Debian',
    [string]$LinuxProjectPath
)
$ErrorActionPreference = 'Stop'
$binPath = Join-Path $env:USERPROFILE '.local\bin'
$scriptPath = Join-Path $PSScriptRoot 'daw.ps1'
if ($Distribution -notmatch '^[a-zA-Z0-9._-]+$') { throw 'Invalid WSL distribution name.' }
if ($LinuxProjectPath) {
    if ($LinuxProjectPath -notmatch '^/[a-zA-Z0-9_./-]+$' -or $LinuxProjectPath -match '(^|/)\.\.(/|$)') {
        throw 'Use an absolute Linux project path without spaces or shell metacharacters.'
    }
    # Unha copia local evita depender dunha ruta UNC de WSL antes de arrancar Debian.
    $launcherDir = Join-Path $env:LOCALAPPDATA 'daw-dev-launcher'
    New-Item -ItemType Directory -Path $launcherDir -Force | Out-Null
    Copy-Item -LiteralPath $scriptPath -Destination (Join-Path $launcherDir 'daw.ps1') -Force
    $scriptPath = Join-Path $launcherDir 'daw.ps1'
}
New-Item -ItemType Directory -Path $binPath -Force | Out-Null

$commands = [ordered]@{
    'daw-start' = 'start'
    'daw-star' = 'start'
    'daw-start-all' = 'start-all'
    'daw-start-db' = 'start-db'
    'daw-stop' = 'stop'
    'daw-status' = 'status'
    'daw-logs' = 'logs'
    'daw-help' = 'help'
}
foreach ($entry in $commands.GetEnumerator()) {
    $wrapperPath = Join-Path $binPath ($entry.Key + '.cmd')
    $locationArgs = " -Distribution ""$Distribution"""
    if ($LinuxProjectPath) { $locationArgs += " -ProjectPath ""$LinuxProjectPath""" }
    $scriptReference = $scriptPath
    if ($LinuxProjectPath) { $scriptReference = '%LOCALAPPDATA%\daw-dev-launcher\daw.ps1' }
    $wrapper = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$scriptReference"" -Action $($entry.Value)$locationArgs %*`r`nexit /b %ERRORLEVEL%`r`n"
    # cmd.exe debe poder representar a ruta co nome de usuario de Windows.
    $cmdEncoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
    [System.IO.File]::WriteAllText($wrapperPath, $wrapper, $cmdEncoding)
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
# Explorer debe coñecer o PATH novo para as terminais abertas despois da instalación.
if (-not ('DawEnvironmentBroadcast' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DawEnvironmentBroadcast {
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg,
        UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);
}
'@
}
$broadcastResult = [UIntPtr]::Zero
$null = [DawEnvironmentBroadcast]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'Environment', 2, 2000, [ref]$broadcastResult)
Write-Output 'Open a new terminal and run: daw-help'
