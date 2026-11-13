#requires -Version 5.1
<# .SYNOPSIS
Actualiza só os scripts dun paquete local do docente; conserva a imaxe e o seu SHA256.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$PackageDirectory)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'daw-aula.psm1') -Force
if($PSCmdlet.ShouldProcess($PackageDirectory,'Actualizar scripts, manifesto e copia previa sen reconstruír a imaxe')){
    Update-DawPackage $PackageDirectory $PSScriptRoot
    Write-Output 'Scripts actualizados; imaxe e orixe dos alumnos conservadas.'
}
