#requires -Version 5.1
# Só para aulas que optaron expresamente polo autoarranque.
# A validación actual non se omite por un estado.json antigo que diga Success=true.
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'instalar-alumno.ps1') -PackageDirectory $PSScriptRoot
