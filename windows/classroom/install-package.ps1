#requires -Version 5.1
<#
.SYNOPSIS
Instala o paquete DAW Dev neste mesmo equipo, por exemplo no do profesor.
.DESCRIPTION
Fai o mesmo ca manage.ps1 -Action CopyPackage nun posto, pero en local e sen WinRM: retira o
paquete anterior (DAW-Aula), copia o novo en Get-DawPackageDirectory co seu
SHA256 comprobado e a escritura só para SYSTEM e Administradores, deixa os ficheiros do
proxecto e a entrada DAW Dev > Activar DAW Dev no menú Inicio. Executar en PowerShell como
administrador. Non activa ningunha conta: despois, cada usuario activa DAW Dev sen elevación.
AutoStart activa a instalación no inicio de sesión, como en CopyPackage.
.EXAMPLE
.\install-package.ps1 -PackageDirectory C:\DAW-Paquete-2026
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [switch]$AutoStart
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'daw-classroom.psm1') -Force
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Executar en PowerShell como administrador.'
}
$manifest = Assert-DawPackage $PackageDirectory
$files = Get-DawPackageFiles $manifest
$stage = Join-Path ([IO.Path]::GetTempPath()) ('daw-project-' + [guid]::NewGuid().ToString('N'))
try {
    Write-Host 'Preparando os ficheiros do proxecto...'
    $projectManifest = New-DawProjectStage $PSScriptRoot $stage
    Write-Host "Instalando o paquete en $(Get-DawPackageDirectory)..."
    $removed = @(Initialize-DawPackageDirectory)
    $copied = @(Copy-DawPackageFiles $PackageDirectory (Get-DawPackageDirectory) $files)
    Complete-DawPackage -AutoStart:$AutoStart
    Copy-Item -Path (Join-Path $stage '*') -Destination ((Get-DawProjectDirectory) + '\') -Recurse -Force
    $result = Complete-DawProjectStage $projectManifest.Revision
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
if ($removed.Count) { Write-Host "Retirado: $($removed -join ', ')" }
Write-Host "Copiados $($copied.Count) de $($files.Count) ficheiros; os demais xa estaban."
Write-Host "Ficheiros do proxecto: revisión $($result.Revision)."
Write-Host "Menú Inicio: $($result.Shortcut)" -ForegroundColor Green
Write-Host 'Agora, nunha sesión sen elevar: DAW Dev > Activar DAW Dev no menú Inicio (ou daw-activate).'
Write-Host "Para comprobala despois: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$(Get-DawPackageDirectory)\verify-user.ps1`""
[pscustomobject]@{ Removed = $removed; Copied = $copied; Revision = $result.Revision; Shortcut = $result.Shortcut }
