#requires -Version 5.1
# Só para aulas que optaron expresamente polo autoarranque (CopiarModelo -AutoInicio).
# Valida o paquete en cada inicio de sesión; un install-state.json antigo non o evita.
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'install-user.ps1') -PackageDirectory $PSScriptRoot
