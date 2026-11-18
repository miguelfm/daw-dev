#requires -Version 5.1
<#
.SYNOPSIS
Copia na Debian-DAW do alumno os ficheiros do proxecto preparados polo profesor.
.DESCRIPTION
Comproba os SHA256 do paquete e a orixe do modelo antes de cambiar nada. Non toca www,
non borra ficheiros, non substitúe os de datos e garda unha copia dos que substitúe.
Sen Reiniciar, os cambios aplícanse no seguinte daw-start. Con Reiniciar recrea o
contedor web se está en marcha, o que pecha unha sesión aberta de Dev Containers.
#>
[CmdletBinding()]
param(
    [string]$PackageDirectory=$PSScriptRoot,
    [ValidatePattern('^[a-zA-Z0-9._-]+$')][string]$Distribution='Debian-DAW',
    [ValidatePattern('^[a-fA-F0-9]{32}$')][string]$RequestId=([guid]::NewGuid().ToString('N')),
    [string]$ExpectedUserSid,
    [switch]$Reiniciar
)
$ErrorActionPreference='Stop'
$env:WSL_UTF8='1'
Import-Module (Join-Path $PSScriptRoot 'daw-aula.psm1') -Force
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=New-Object Security.Principal.WindowsPrincipal($identity)
if($identity.IsSystem -or $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Executar como alumno sen elevación.'}
if($ExpectedUserSid -and $identity.User.Value -ne $ExpectedUserSid){throw 'Identidade incorrecta: non se iniciou a actualización.'}
$stateDir=Join-Path $env:LOCALAPPDATA 'DAW-Aula'
New-Item -ItemType Directory -Path $stateDir -Force|Out-Null
# O mesmo bloqueo que a instalación: nunca se executan as dúas á vez na mesma conta.
$lock=[IO.File]::Open((Join-Path $stateDir 'instalacion.lock'),'OpenOrCreate','ReadWrite','None')
$statusPath=Join-Path $stateDir 'proxecto-estado.json'
$status=[ordered]@{Schema=2;RequestId=$RequestId;User=$identity.Name;UserSid=$identity.User.Value;Distribution=$Distribution;Phase='Running';StartedUtc=[DateTime]::UtcNow.ToString('o');Success=$false;Error=$null;Revision=$null;Created=@();Replaced=@();Unchanged=@();Kept=@();Backup=$null;Restarted=$false}
$transcriptStarted=$false
try{
    Write-DawState $statusPath $status
    Start-Transcript -LiteralPath (Join-Path $stateDir 'proxecto.log') -Append|Out-Null
    $transcriptStarted=$true
    $manifest=Assert-DawProjectOverlay $PackageDirectory
    $status.Revision=$manifest.Revision
    $installed=@(Invoke-DawNative 'wsl.exe' @('--list','--quiet')) -replace "`0",''|ForEach-Object {$_.Trim()}|Where-Object {$_}
    if($Distribution -notin $installed){throw 'Esta conta aínda non ten Debian-DAW: executar antes InstalarUsuario.'}
    $originPath=Join-Path $stateDir ($Distribution+'.sha256')
    $origin=''
    if(Test-Path -LiteralPath $originPath){
        $origin=(Get-Content -LiteralPath $originPath -Raw -Encoding UTF8).Trim()
        if($origin -notmatch '^[a-fA-F0-9]{64}$'){throw 'O rexistro de orixe da distribución non é válido; conservouse sen modificar.'}
    }
    # Só o modelo DAW instalado por instalar-alumno.ps1, co seu rexistro de orixe.
    Assert-DawOrigin $Distribution $manifest.Marker $origin $originPath $false
    $result=Invoke-DawProjectOverlay $Distribution $PackageDirectory $manifest
    foreach($name in @('Created','Replaced','Unchanged','Kept','Backup')){$status[$name]=$result.$name}
    if($Reiniciar){$status.Restarted=Restart-DawProjectWeb $Distribution}
    $status.Success=$true
    Write-Output "Proxecto $RequestId actualizado á revisión $($manifest.Revision)."
}catch{$status.Error=$_.Exception.Message;throw}
finally{
    try{
        $status.Phase='Completed';$status.CheckedUtc=[DateTime]::UtcNow.ToString('o')
        Write-DawState $statusPath $status
    }finally{if($transcriptStarted){Stop-Transcript|Out-Null};$lock.Dispose()}
}
