#requires -Version 5.1
<#
.SYNOPSIS
Engade ao paquete da aula o VS Code Server para Linux, co seu commit e SHA256.
.DESCRIPTION
O commit ten que ser o do VS Code dos postos: a segunda liña de code --version.
CopiarModelo leva o ficheiro a C:\ProgramData\DAW-Aula, e daw-code-angular instálao
en Debian-DAW sen descargalo. Con -Commit descárgao de Microsoft; con -Archive usa un
ficheiro xa descargado de https://update.code.visualstudio.com/commit:<commit>/server-linux-x64/stable.
.EXAMPLE
.\engadir-vscode-server.ps1 -PackageDirectory C:\DAW-Paquete-2026 -Commit a717861c07586a53d83b80d742cd3f59b20a6273
.EXAMPLE
.\engadir-vscode-server.ps1 -PackageDirectory C:\DAW-Paquete-2026 -Archive $HOME\Downloads\vscode-server-linux-x64.tar.gz
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [string]$Archive,
    [ValidatePattern('^[0-9a-fA-F]{40}$')][string]$Commit,
    [ValidateSet('x64', 'arm64')][string]$Architecture = 'x64'
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'daw-aula.psm1') -Force
if (-not $Archive -and -not $Commit) { throw 'Indica -Archive ou -Commit.' }
$download = $null
try {
    if (-not $Archive) {
        $download = Join-Path ([IO.Path]::GetTempPath()) ('daw-vscode-server-' + [guid]::NewGuid().ToString('N') + '.tar.gz')
        $url = 'https://update.code.visualstudio.com/commit:{0}/server-linux-{1}/stable' -f $Commit.ToLowerInvariant(), $Architecture
        Write-Output "Descargando $url"
        # Sen barra de progreso: en Windows PowerShell 5.1 fai a descarga moito máis lenta.
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $download -TimeoutSec 900
        $Archive = $download
    }
    if ($PSCmdlet.ShouldProcess($PackageDirectory, 'Engadir o VS Code Server')) {
        $entry = Add-DawPackageFile $PackageDirectory $Archive $Commit
        Write-Output "VS Code Server $($entry.Commit) engadido ao paquete como $($entry.File)."
    }
} finally {
    if ($download) { Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue }
}
