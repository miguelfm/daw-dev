[CmdletBinding()]
param(
    [string]$Distribution = 'Debian',
    [string]$LinuxProjectPath,
    [ValidatePattern('^[a-z_][a-z0-9_-]*$')][string]$LinuxUser,
    # Só crea os lanzadores que faltan e garante o PATH; non substitúe nin borra ningún.
    [switch]$Repair
)
$ErrorActionPreference = 'Stop'
$binPath = Join-Path $env:USERPROFILE '.local\bin'
$scriptPath = Join-Path $PSScriptRoot 'daw.ps1'
# Copia local dos lanzadores da aula, en %LOCALAPPDATA%.
$launcherName = 'daw-dev-launcher'
if ($Distribution -notmatch '^[a-zA-Z0-9._-]+$') { throw 'Invalid WSL distribution name.' }
if ($LinuxProjectPath) {
    if ($LinuxProjectPath -notmatch '^/[a-zA-Z0-9_./-]+$' -or $LinuxProjectPath -match '(^|/)\.\.(/|$)') {
        throw 'Use an absolute Linux project path without spaces or shell metacharacters.'
    }
    # Unha copia local evita depender dunha ruta UNC de WSL antes de arrancar Debian.
    # O instalador vai con ela para que daw.ps1 poida repoñer os lanzadores que falten.
    $launcherDir = Join-Path $env:LOCALAPPDATA $launcherName
    New-Item -ItemType Directory -Path $launcherDir -Force | Out-Null
    foreach ($name in 'daw.ps1', 'install-daw-commands.ps1') {
        $source = Join-Path $PSScriptRoot $name
        $target = Join-Path $launcherDir $name
        if ([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($target)) {
            Copy-Item -LiteralPath $source -Destination $target -Force
        }
    }
    $scriptPath = Join-Path $launcherDir 'daw.ps1'
}
New-Item -ItemType Directory -Path $binPath -Force | Out-Null

function Add-DawUserPath {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @($userPath -split ';' | Where-Object { $_ })
    $changed = $false
    # As probas non deben cambiar o PATH real da conta: só o do proceso.
    if (-not $env:DAW_SKIP_USER_PATH -and @($entries | ForEach-Object { $_.TrimEnd('\') }) -notcontains $binPath.TrimEnd('\')) {
        [Environment]::SetEnvironmentVariable('Path', (($entries + $binPath) -join ';'), 'User')
        $changed = $true
    }
    if (($env:Path -split ';').TrimEnd('\') -notcontains $binPath.TrimEnd('\')) {
        $env:Path += ";$binPath"
    }
    return $changed
}
function Send-DawEnvironmentChange {
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
}

$commands = [ordered]@{
    'daw-activate' = 'activate'
    'daw-start' = 'start'
    'daw-star' = 'start'
    'daw-start-all' = 'start-all'
    'daw-start-db' = 'start-db'
    'daw-start-angular' = 'start-angular'
    'daw-start-doc' = 'start-doc'
    'daw-stop' = 'stop'
    'daw-stop-all' = 'stop-all'
    'daw-stop-doc' = 'stop-doc'
    'daw-status' = 'status'
    'daw-logs' = 'logs'
    'daw-web-shell' = 'shell'
    'daw-shell' = 'shell'
    'daw-wsl-shell' = 'wsl-shell'
    'daw-code' = 'code'
    'daw-web-root' = 'web-root'
    'daw-www' = 'www'
    'daw-help' = 'help'
}
$locationArgs = " -Distribution ""$Distribution"""
if ($LinuxProjectPath) { $locationArgs += " -ProjectPath ""$LinuxProjectPath""" }
if ($LinuxUser) { $locationArgs += " -LinuxUser $LinuxUser" }
$scriptReference = $scriptPath
if ($LinuxProjectPath) { $scriptReference = "%LOCALAPPDATA%\$launcherName\daw.ps1" }
# cmd.exe debe poder representar a ruta co nome de usuario de Windows.
$cmdEncoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)

if ($Repair) {
    # Os lanzadores existentes deben ser desta instalación (mesmo script e distribución).
    # Os anteriores a -Distribution non a levan e usan Debian. Se apuntan a outra copia, non se mesturan.
    foreach ($existing in @(Get-ChildItem -LiteralPath $binPath -Filter 'daw-*.cmd' -File)) {
        $line = @([IO.File]::ReadAllLines($existing.FullName, $cmdEncoding) | Where-Object { $_ -match '-File "' }) | Select-Object -First 1
        if (-not $line) { continue }
        $m = [regex]::Match($line, '-File "([^"]+)" -Action \S+(.*?) %\*')
        if (-not $m.Success) { continue }
        $sameScript = $m.Groups[1].Value -ieq $scriptReference
        $wrapperArgs = $m.Groups[2].Value
        $sameTarget = $wrapperArgs -ceq $locationArgs -or (-not $wrapperArgs -and $Distribution -eq 'Debian' -and -not $LinuxProjectPath -and -not $LinuxUser)
        if (-not ($sameScript -and $sameTarget)) { return }
    }
}
foreach ($entry in $commands.GetEnumerator()) {
    $wrapperPath = Join-Path $binPath ($entry.Key + '.cmd')
    if ($Repair -and (Test-Path -LiteralPath $wrapperPath)) { continue }
    $wrapper = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$scriptReference"" -Action $($entry.Value)$locationArgs %*`r`nexit /b %ERRORLEVEL%`r`n"
    [System.IO.File]::WriteAllText($wrapperPath, $wrapper, $cmdEncoding)
    if ($Repair) { Write-Host "DAW Dev: added $($entry.Key)" } else { Write-Output "Installed: $wrapperPath" }
}
if ($Repair) {
    if (Add-DawUserPath) { Send-DawEnvironmentChange; Write-Host "DAW Dev: added $binPath to the user PATH. Open a new terminal." }
    return
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

$null = Add-DawUserPath
Send-DawEnvironmentChange
Write-Output 'Open a new terminal and run: daw-help'
