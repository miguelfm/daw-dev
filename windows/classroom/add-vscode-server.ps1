#requires -Version 5.1
<#
.SYNOPSIS
Engade ao paquete da aula o VS Code Server dun commit de VS Code, co seu SHA256.
.DESCRIPTION
Os postos non descargan entón o servidor ao abrir o proxecto: CopyPackage leva o ficheiro
aos equipos, a activación instálao na distribución e daw-code prepara tamén a caché de
Dev Containers. Commit é o do VS Code dos postos (segunda liña de code --version nun
posto), que pode ser distinto do VS Code do profesor. Con Archive usa un servidor xa
descargado en lugar de descargalo.
.EXAMPLE
.\add-vscode-server.ps1 -PackageDirectory C:\DAW-Paquete-2026 -Commit 0123456789abcdef0123456789abcdef01234567
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$Commit,
    [string]$Archive
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'daw-classroom.psm1') -Force
$download = $null
try {
    if (-not $Archive) {
        $download = Join-Path ([IO.Path]::GetTempPath()) ("vscode-server-$Commit-" + [guid]::NewGuid().ToString('N') + '.tar.gz')
        $url = "https://update.code.visualstudio.com/commit:$Commit/server-linux-x64/stable"
        Write-Host "Descargando $url"
        & curl.exe --fail --location --silent --show-error --connect-timeout 20 --max-time 900 --output $download $url
        if ($LASTEXITCODE -ne 0) { throw 'Fallou a descarga de VS Code Server.' }
        $Archive = $download
    }
    if ($PSCmdlet.ShouldProcess($PackageDirectory, "Engadir VS Code Server $Commit")) {
        Add-DawPackageCodeServer $PackageDirectory $Archive $Commit
    }
} finally {
    if ($download -and (Test-Path -LiteralPath $download)) { Remove-Item -LiteralPath $download -Force }
}
