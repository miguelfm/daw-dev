#requires -Version 5.1
<#
.SYNOPSIS
Instala DAW Dev na conta que o executa, sen elevación.
.DESCRIPTION
Retira primeiro a instalación anterior desta conta (distribución Debian do modelo DAW-Aula,
o seu estado e os seus lanzadores). Antes de eliminar unha distribución copia a súa raíz web
(WWW_DIR) en Documentos\DAW-Dev-www-<data>-<distribución>, e despois copia ese contido no www
do proxecto novo. O resto do contido da distribución pérdese: o alumnado garda antes o que precise.
Unha distribución co mesmo paquete consérvase. Se procede doutro paquete, só se substitúe
con -Reinstall, que a elimina con todo o seu contido. Nunca se elimina unha distribución
sen o marcador do modelo. SkipVSCode omite as extensións e o VS Code Server do paquete.
#>
[CmdletBinding()]
param(
    [string]$PackageDirectory,
    [ValidatePattern('^([a-zA-Z0-9._-]+)?$')][string]$Distribution,
    [ValidatePattern('^[a-fA-F0-9]{32}$')][string]$RequestId=([guid]::NewGuid().ToString('N')),
    [string]$ExpectedUserSid,
    [switch]$Reinstall,
    [switch]$SkipVSCode
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
if($ExpectedUserSid -and $identity.User.Value -ne $ExpectedUserSid){throw 'Identidade incorrecta: non se iniciou a instalación.'}
$stateDir=Get-DawStateDirectory
$stateFiles=Get-DawStateFiles
$project=Get-DawLinuxProjectPath
New-Item -ItemType Directory -Path $stateDir -Force|Out-Null
$lock=[IO.File]::Open((Join-Path $stateDir $stateFiles.Lock),'OpenOrCreate','ReadWrite','None')
$statusPath=Join-Path $stateDir $stateFiles.Install
$status=[ordered]@{Schema=2;RequestId=$RequestId;User=$identity.Name;UserSid=$identity.User.Value;Distribution=$Distribution;Phase='Running';StartedUtc=[DateTime]::UtcNow.ToString('o');Success=$false;Error=$null;Removed=@();WebBackups=@();WebRestored=@();Imported=$false;CodeExtensions=@();CodeExtensionsError=$null;CodeServer=$null;PhpExtensions=@();CodeSkipped=$SkipVSCode.IsPresent;Shortcut=$null;ProjectMoved=$false}
$transcriptStarted=$false
try{
    Write-DawState $statusPath $status
    Start-Transcript -LiteralPath (Join-Path $stateDir $stateFiles.InstallLog) -Append|Out-Null
    $transcriptStarted=$true
    $manifest=Assert-DawPackage $PackageDirectory
    $status.ModelSha256=$manifest.Sha256
    # Unha copia que quedou sen restaurar nunha execución anterior restáurase ao final desta.
    $pendingRestore=Join-Path $stateDir $stateFiles.PendingRestore
    $legacy=Remove-DawLegacyInstall -PendingRestore $pendingRestore
    $status.Removed=@($legacy.Removed)
    if($legacy.Backup){$status.WebBackups+=$legacy.Backup}
    $originPath=Join-Path $stateDir ($Distribution+'.sha256')
    $import=$true
    if($Distribution -in @(Get-DawDistributions)){
        if(-not(Test-DawModelMarker $Distribution)){throw "A distribución $Distribution non é de DAW Dev; conservouse. Indicar outro nome con -Distribution."}
        $origin=if(Test-Path -LiteralPath $originPath){(Get-Content -LiteralPath $originPath -Raw -Encoding UTF8).Trim()}else{''}
        if($origin -eq $manifest.Sha256 -and -not $Reinstall){$import=$false}
        elseif(-not $Reinstall){throw "$Distribution procede doutro paquete. Gardar o traballo e repetir con -Reinstall, que a elimina."}
        else{
            # Tamén na ruta anterior do proxecto: unha conta pode non ter repetido a activación.
            $backup=Backup-DawWebRoot $Distribution @($project,(Get-DawPreviousLinuxProjectPath)) $pendingRestore
            if($backup){$status.WebBackups+=$backup}
            Remove-DawDistribution $Distribution
            $status.Removed+="wsl:$Distribution"
        }
    }
    if($import){
        if(Test-Path -LiteralPath $originPath){Remove-Item -LiteralPath $originPath -Force}
        # Os restos dunha importación que non chegou a rexistrarse.
        Remove-DawInstallDirectory $Distribution
        $installDir=Join-Path $env:LOCALAPPDATA "wsl\$Distribution"
        New-Item -ItemType Directory -Path $installDir|Out-Null
        Invoke-DawNative 'wsl.exe' @('--import',$Distribution,$installDir,(Join-Path $PackageDirectory $manifest.Image),'--version','2')|Out-Null
        if(-not(Test-DawModelMarker $Distribution)){throw 'A imaxe importada non ten o marcador do modelo.'}
        Set-Content -LiteralPath $originPath -Value $manifest.Sha256 -Encoding ASCII
        $status.Imported=$true
        # Un modelo anterior ao 27-11-2026 trae o proxecto en ~/workspace.
        $status.ProjectMoved=Move-DawProjectDirectory $Distribution
        $settingsPath=ConvertTo-DawWslPath $Distribution "$project/.vscode/settings.json"
        if(Test-Path -LiteralPath $settingsPath){
            $text=[IO.File]::ReadAllText($settingsPath).Replace('"Debian"',('"'+$Distribution+'"'))
            [IO.File]::WriteAllText($settingsPath,$text,(New-Object Text.UTF8Encoding($false)))
        }
    }
    # A distribución que xa tiña a conta, co proxecto aínda en ~/workspace.
    if(-not $import){$status.ProjectMoved=Move-DawProjectDirectory $Distribution}
    if($status.ProjectMoved){Write-Output "O proxecto está agora en $project (antes $(Get-DawPreviousLinuxProjectPath))."}
    Invoke-DawNative 'wsl.exe' @('-d',$Distribution,'-u','ad','--exec','bash','-c','for i in {1..60}; do docker info >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1')|Out-Null
    Invoke-DawNative 'wsl.exe' @('-d',$Distribution,'-u','ad','--cd',$project,'--exec','docker','compose','config','--quiet')|Out-Null
    $status.WebRestored=@(Restore-DawPendingWebRoot $Distribution $pendingRestore)
    foreach($backup in $status.WebRestored){Write-Output "Copiouse en www o contido da raíz web anterior. A copia consérvase en $backup."}
    & (Join-Path $PackageDirectory 'install-daw-commands.ps1') -Distribution $Distribution -LinuxProjectPath $project -LinuxUser ad
    if(-not $SkipVSCode){
        # Dev Containers e WSL, do paquete ou do Marketplace. Sen elas non se abre o proxecto en VS Code,
        # pero o resto da contorna funciona: avísase, séguese e verify-user.ps1 compróbaas.
        try{$status.CodeExtensions=@(Install-DawCodeExtensions $PackageDirectory)}
        catch{
            $status.CodeExtensionsError=$_.Exception.Message
            Write-Warning "Non se instalaron as extensións de VS Code: $($_.Exception.Message) Repetir daw-activate cando haxa conexión."
        }
        # VS Code Server do paquete, para non descargalo na aula. É unha axuda: sen el, VS Code descárgao.
        try{
            $server=Initialize-DawCodeServer -Distribution $Distribution -Code (Find-DawCode) -PackageDirectory $PackageDirectory -ForContainer
            $status.CodeServer="$($server.Status) $($server.Commit)"
            if($server.Status -eq 'Missing'){Write-Warning "O paquete non ten VS Code Server para o commit $($server.Commit): VS Code descargarao."}
            # As extensións de PHP do paquete, en WSL e no volume do Dev Container, sen Internet.
            else{$status.PhpExtensions=@(Install-DawPackageCodeExtensions $Distribution $server.Commit $PackageDirectory)}
        }catch{
            $status.CodeServer="Error: $($_.Exception.Message)"
            Write-Warning "Non se preparou VS Code Server: $($_.Exception.Message)"
        }
    }
    $status.Shortcut=New-DawShortcut $Distribution
    $status.Success=$true
    Write-Output "Instalación $RequestId comprobada. Código web: $(ConvertTo-DawWslPath $Distribution "$project/www")"
}catch{$status.Error=$_.Exception.Message;throw}
finally{
    try{
        $status.Phase='Completed';$status.CheckedUtc=[DateTime]::UtcNow.ToString('o')
        Write-DawState $statusPath $status
    }finally{if($transcriptStarted){Stop-Transcript|Out-Null};$lock.Dispose()}
}
