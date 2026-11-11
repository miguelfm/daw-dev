#requires -Version 5.1
# Este script execútase co usuario normal ao iniciar sesión, nunca como SYSTEM.
$ErrorActionPreference = 'Stop'
$statusPath = Join-Path $env:LOCALAPPDATA 'DAW-Aula\estado.json'
if (Test-Path -LiteralPath $statusPath) {
    try {
        $status = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($status.Success) { exit 0 }
    } catch { }
}
& (Join-Path $PSScriptRoot 'instalar-alumno.ps1') -PackageDirectory $PSScriptRoot
