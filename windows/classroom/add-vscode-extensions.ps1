#requires -Version 5.1
<#
.SYNOPSIS
Engade ao paquete da aula as extensións de VS Code para PHP (.vsix), co seu SHA256.
.DESCRIPTION
Descarga do Marketplace de Visual Studio a última versión de cada extensión de
Get-DawCodeExtensionIds (as de .devcontainer/devcontainer.json). A activación instálaas sen
Internet no VS Code Server da distribución e no volume do Dev Container.
.EXAMPLE
.\add-vscode-extensions.ps1 -PackageDirectory C:\DAW-Paquete-2026
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [string[]]$Id
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'daw-classroom.psm1') -Force
if (-not $Id) { $Id = Get-DawCodeExtensionIds }
$download = Join-Path ([IO.Path]::GetTempPath()) ('daw-vsix-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $download | Out-Null
try {
    foreach ($extension in $Id) {
        if ($extension -cnotmatch '^([a-z0-9-]+)\.([a-z0-9-]+)$') { throw "Extensión de VS Code non válida: $extension" }
        $url = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/$($Matches[1])/vsextensions/$($Matches[2])/latest/vspackage"
        $path = Join-Path $download (Get-DawCodeExtensionFile $extension)
        Write-Host "Descargando $extension..."
        & curl.exe --fail --location --compressed --silent --show-error --connect-timeout 20 --max-time 600 --output $path $url
        if ($LASTEXITCODE -ne 0) { throw "Fallou a descarga de $extension." }
        # Un .vsix é un zip: PK ao comezo.
        $head = New-Object byte[] 2
        $stream = [IO.File]::OpenRead($path); try { $null = $stream.Read($head, 0, 2) } finally { $stream.Dispose() }
        if ($head[0] -ne 0x50 -or $head[1] -ne 0x4B) { throw "A descarga de $extension non é un .vsix." }
        if ($PSCmdlet.ShouldProcess($PackageDirectory, "Engadir $extension")) {
            Add-DawPackageCodeExtension $PackageDirectory $path $extension
        }
    }
} finally {
    Remove-Item -LiteralPath $download -Recurse -Force -ErrorAction SilentlyContinue
}
