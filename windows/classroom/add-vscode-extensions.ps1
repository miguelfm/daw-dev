#requires -Version 5.1
<#
.SYNOPSIS
Engade ao paquete da aula as extensións de VS Code (.vsix), co seu SHA256.
.DESCRIPTION
Descarga do Marketplace de Visual Studio as extensións de Get-DawPackageCodeExtensionIds:
- as de PHP do Dev Container (.devcontainer/devcontainer.json), que a activación instala sen
  Internet no VS Code Server da distribución e no volume do Dev Container;
- Dev Containers e WSL, que a activación instala sen Internet no VS Code de Windows.
Con CodeVersion, a última versión estable que acepta ese VS Code (o máis vello dos postos, que
non se actualiza); sen el, a última estable. Se o paquete xa ten esa versión, non a descarga:
deploy.ps1 chámao en cada despregamento para levar sempre a máis nova que aceptan os postos.
Se falla unha extensión, segue coas demais e remata cun erro que as nomea.
.EXAMPLE
.\add-vscode-extensions.ps1 -PackageDirectory C:\DAW-Paquete-2026 -CodeVersion 1.122.0
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [string[]]$Id,
    [ValidatePattern('^(\d+\.\d+\.\d+)?$')][string]$CodeVersion
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'daw-classroom.psm1') -Force
if (-not $Id) { $Id = Get-DawPackageCodeExtensionIds }

function Get-DawCompatibleVersion([string]$Extension, [string]$Platform) {
    # A versión estable máis nova que acepta CodeVersion, segundo o Marketplace.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    # 0x11: as versións e as súas propiedades (motor de VS Code e se é preliminar).
    $body = @{ filters = @(@{ criteria = @(@{ filterType = 7; value = $Extension }); pageNumber = 1; pageSize = 1 }); flags = 0x11 } | ConvertTo-Json -Depth 6
    $result = Invoke-RestMethod -Method Post -Uri 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery' -ContentType 'application/json' -Headers @{ Accept = 'application/json;api-version=3.0-preview.1' } -Body $body -TimeoutSec 60
    $candidates = foreach ($v in @($result.results[0].extensions[0].versions)) {
        $properties = @{}
        foreach ($p in @($v.properties)) { $properties[[string]$p.key] = [string]$p.value }
        if ($properties['Microsoft.VisualStudio.Code.PreRelease'] -eq 'true') { continue }
        if ($v.targetPlatform -and $v.targetPlatform -ne $Platform) { continue }
        if ([string]$v.version -notmatch '^\d+\.\d+\.\d+$') { continue }
        if ($CodeVersion -and -not (Test-DawCodeEngine $properties['Microsoft.VisualStudio.Code.Engine'] $CodeVersion)) { continue }
        [pscustomobject]@{ Version = [string]$v.version; Platform = [string]$v.targetPlatform }
    }
    $best = @($candidates | Sort-Object { [version]$_.Version } -Descending) | Select-Object -First 1
    if (-not $best) { throw "Ningunha versión estable de $Extension vale para VS Code $(if ($CodeVersion) { $CodeVersion } else { 'actual' })." }
    $best
}

# As versións que xa leva o paquete.
$current = @{}
foreach ($entry in @(Get-DawPackageCodeExtensions (Assert-DawPackage $PackageDirectory))) {
    try { $current[[string]$entry.Id] = (Get-DawVsixInfo (Join-Path $PackageDirectory $entry.File)).Version } catch { }
}
$download = Join-Path ([IO.Path]::GetTempPath()) ('daw-vsix-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $download | Out-Null
$failed = @()
try {
    foreach ($extension in $Id) {
        try {
            if ($extension -cnotmatch '^([a-z0-9-]+)\.([a-z0-9-]+)$') { throw "Extensión de VS Code non válida: $extension" }
            $base = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/$($Matches[1])/vsextensions/$($Matches[2])"
            # As de Windows execútanse no VS Code dos postos; as de PHP, no VS Code Server de Linux.
            $platform = if ($extension -in @(Get-DawWindowsCodeExtensionIds)) { 'win32-x64' } else { 'linux-x64' }
            $compatible = Get-DawCompatibleVersion $extension $platform
            $url = "$base/$($compatible.Version)/vspackage"
            if ($compatible.Platform) { $url += "?targetPlatform=$($compatible.Platform)" }
            $label = "$extension $($compatible.Version)"
            if ($CodeVersion) { $label += " (VS Code $CodeVersion)" }
            if ($current[$extension] -eq $compatible.Version) {
                Write-Host "$label xa está no paquete."
                continue
            }
            $path = Join-Path $download (Get-DawCodeExtensionFile $extension)
            Write-Host "Descargando $label..."
            & curl.exe --fail --location --compressed --silent --show-error --connect-timeout 20 --max-time 600 --output $path $url
            if ($LASTEXITCODE -ne 0) { throw "Fallou a descarga de $extension." }
            # Un .vsix é un zip: PK ao comezo.
            $head = New-Object byte[] 2
            $stream = [IO.File]::OpenRead($path); try { $null = $stream.Read($head, 0, 2) } finally { $stream.Dispose() }
            if ($head[0] -ne 0x50 -or $head[1] -ne 0x4B) { throw "A descarga de $extension non é un .vsix." }
            $info = Get-DawVsixInfo $path
            if ($info.Id -ne $extension) { throw "A descarga de $extension contén $($info.Id)." }
            if ($CodeVersion -and -not (Test-DawCodeEngine $info.Engine $CodeVersion)) { throw "$extension $($info.Version) precisa VS Code $($info.Engine), non $CodeVersion." }
            if ($PSCmdlet.ShouldProcess($PackageDirectory, "Engadir $extension")) {
                Add-DawPackageCodeExtension $PackageDirectory $path $extension | Out-Null
            }
        } catch {
            $failed += "${extension}: $($_.Exception.Message)"
        }
    }
} finally {
    Remove-Item -LiteralPath $download -Recurse -Force -ErrorAction SilentlyContinue
}
if ($failed.Count) { throw "Non se engadiron: $($failed -join ' | ')" }
