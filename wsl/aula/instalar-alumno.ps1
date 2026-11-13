#requires -Version 5.1
<#
.SYNOPSIS
Instala DAW na conta do alumno, validando identidade e orixe antes de migrar.
.DESCRIPTION
Non borra distribucións nin remata procesos. AdoptarExistente permite aceptar expresamente
un modelo recoñecido que perdeu o rexistro de orixe. SenVSCode omite o IDE expresamente.
#>
[CmdletBinding()]
param(
    [string]$PackageDirectory=$PSScriptRoot,
    [ValidatePattern('^[a-zA-Z0-9._-]+$')][string]$Distribution='Debian-DAW',
    [ValidatePattern('^[a-fA-F0-9]{32}$')][string]$RequestId=([guid]::NewGuid().ToString('N')),
    [string]$ExpectedUserSid,
    [switch]$AdoptarExistente,
    [switch]$SenVSCode
)
$ErrorActionPreference='Stop'
$env:WSL_UTF8='1'
Import-Module (Join-Path $PSScriptRoot 'daw-aula.psm1') -Force
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=New-Object Security.Principal.WindowsPrincipal($identity)
if($identity.IsSystem -or $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Executar como alumno sen elevación.'}
if($ExpectedUserSid -and $identity.User.Value -ne $ExpectedUserSid){throw 'Identidade incorrecta: non se iniciou a instalación.'}
$stateDir=Join-Path $env:LOCALAPPDATA 'DAW-Aula'
New-Item -ItemType Directory -Path $stateDir -Force|Out-Null
$lock=[IO.File]::Open((Join-Path $stateDir 'instalacion.lock'),'OpenOrCreate','ReadWrite','None')
$statusPath=Join-Path $stateDir 'estado.json'
$status=[ordered]@{Schema=2;SetupRevision=2;RequestId=$RequestId;User=$identity.Name;UserSid=$identity.User.Value;Distribution=$Distribution;Phase='Running';StartedUtc=[DateTime]::UtcNow.ToString('o');Success=$false;Error=$null;CodeExtensions=@();CodeSkipped=$SenVSCode.IsPresent;Shortcut=$null}
$transcriptStarted=$false
try{
    Write-DawState $statusPath $status
    Start-Transcript -LiteralPath (Join-Path $stateDir 'instalacion.log') -Append|Out-Null
    $transcriptStarted=$true
    $manifest=Assert-DawPackage $PackageDirectory
    $status.ModelSha256=$manifest.Sha256
    $installed=@(Invoke-DawNative 'wsl.exe' @('--list','--quiet')) -replace "`0",'' |ForEach-Object {$_.Trim()}|Where-Object {$_}
    $importedNow=$false
    $originPath=Join-Path $stateDir ($Distribution+'.sha256')
    if($Distribution -notin $installed){
        # A leftover origin record also prevents importing a different model into this profile.
        if((Test-Path -LiteralPath $originPath) -and (Get-Content $originPath -Raw).Trim() -ne $manifest.Sha256){throw 'A conta conserva a orixe doutro modelo. Revisar antes de importar.'}
        $installDir=Join-Path $env:LOCALAPPDATA "wsl\$Distribution"
        if(Test-Path -LiteralPath $installDir){
            $item=Get-Item -LiteralPath $installDir -Force
            if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or @(Get-ChildItem -LiteralPath $installDir -Force).Count){throw 'O directorio WSL xa contén datos ou é unha ligazón. Conservouse.'}
        }else{New-Item -ItemType Directory -Path $installDir|Out-Null}
        Invoke-DawNative 'wsl.exe' @('--import',$Distribution,$installDir,(Join-Path $PackageDirectory $manifest.Image),'--version','2')|Out-Null
        $importedNow=$true
    }
    Assert-DawOrigin $Distribution $manifest.Marker $manifest.Sha256 $originPath $importedNow -AdoptExisting:$AdoptarExistente
    if(-not(Test-Path -LiteralPath $originPath)){Set-Content -LiteralPath $originPath -Value $manifest.Sha256 -Encoding ASCII}
    # Explicit adoption and freshly imported models are recorded BEFORE migration, so a partial failure is retryable.
    Invoke-DawNative 'wsl.exe' @('-d',$Distribution,'-u','root','--exec','bash','-c',(Get-DawMigration))|Out-Null
    Invoke-DawNative 'wsl.exe' @('-d',$Distribution,'-u','ad','--exec','bash','-c','for i in {1..60}; do docker info >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1')|Out-Null
    Invoke-DawNative 'wsl.exe' @('-d',$Distribution,'-u','ad','--cd','/home/ad/proxectos/daw-dev','--exec','docker','compose','config','--quiet')|Out-Null
    if($importedNow){
        $settingsPath="\\wsl.localhost\$Distribution\home\ad\proxectos\daw-dev\.vscode\settings.json"
        if(Test-Path -LiteralPath $settingsPath){
            $text=[IO.File]::ReadAllText($settingsPath).Replace('"Debian"',('"'+$Distribution+'"'))
            [IO.File]::WriteAllText($settingsPath,$text,(New-Object Text.UTF8Encoding($false)))
        }
    }
    & (Join-Path $PackageDirectory 'install-daw-commands.ps1') -Distribution $Distribution -LinuxProjectPath '/home/ad/proxectos/daw-dev' -LinuxUser ad
    if(-not $SenVSCode){$status.CodeExtensions=@(Install-DawCodeExtensions)}
    $status.Shortcut=New-DawShortcut $Distribution
    $status.Success=$true
    Write-Output "Instalación $RequestId comprobada. Ruta: \\wsl.localhost\$Distribution\home\ad\www"
}catch{$status.Error=$_.Exception.Message;throw}
finally{
    try{
        $status.Phase='Completed';$status.CheckedUtc=[DateTime]::UtcNow.ToString('o')
        Write-DawState $statusPath $status
    }finally{if($transcriptStarted){Stop-Transcript|Out-Null};$lock.Dispose()}
}
