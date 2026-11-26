# Transición: os lanzadores daw-*.cmd instalados antes de mover wsl/ a windows/ apuntan
# aquí. Reinstálaos coa ruta nova e executa a orde pedida. Retirar cando xa non se usen.
param(
    [string]$Action = 'help',
    [string]$Distribution = 'Debian',
    [string]$ProjectPath,
    [string]$LinuxUser,
    [switch]$Open,
    [switch]$Local,
    [switch]$Container,
    [string]$PackageDirectory,
    [switch]$SkipVSCode
)
$ErrorActionPreference = 'Stop'
$windows = Join-Path (Split-Path -Parent $PSScriptRoot) 'windows'
Write-Host 'DAW Dev: os comandos daw-* pasan a windows\daw.ps1; actualizando os lanzadores...'
& (Join-Path $windows 'install-daw-commands.ps1') -Distribution $Distribution | Out-Null
& (Join-Path $windows 'daw.ps1') @PSBoundParameters
exit $LASTEXITCODE
