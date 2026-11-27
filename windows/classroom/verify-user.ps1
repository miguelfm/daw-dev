#requires -Version 5.1
<#
.SYNOPSIS
Comproba que DAW Dev funciona na conta que o executa, sen elevación.
.DESCRIPTION
Usa os lanzadores da conta, como o alumnado: daw-start-db e daw-start-doc, e comproba
que responden a web, a documentación e que VS Code Server do paquete está listo. Se a
contorna non estaba en marcha, párase ao rematar. Non cambia a instalación.
#>
[CmdletBinding()]
param(
    [string]$PackageDirectory,
    [ValidatePattern('^([a-zA-Z0-9._-]+)?$')][string]$Distribution,
    [ValidatePattern('^[a-fA-F0-9]{32}$')][string]$RequestId=([guid]::NewGuid().ToString('N')),
    [string]$ExpectedUserSid,
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
if($ExpectedUserSid -and $identity.User.Value -ne $ExpectedUserSid){throw 'Identidade incorrecta: non se iniciou a verificación.'}
$stateDir=Get-DawStateDirectory
$stateFiles=Get-DawStateFiles
$project=Get-DawLinuxProjectPath
New-Item -ItemType Directory -Path $stateDir -Force|Out-Null
# O mesmo bloqueo que a instalación: non se verifica unha instalación a medias.
$lock=[IO.File]::Open((Join-Path $stateDir $stateFiles.Lock),'OpenOrCreate','ReadWrite','None')
$statusPath=Join-Path $stateDir $stateFiles.Verify
$status=[ordered]@{Schema=2;RequestId=$RequestId;User=$identity.Name;UserSid=$identity.User.Value;Distribution=$Distribution;Phase='Running';StartedUtc=[DateTime]::UtcNow.ToString('o');Success=$false;Error=$null;Checks=@()}
$powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$launcher=Join-Path (Get-DawStateDirectory) 'launcher\daw.ps1'
function Test-DawStep([string]$Name,[scriptblock]$Body){
    try{$detail=& $Body;$status.Checks+=[pscustomobject]@{Name=$Name;Ok=$true;Detail=[string]$detail}}
    catch{$status.Checks+=[pscustomobject]@{Name=$Name;Ok=$false;Detail=$_.Exception.Message}}
}
function Invoke-DawLauncher([string]$Action){
    Invoke-DawNative $powershell @('-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,'-Action',$Action,'-Distribution',$Distribution,'-ProjectPath',$project,'-LinuxUser','ad') 900|Out-Null
}
function Test-DawUrl([string]$Url){
    $response=Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 30
    if($response.StatusCode -ne 200){throw "$Url respondeu $($response.StatusCode)."}
    "$Url 200"
}
$transcriptStarted=$false
$wasRunning=$true
try{
    Write-DawState $statusPath $status
    Start-Transcript -LiteralPath (Join-Path $stateDir $stateFiles.VerifyLog) -Append|Out-Null
    $transcriptStarted=$true
    $manifest=Assert-DawPackage $PackageDirectory
    if($Distribution -notin @(Get-DawDistributions) -or -not(Test-DawModelMarker $Distribution)){
        throw "Esta conta aínda non activou DAW Dev (falta a distribución $Distribution)."
    }
    Test-DawStep 'Paquete' {
        $origin=Join-Path $stateDir ($Distribution+'.sha256')
        if(-not(Test-Path -LiteralPath $origin) -or (Get-Content -LiteralPath $origin -Raw).Trim() -ne $manifest.Sha256){throw 'A distribución procede doutro paquete: activar de novo con daw-activate -Reinstall.'}
        'actual'
    }
    Test-DawStep 'Docker' {
        Invoke-DawNative 'wsl.exe' @('-d',$Distribution,'-u','ad','--exec','bash','-c','for i in {1..60}; do docker info >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1')|Out-Null
        'responde'
    }
    Test-DawStep 'Proxecto' {
        Invoke-DawNative 'wsl.exe' @('-d',$Distribution,'-u','ad','--cd',$project,'--exec','sh','-c','test -d www && docker compose config --quiet')|Out-Null
        $project
    }
    Test-DawStep 'Lanzadores' {
        foreach($path in @($launcher,(Join-Path $env:USERPROFILE '.local\bin\daw-start.cmd'),(Join-Path $env:USERPROFILE '.local\bin\daw-activate.cmd'))){
            if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Falta $path."}
        }
        'daw-*'
    }
    $running=@(Invoke-DawNative 'wsl.exe' @('-d',$Distribution,'-u','ad','--cd',$project,'--exec','docker','compose','--profile','doc','--profile','frontend','ps','--status','running','--services')|Where-Object {$_.Trim()})
    $wasRunning=$running.Count -gt 0
    Test-DawStep 'Web e MariaDB' {
        Invoke-DawLauncher 'start-db'
        Test-DawUrl 'http://localhost/'
    }
    Test-DawStep 'Documentación' {
        Invoke-DawLauncher 'start-doc'
        (@('http://localhost:8080/','http://localhost:5042/','http://localhost:8088/')|ForEach-Object {Test-DawUrl $_}) -join ', '
    }
    if(-not $SkipVSCode){
        Test-DawStep 'Extensións de VS Code' {
            $installed=@(Get-DawInstalledCodeExtensionIds)
            $missing=@(Get-DawWindowsCodeExtensionIds|Where-Object {$_ -notin $installed})
            if($missing.Count){throw "Faltan en VS Code: $($missing -join ', '). Activar de novo con daw-activate."}
            (Get-DawWindowsCodeExtensionIds) -join ', '
        }
        Test-DawStep 'VS Code Server' {
            $commit=Get-DawCodeCommit (Find-DawCode)
            if(-not(@(Get-DawPackageCodeServers $manifest)|Where-Object {$_.Commit -eq $commit})){throw "O paquete non ten VS Code Server para o commit $commit."}
            Invoke-DawNative 'wsl.exe' @('-d',$Distribution,'-u','ad','--exec','test','-x',"/home/ad/.vscode-server/bin/$commit/node")|Out-Null
            "listo $commit"
        }
        Test-DawStep 'Extensións de PHP' {
            $wsl=@(Invoke-DawNative 'wsl.exe' @('-d',$Distribution,'-u','ad','--exec','sh','-c','ls ~/.vscode-server/extensions 2>/dev/null || true'))
            $volume=@(Invoke-DawNative 'wsl.exe' @('-d',$Distribution,'-u','ad','--exec','docker','run','--rm','--pull','never','--network','none','--entrypoint','ls','-v',"$(Get-DawCodeExtensionsVolume):/e",(Get-DawWebImage),'/e'))
            foreach($id in Get-DawCodeExtensionIds){
                foreach($place in @(@{Name='WSL';List=$wsl},@{Name='Dev Container';List=$volume})){
                    if(-not($place.List|Where-Object {$_.Trim() -like "$id-*"})){throw "Falta $id en $($place.Name)."}
                }
            }
            (Get-DawCodeExtensionIds) -join ', '
        }
    }
    $failed=@($status.Checks|Where-Object {-not $_.Ok})
    if($failed.Count){throw (($failed|ForEach-Object {"$($_.Name): $($_.Detail)"}) -join ' | ')}
    $status.Success=$true
    Write-Output "Verificación $RequestId correcta: $(($status.Checks|ForEach-Object {$_.Name}) -join ', ')."
}catch{$status.Error=$_.Exception.Message;throw}
finally{
    try{
        # Só se para o que arrancou a verificación.
        if(-not $wasRunning){try{Invoke-DawLauncher 'stop-all'}catch{$status.Checks+=[pscustomobject]@{Name='Parar';Ok=$false;Detail=$_.Exception.Message}}}
        $status.Phase='Completed';$status.CheckedUtc=[DateTime]::UtcNow.ToString('o')
        Write-DawState $statusPath $status
    }finally{if($transcriptStarted){Stop-Transcript|Out-Null};$lock.Dispose()}
}
