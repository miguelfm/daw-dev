#requires -Version 5.1
<#
.SYNOPSIS
Activa DAW Dev na conta que o executa: instala a distribución e copia os ficheiros do proxecto.
.DESCRIPTION
Lánzao cada usuario desde o menú Inicio (DAW Dev > Activar DAW Dev), sen administración.
Non deixa nada no inicio de sesión. A primeira vez retira a instalación anterior da conta.
Repetilo é seguro: conserva a distribución e o traballo mentres o paquete sexa o mesmo.
Reinstall substitúe unha distribución doutro paquete e elimina todo o seu contido.
Distribution permite probar cunha distribución separada. NoPause omite a
espera final. SkipVSCode omite a instalación das extensións.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^([a-zA-Z0-9._-]+)?$')][string]$Distribution,
    [switch]$Reinstall,
    [switch]$NoPause,
    [switch]$SkipVSCode
)
$ErrorActionPreference = 'Stop'
try { $Host.UI.RawUI.WindowTitle = 'Activar DAW Dev' } catch { }
Write-Host 'Activando DAW Dev nesta conta. A primeira vez tarda uns minutos: non peches esta xanela.'
$target = @{}
if ($Distribution) { $target.Distribution = $Distribution }
$ok = $false
try {
    & (Join-Path $PSScriptRoot 'install-user.ps1') -PackageDirectory $PSScriptRoot -Reinstall:$Reinstall -SkipVSCode:$SkipVSCode @target
    # Os ficheiros do proxecto que CopyPackage deixou no equipo, cos seus SHA256.
    $stage = Join-Path $PSScriptRoot 'project'
    if (Test-Path -LiteralPath (Join-Path $stage 'project.json') -PathType Leaf) {
        & (Join-Path $stage 'update-project.ps1') -PackageDirectory $stage @target
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
    Write-Host 'Non se puido activar. Avisa ao docente: o rexistro está en %LOCALAPPDATA%\DAW-Dev.'
}
if (-not $NoPause) { $null = Read-Host 'Preme Intro para pechar' }
if (-not $ok) { exit 1 }
exit 0
