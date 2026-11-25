#requires -Version 5.1
<#
.SYNOPSIS
Activa DAW Dev na conta que o executa: importa Debian e copia os ficheiros do proxecto.
.DESCRIPTION
Lánzao cada usuario desde o menú Inicio (DAW Dev > Activar DAW Dev), sen administración.
Non deixa nada no inicio de sesión. Repetilo é seguro: conserva a distribución e os datos.
Distribution permite probar cunha distribución separada. SenPausa omite a
espera final. SenVSCode omite a instalación das extensións.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[a-zA-Z0-9._-]+$')][string]$Distribution='Debian',
    [switch]$SenPausa,
    [switch]$SenVSCode
)
$ErrorActionPreference = 'Stop'
try { $Host.UI.RawUI.WindowTitle = 'Activar DAW Dev' } catch { }
Write-Host 'Activando DAW Dev nesta conta. A primeira vez tarda uns minutos: non peches esta xanela.'
$ok = $false
try {
    & (Join-Path $PSScriptRoot 'instalar-alumno.ps1') -PackageDirectory $PSScriptRoot -Distribution $Distribution -SenVSCode:$SenVSCode
    # Os ficheiros do proxecto que CopiarModelo deixou no equipo, cos seus SHA256.
    $stage = Join-Path $PSScriptRoot 'proxecto'
    if (Test-Path -LiteralPath (Join-Path $stage 'proxecto.json') -PathType Leaf) {
        & (Join-Path $stage 'actualizar-proxecto.ps1') -PackageDirectory $stage -Distribution $Distribution
    } else {
        Write-Host 'Este equipo aínda non ten os ficheiros do proxecto: o docente pode copialos despois.'
    }
    $ok = $true
} catch {
    Write-Host ('ERRO: ' + $_.Exception.Message) -ForegroundColor Red
}
if ($ok) {
    Write-Host 'DAW Dev está activado. Abre un terminal novo e executa daw-start.' -ForegroundColor Green
} else {
    Write-Host 'Non se puido activar. Avisa ao docente: o rexistro está en %LOCALAPPDATA%\DAW-Aula.'
}
if (-not $SenPausa) { $null = Read-Host 'Preme Intro para pechar' }
if (-not $ok) { exit 1 }
exit 0
