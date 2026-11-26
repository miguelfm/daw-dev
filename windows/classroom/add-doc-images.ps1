#requires -Version 5.1
<#
.SYNOPSIS
Engade ao paquete da aula as imaxes da documentación sen conexión publicadas en daw-doc.
.DESCRIPTION
Descarga dunha release de GitHub de daw-doc (por defecto, a última) os arquivos das imaxes
da documentación e SHA256SUMS, sen login. Comproba o SHA256 de cada arquivo e que garda a
imaxe esperada, e rexístraa no paquete co mesmo procedemento ca add-package-image.ps1.
CopyPackage leva despois os arquivos aos equipos, e daw-start-doc cárgaos en cada conta.
.EXAMPLE
.\add-doc-images.ps1 -PackageDirectory C:\DAW-Paquete-2026
.EXAMPLE
.\add-doc-images.ps1 -PackageDirectory C:\DAW-Paquete-2026 -Tag docs-2026-11-26
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Tag = 'latest',
    [ValidatePattern('^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$')][string]$Repository = 'miguelfm/daw-doc'
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'daw-classroom.psm1') -Force
Assert-DawPackage $PackageDirectory | Out-Null
# As imaxes da documentación que carga daw.ps1: cada arquivo leva o nome do repositorio da imaxe.
$images = [ordered]@{}
foreach ($name in Get-DawPackageImageNames | Where-Object { $_ -match '/daw-doc-[a-z]+:' }) {
    $images[(($name -split '/')[-1] -split ':')[0] + '.tar.gz'] = $name
}
$api = if ($Tag -eq 'latest') { "https://api.github.com/repos/$Repository/releases/latest" } else { "https://api.github.com/repos/$Repository/releases/tags/$Tag" }
$release = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'daw-dev classroom'; Accept = 'application/vnd.github+json' }
Write-Host "Release $($release.tag_name) de $Repository"
$assets = @{}
foreach ($asset in @($release.assets)) { $assets[$asset.name] = $asset.browser_download_url }
foreach ($file in @('SHA256SUMS') + @($images.Keys)) {
    if (-not $assets.ContainsKey($file)) { throw "A release $($release.tag_name) non ten $file." }
}
$download = Join-Path ([IO.Path]::GetTempPath()) ('daw-doc-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $download | Out-Null
try {
    function Get-DawAsset([string]$Name) {
        $path = Join-Path $download $Name
        & curl.exe --fail --location --silent --show-error --connect-timeout 20 --max-time 1800 --output $path $assets[$Name]
        if ($LASTEXITCODE -ne 0) { throw "Fallou a descarga de $Name." }
        $path
    }
    $sums = @{}
    foreach ($line in Get-Content -LiteralPath (Get-DawAsset 'SHA256SUMS')) {
        if ($line -match '^([0-9a-fA-F]{64})\s+\*?(\S+)$') { $sums[$Matches[2]] = $Matches[1].ToUpperInvariant() }
    }
    $entries = @()
    foreach ($file in $images.Keys) {
        if (-not $sums.ContainsKey($file)) { throw "SHA256SUMS non ten $file." }
        Write-Host "Descargando $file..."
        $path = Get-DawAsset $file
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $sums[$file]) { throw "O SHA256 de $file non coincide con SHA256SUMS." }
        # O arquivo debe gardar a imaxe que carga daw.ps1 (docker save escribe manifest.json).
        $tags = (& tar.exe -xzOf $path manifest.json | Out-String | ConvertFrom-Json) | ForEach-Object { $_.RepoTags }
        if ($LASTEXITCODE -ne 0 -or $images[$file] -notin @($tags)) { throw "$file non contén $($images[$file])." }
        if ($PSCmdlet.ShouldProcess($PackageDirectory, "Engadir $($images[$file])")) {
            $entries += Add-DawPackageImage $PackageDirectory $path $images[$file]
        }
    }
    $entries
} finally {
    Remove-Item -LiteralPath $download -Recurse -Force -ErrorAction SilentlyContinue
}
