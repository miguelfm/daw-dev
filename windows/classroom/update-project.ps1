#requires -Version 5.1
<#
.SYNOPSIS
Copia na distribución DAW Dev da conta os ficheiros do proxecto preparados polo profesor.
.DESCRIPTION
Comproba os SHA256 do paquete e o marcador do modelo antes de cambiar nada. Non toca www,
non borra ficheiros, non substitúe os de data e garda unha copia dos que substitúe.
Sen Restart, os cambios aplícanse no seguinte daw-start. Con Restart recrea o
contedor web se está en marcha, o que pecha unha sesión aberta de Dev Containers.
#>
[CmdletBinding()]
param(
    [string]$PackageDirectory,
    [ValidatePattern('^([a-zA-Z0-9._-]+)?$')][string]$Distribution,
    [ValidatePattern('^[a-fA-F0-9]{32}$')][string]$RequestId=([guid]::NewGuid().ToString('N')),
    [string]$ExpectedUserSid,
    [switch]$Restart
)
$ErrorActionPreference='Stop'
# Con [CmdletBinding()] e -File, Windows PowerShell 5.1 deixa baleiro $PSScriptRoot nos valores por defecto.
if(-not $PackageDirectory){$PackageDirectory=$PSScriptRoot}
$env:WSL_UTF8='1'
Import-Module (Join-Path $PSScriptRoot 'daw-classroom.psm1') -Force
if(-not $Distribution){$Distribution=Get-DawDistribution}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=New-Object Security.Principal.WindowsPrincipal($identity)
if($identity.IsSystem -or $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Executar como alumno sen elevación.'}
if($ExpectedUserSid -and $identity.User.Value -ne $ExpectedUserSid){throw 'Identidade incorrecta: non se iniciou a actualización.'}
$stateDir=Get-DawStateDirectory
$stateFiles=Get-DawStateFiles
New-Item -ItemType Directory -Path $stateDir -Force|Out-Null
# O mesmo bloqueo que a instalación: nunca se executan as dúas á vez na mesma conta.
$lock=[IO.File]::Open((Join-Path $stateDir $stateFiles.Lock),'OpenOrCreate','ReadWrite','None')
$statusPath=Join-Path $stateDir $stateFiles.Project
$status=[ordered]@{Schema=2;RequestId=$RequestId;User=$identity.Name;UserSid=$identity.User.Value;Distribution=$Distribution;Phase='Running';StartedUtc=[DateTime]::UtcNow.ToString('o');Success=$false;Error=$null;Revision=$null;Created=@();Replaced=@();Unchanged=@();Kept=@();Backup=$null;Restarted=$false}
$transcriptStarted=$false
try{
    Write-DawState $statusPath $status
    Start-Transcript -LiteralPath (Join-Path $stateDir $stateFiles.ProjectLog) -Append|Out-Null
    $transcriptStarted=$true
    $manifest=Assert-DawProjectOverlay $PackageDirectory
    $status.Revision=$manifest.Revision
    if($Distribution -notin @(Get-DawDistributions)){throw "Esta conta aínda non ten $Distribution`: activar antes DAW Dev."}
    # Só o modelo que instalou install-user.ps1.
    if(-not(Test-DawModelMarker $Distribution)){throw "A distribución $Distribution non é de DAW Dev; conservouse sen modificar."}
    $result=Invoke-DawProjectOverlay $Distribution $PackageDirectory $manifest
    foreach($name in @('Created','Replaced','Unchanged','Kept','Backup')){$status[$name]=$result.$name}
    if($Restart){$status.Restarted=Restart-DawProjectWeb $Distribution}
    $status.Success=$true
    Write-Output "Proxecto $RequestId actualizado á revisión $($manifest.Revision)."
}catch{$status.Error=$_.Exception.Message;throw}
finally{
    try{
        $status.Phase='Completed';$status.CheckedUtc=[DateTime]::UtcNow.ToString('o')
        Write-DawState $statusPath $status
    }finally{if($transcriptStarted){Stop-Transcript|Out-Null};$lock.Dispose()}
}
