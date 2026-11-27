#requires -Version 5.1
<#
.SYNOPSIS
Engade ao paquete da aula unha imaxe Docker gardada con docker save, co seu SHA256.
.DESCRIPTION
CopyPackage leva despois o ficheiro aos equipos, e daw.ps1 cárgao en cada conta
a primeira vez que o necesita, sen Internet.
.EXAMPLE
.\add-package-image.ps1 -PackageDirectory C:\DAW-Paquete-2026 -Archive C:\tmp\daw-angular.tar.gz -Name ghcr.io/miguelfm/daw-angular:22
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [Parameter(Mandatory)][string]$Archive,
    [Parameter(Mandatory)][string]$Name
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'daw-classroom.psm1') -Force
if ($PSCmdlet.ShouldProcess($PackageDirectory, "Engadir $Name")) {
    Add-DawPackageImage $PackageDirectory $Archive $Name
}
