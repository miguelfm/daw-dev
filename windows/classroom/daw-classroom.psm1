#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Nomes e rutas do despregamento, nun só sitio. Cambiar un deles nun paquete novo obriga a
# reinstalar as contas: install-user.ps1 retira antes a instalación anterior (-Reinstall).
function Get-DawPackageDirectory { 'C:\ProgramData\DAW-Dev' }
# Estado, rexistros e bloqueo de cada conta, relativos ao seu perfil de Windows.
function Get-DawStateRelativePath { 'AppData\Local\DAW-Dev' }
function Get-DawStateDirectory {
    param([string]$UserProfile)
    if($UserProfile){return Join-Path $UserProfile (Get-DawStateRelativePath)}
    Join-Path $env:LOCALAPPDATA (Split-Path -Leaf (Get-DawStateRelativePath))
}
function Get-DawStateFiles {
    [pscustomobject]@{Lock='install.lock';Install='install-state.json';InstallLog='install.log';Project='project-state.json';ProjectLog='project.log';Verify='verify-state.json';VerifyLog='verify.log';PendingRestore='web-restore.txt'}
}
# Descargas do profesor (PsExec, MSI de WSL).
function Get-DawToolsDirectory { Join-Path (Get-DawStateDirectory) 'tools' }
# Nome xenérico: a distribución pode cambiar sen cambiar as rutas nin as guías.
function Get-DawDistribution { 'linux' }
# A contorna (compose.yaml, .env, docker/, scripts/...) vai oculta en ~/.daw, e o que é do
# alumnado, no home: o código web en ~/html, os datos das tarefas en ~/data e Angular en
# ~/angular. Así cada cousa queda a un nivel, e ~/data é a mesma ruta ca no contedor.
function Get-DawLinuxProjectPath { '/home/ad/.daw' }
function Get-DawLinuxWebPath { '/home/ad/html' }
function Get-DawLinuxDataPath { '/home/ad/data' }
function Get-DawLinuxAngularPath { '/home/ad/angular' }
# Ata o 27-11-2026 o proxecto estaba en ~/daw (antes en ~/workspace), con www, data e angular
# dentro: a activación e UpdateProject móveno á disposición actual.
function Get-DawPreviousLinuxProjectPaths { @('/home/ad/daw','/home/ad/workspace') }
function Get-DawWebImage { 'ghcr.io/miguelfm/daw-php:8.6' }
# Ata o 27-11-2026 a imaxe web chamábase así: os modelos anteriores trana na distribución.
function Get-DawPreviousWebImage { 'ghcr.io/miguelfm/dwcs-php:8.6-ad' }
function Get-DawModelArchive { 'linux.tar.gz' }
# Imaxes Docker que deben ir no paquete para usar Angular e a documentación sen Internet
# (as mesmas que carga daw.ps1).
# Extensións de VS Code para PHP (as de .devcontainer/devcontainer.json): o paquete leva os .vsix
# e a activación instálaas sen Internet en WSL e no volume do Dev Container.
function Get-DawCodeExtensionIds { @('xdebug.php-debug','bmewburn.vscode-intelephense-client') }
# As do VS Code de Windows para abrir o proxecto en WSL, Dev Containers e Angular (Remote - SSH).
function Get-DawWindowsCodeExtensionIds { @('ms-vscode-remote.remote-containers','ms-vscode-remote.remote-wsl','ms-vscode-remote.remote-ssh') }
# Todas as que leva o paquete en .vsix, para instalalas sen Internet.
function Get-DawPackageCodeExtensionIds { @(Get-DawCodeExtensionIds)+@(Get-DawWindowsCodeExtensionIds) }
function Get-DawCodeExtensionsVolume { 'daw-vscode-extensions' }
function Get-DawPackageImageNames {
    @('ghcr.io/miguelfm/daw-angular:22','ghcr.io/miguelfm/daw-doc-php:en','ghcr.io/miguelfm/daw-doc-devdocs:latest','ghcr.io/miguelfm/daw-doc-laravel:13.x')
}
# O modelo leva este ficheiro: só se reinstala ou actualiza unha distribución que o teña.
function Get-DawModelMarker { [pscustomobject]@{Path='/etc/daw-dev-model';Value='daw-dev-v2'} }
# A instalación anterior (paquete DAW-Aula, distribución Debian, proxecto en ~/proxectos/daw-dev).
# CopyPackage retira o paquete e cada conta retira o seu ao activar DAW Dev.
function Get-DawLegacyInstall {
    [pscustomobject]@{
        PackageDirectory='C:\ProgramData\DAW-Aula';StateRelativePath='AppData\Local\DAW-Aula';Lock='instalacion.lock'
        LauncherDirectory='daw-dev-launcher';Shortcut='DAW - Proxectos (www).lnk'
        ProjectPaths=@('/home/ad/proxectos/daw-dev','/home/alumno/proxectos/daw-dev')
        Distribution='Debian';MarkerPath='/etc/daw-aula-modelo';Marker='daw-aula-v1'
        RunValue='DAWAula';AutoStartCommand="& 'C:\ProgramData\DAW-Aula\iniciar-usuario.ps1'";Activator='activar-dawdev.ps1'
    }
}
function ConvertTo-DawWslPath {
    # Ruta de Linux vista desde Windows: \\wsl.localhost\<distribución>\...
    param([string]$Distribution,[string]$LinuxPath)
    "\\wsl.localhost\$Distribution"+($LinuxPath -replace '/','\')
}
function ConvertTo-DawAdminSharePath {
    # C:\ruta dun posto vista desde o profesor: \\equipo\c$\ruta.
    param([string]$Computer,[string]$Path)
    if($Path -notmatch '^([A-Za-z]):\\(.*)$'){throw "Ruta local non válida: $Path"}
    "\\$Computer\$($Matches[1].ToLowerInvariant())`$\$($Matches[2])"
}
function Expand-DawScriptTemplate {
    # Os scripts Bash levan marcadores __DAW_*__ para os valores anteriores.
    param([string]$Text)
    $Text=$Text.Replace('__DAW_WEB_IMAGE__',(Get-DawWebImage)).Replace('__DAW_PREVIOUS_WEB_IMAGE__',(Get-DawPreviousWebImage))
    if($Text -match '__DAW_[A-Z_]+__'){throw "Marcador sen valor: $($Matches[0])"}
    $Text.Replace("`r",'')
}

function ConvertTo-DawArgument {
    param([AllowEmptyString()][string]$Value)
    # wsl.exe 3.0 non recoñece as opcións entre comiñas ("--list" execútase como orde):
    # só se citan os argumentos baleiros ou con espazos ou comiñas.
    if($Value -and $Value -notmatch '[\s"]'){return $Value}
    $v=[regex]::Replace($Value,'(\\*)"','$1$1\"')
    '"'+[regex]::Replace($v,'(\\+)$','$1$1')+'"'
}
function Invoke-DawNative {
    param([string]$File,[string[]]$Arguments,[int]$TimeoutSeconds=900)
    $s=New-Object Diagnostics.ProcessStartInfo
    $s.FileName=$File;$s.Arguments=(@($Arguments|ForEach-Object {ConvertTo-DawArgument $_}) -join ' ')
    $s.UseShellExecute=$false;$s.CreateNoWindow=$true
    $s.RedirectStandardOutput=$true;$s.RedirectStandardError=$true
    $p=New-Object Diagnostics.Process;$p.StartInfo=$s
    try {
        if(-not $p.Start()){throw "Non se puido iniciar $File"}
        $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit($TimeoutSeconds*1000)){$p.Kill();$p.WaitForExit();throw "Tempo esgotado en $File"}
        $out=$stdout.GetAwaiter().GetResult();$err=$stderr.GetAwaiter().GetResult()
        if($p.ExitCode -ne 0){throw "$File (exit $($p.ExitCode)): $out`n$err"}
        return ($out -split '\r?\n')
    }finally{$p.Dispose()}
}
function Get-DawRegisteredDistributions {
    # WSL rexistra as distribucións de cada conta en HKCU; non depende da lingua de wsl.exe.
    $path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if(-not(Test-Path -LiteralPath $path)){return @()}
    @(Get-ChildItem -LiteralPath $path|ForEach-Object {$_.GetValue('DistributionName')}|Where-Object {$_})
}
function Get-DawDistributions {
    # Por se wsl --list sae con -1 nunha conta sen distribucións (non comprobado coa 3.0.5),
    # ese erro só vale como lista baleira se o rexistro da conta tampouco ten ningunha.
    try{
        @(Invoke-DawNative 'wsl.exe' @('--list','--quiet')) -replace "`0",''|ForEach-Object {$_.Trim()}|Where-Object {$_}
    }catch{
        if($_.Exception.Message -notmatch '^wsl\.exe \(exit -1\)' -or @(Get-DawRegisteredDistributions).Count){throw}
        return @()
    }
}
function Write-DawState {
    param([string]$Path,$State)
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temp,($State|ConvertTo-Json -Depth 15),(New-Object Text.UTF8Encoding($false)))
        if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temp,$Path,[NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
    }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}
function Test-DawModelMarker {
    # Só lectura, como root. Unha distribución que non arranca tampouco se recoñece.
    param([string]$Distribution,[string]$Path=(Get-DawModelMarker).Path,[string]$Value=(Get-DawModelMarker).Value)
    try{$actual=(Invoke-DawNative 'wsl.exe' @('-d',$Distribution,'-u','root','--exec','cat',$Path)) -join ''}catch{return $false}
    return $actual.Trim() -ceq $Value
}
function Remove-DawInstallDirectory {
    # O directorio en que install-user.ps1 importou a distribución.
    param([string]$Distribution)
    $dir=Join-Path $env:LOCALAPPDATA "wsl\$Distribution"
    if(-not(Test-Path -LiteralPath $dir)){return}
    if((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw "$dir é unha ligazón; conservouse."}
    Remove-Item -LiteralPath $dir -Recurse -Force
}
function Remove-DawDistribution {
    # Elimina a distribución, co seu proxecto e os seus volumes de Docker, só se ten o marcador.
    param([string]$Distribution,[string]$MarkerPath=(Get-DawModelMarker).Path,[string]$Marker=(Get-DawModelMarker).Value)
    if(-not(Test-DawModelMarker $Distribution $MarkerPath $Marker)){throw "A distribución $Distribution non é un modelo DAW recoñecido; conservouse."}
    Invoke-DawNative 'wsl.exe' @('--unregister',$Distribution)|Out-Null
    Remove-DawInstallDirectory $Distribution
}
function Get-DawWebRootBackupScript {
    # Como root na distribución que se vai eliminar. Argumentos: destino en Windows e rutas posibles
    # do proxecto. Copia o contido da raíz web configurada (WWW_DIR, por defecto ./www) ou, coa
    # contorna en ~/.daw, o de ~/html.
    $text=@'
set -euo pipefail
dest=$(wslpath -u "$1")
shift
project=
for candidate in "$@"; do
    if [[ -f $candidate/compose.yaml ]]; then project=$candidate; break; fi
done
[[ -n $project ]] || exit 0
www=./www
if [[ -f $project/.env ]]; then
    value=$(sed -n 's/^WWW_DIR=//p' "$project/.env" | tail -n 1)
    value=${value%\"}; value=${value#\"}; value=${value%\'}; value=${value#\'}
    [[ -z $value ]] || www=$value
fi
www=$(cd "$project" && realpath -m -- "$www")
# Desde o 27-11-2026 o código web vai fóra da contorna, en ~/html.
[[ -d $www || ! -d $project/../html ]] || www=$(realpath -m -- "$project/../html")
[[ -d $www && -n $(ls -A -- "$www") ]] || exit 0
[[ ! -e $dest ]] || { echo "Xa existe $dest; non se sobrescribe." >&2; exit 1; }
mkdir -p -- "$dest"
cp -R --preserve=timestamps -- "$www/." "$dest/"
echo copied
'@
    Expand-DawScriptTemplate $text
}
function Get-DawWebRootRestoreScript {
    # Como ad na distribución nova. Os ficheiros quedan cos permisos por defecto de ad, non cos de Windows.
    $text=@'
set -euo pipefail
src=$(wslpath -u "$1")
www=$2
[[ -d $src ]] || { echo "Falta a copia $src." >&2; exit 1; }
mkdir -p -- "$www"
cp -R --preserve=timestamps --no-preserve=mode -- "$src/." "$www/"
'@
    Expand-DawScriptTemplate $text
}
# Documentos da conta, onde quedan as copias da raíz web (pode estar en OneDrive).
function Get-DawDocumentsDirectory { [Environment]::GetFolderPath('MyDocuments') }
function Backup-DawWebRoot {
    # Copia en Documentos a raíz web dunha distribución antes de eliminala; devolve a copia ou $null.
    # A ruta queda en PendingRestore ata que Restore-DawPendingWebRoot a copie na distribución nova.
    param([string]$Distribution,[string[]]$ProjectPaths,[string]$PendingRestore)
    $documents=Get-DawDocumentsDirectory
    if(-not $documents){throw 'Non se atopou o cartafol Documentos da conta.'}
    # Ruta de Windows para wslpath: sen Join-Path, que fóra de Windows non coñece a unidade C:.
    $target=$documents.TrimEnd('\')+'\DAW-Dev-www-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$Distribution
    $lines=@(Invoke-DawNative 'wsl.exe' (@('-d',$Distribution,'-u','root','--exec','bash','-c',(Get-DawWebRootBackupScript),'daw-backup',$target)+$ProjectPaths))
    if(-not(@($lines|ForEach-Object {$_.Trim()}) -contains 'copied')){return $null}
    Add-Content -LiteralPath $PendingRestore -Value $target -Encoding UTF8
    return $target
}
function Get-DawProjectMoveScript {
    # Como root na distribución. Argumentos: a contorna actual, as rutas do código web, os datos
    # e Angular, e as rutas anteriores do proxecto. Move a contorna á actual, se segue nunha
    # anterior, e www, data e angular fóra dela, ao home. Compróbao todo antes de mover nada, e
    # para antes os contedores do proxecto (montan as rutas anteriores; o seguinte arranque
    # recréaos). As rutas anteriores quedan como ligazóns, e reapunta as ordes daw-* do modelo.
    $text=@'
set -euo pipefail
fail() { echo "$1" >&2; exit 1; }
new=$1 web=$2 data=$3 angular=$4
shift 4
old=
for candidate in "$@"; do
    if [[ -d $candidate && ! -L $candidate ]]; then
        [[ -f $candidate/compose.yaml ]] || fail "$candidate non é o proxecto DAW Dev; non se moveu."
        old=$candidate
        break
    fi
done
if [[ -n $old ]]; then
    [[ ! -e $new && ! -L $new ]] || fail "Existen $old e $new; non se moveu ningún."
    project=$old
else
    project=$new
    [[ -d $project && ! -L $project ]] || exit 0
fi
moves=()
empties=()
for pair in "www=$web" "data=$data" "angular=$angular"; do
    name=${pair%%=*} to=${pair#*=}
    [[ -d $project/$name && ! -L $project/$name ]] || continue
    if [[ -e $to || -L $to ]]; then
        if [[ -d $to && ! -L $to && -z $(ls -A -- "$project/$name") ]]; then
            empties+=("$name")
            continue
        fi
        [[ -d $to && ! -L $to && -z $(ls -A -- "$to") ]] || fail "Existen $project/$name e $to; non se moveu ningún."
    fi
    moves+=("$name" "$to")
done
if [[ -z $old && ${#moves[@]} -eq 0 ]]; then
    for name in "${empties[@]}"; do
        rmdir -- "$project/$name"
    done
    exit 0
fi
for i in {1..60}; do docker info >/dev/null 2>&1 && break; sleep 1; done
if docker info >/dev/null 2>&1; then
    for dir in "$project" "$@"; do
        ids=$(docker ps -q --filter "label=com.docker.compose.project.working_dir=$dir")
        [[ -z $ids ]] || docker stop $ids >/dev/null
    done
fi
if [[ -n $old ]]; then
    mv -T -- "$old" "$new"
    ln -s -- "$new" "$old"
    chown -h --reference="$new" -- "$old"
    # DAW_BIN_DIR só nas probas.
    for link in "${DAW_BIN_DIR:-/usr/local/bin}"/daw*; do
        [[ -L $link ]] || continue
        target=$(readlink -- "$link")
        for previous in "$@"; do
            if [[ $target == "$previous/scripts/daw.sh" ]]; then ln -sfn -- "$new/scripts/daw.sh" "$link"; fi
        done
    done
fi
for name in "${empties[@]}"; do
    rmdir -- "$new/$name"
done
for ((i = 0; i < ${#moves[@]}; i += 2)); do
    name=${moves[i]} to=${moves[i+1]}
    [[ ! -d $to ]] || rmdir -- "$to"
    mv -T -- "$new/$name" "$to"
    # Dentro da contorna, a ruta anterior leva ao novo sitio: un .env ou un acceso anteriores.
    ln -s -- "$to" "$new/$name"
    chown -h --reference="$to" -- "$new/$name"
done
echo moved
'@
    Expand-DawScriptTemplate $text
}
function Move-DawProjectDirectory {
    # Devolve $true se moveu a contorna ou o que é do alumnado á disposición actual.
    param([string]$Distribution)
    $arguments=@('-d',$Distribution,'-u','root','--exec','bash','-c',(Get-DawProjectMoveScript),'daw-move',(Get-DawLinuxProjectPath),(Get-DawLinuxWebPath),(Get-DawLinuxDataPath),(Get-DawLinuxAngularPath))+@(Get-DawPreviousLinuxProjectPaths)
    $lines=@(Invoke-DawNative 'wsl.exe' $arguments)
    return (@($lines|ForEach-Object {([string]$_).Trim()}) -contains 'moved')
}
function Get-DawPreviousLinksScript {
    # Como root. Argumentos: a contorna actual e as rutas anteriores. Retira as ligazóns das rutas
    # anteriores que levan á contorna, cando xa hai lanzadores e accesos novos (activación).
    $text=@'
set -euo pipefail
new=$(realpath -m -- "$1")
shift
# Primeiro todas: ~/workspace leva a ~/.daw a través de ~/daw.
remove=()
for old in "$@"; do
    [[ -L $old && $(realpath -m -- "$old") == "$new" ]] && remove+=("$old")
done
for old in "${remove[@]}"; do
    rm -- "$old"
    echo "removed $old"
done
'@
    Expand-DawScriptTemplate $text
}
function Remove-DawPreviousProjectLinks {
    param([string]$Distribution)
    @(Invoke-DawNative 'wsl.exe' (@('-d',$Distribution,'-u','root','--exec','bash','-c',(Get-DawPreviousLinksScript),'daw-links',(Get-DawLinuxProjectPath))+@(Get-DawPreviousLinuxProjectPaths)))|ForEach-Object {([string]$_).Trim()}|Where-Object {$_ -like 'removed *'}|ForEach-Object {$_.Substring(8)}
}
function Restore-DawPendingWebRoot {
    # Copia na raíz web do proxecto as copias pendentes, na orde en que se fixeron. Os ficheiros
    # copiados substitúen os do proxecto novo; a copia de Documentos consérvase.
    param([string]$Distribution,[string]$PendingRestore)
    if(-not(Test-Path -LiteralPath $PendingRestore -PathType Leaf)){return @()}
    $restored=@()
    foreach($backup in @(Get-Content -LiteralPath $PendingRestore -Encoding UTF8|Where-Object {$_.Trim()})){
        Invoke-DawNative 'wsl.exe' @('-d',$Distribution,'-u','ad','--exec','bash','-c',(Get-DawWebRootRestoreScript),'daw-restore',$backup.Trim(),(Get-DawLinuxWebPath))|Out-Null
        $restored+=$backup.Trim()
    }
    Remove-Item -LiteralPath $PendingRestore -Force
    return $restored
}
function Remove-DawLegacyInstall {
    # Na conta actual: a distribución, o estado, os lanzadores e o acceso directo anteriores.
    # Unha Debian sen o marcador do modelo anterior é persoal e consérvase. Antes de eliminar a
    # distribución copia a súa raíz web en Documentos (PendingRestore).
    param([string]$PendingRestore)
    $legacy=Get-DawLegacyInstall
    $result=[pscustomobject]@{Removed=@();Backup=$null}
    if($legacy.Distribution -in @(Get-DawDistributions) -and (Test-DawModelMarker $legacy.Distribution $legacy.MarkerPath $legacy.Marker)){
        $result.Backup=Backup-DawWebRoot $legacy.Distribution $legacy.ProjectPaths $PendingRestore
        Remove-DawDistribution $legacy.Distribution $legacy.MarkerPath $legacy.Marker
        $result.Removed+="wsl:$($legacy.Distribution)"
    }
    foreach($dir in @((Join-Path $env:LOCALAPPDATA (Split-Path -Leaf $legacy.StateRelativePath)),(Join-Path $env:LOCALAPPDATA $legacy.LauncherDirectory))){
        if(-not(Test-Path -LiteralPath $dir)){continue}
        if((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw "$dir é unha ligazón; conservouse."}
        Remove-Item -LiteralPath $dir -Recurse -Force
        $result.Removed+=$dir
    }
    $desktop=[Environment]::GetFolderPath('Desktop')
    if($desktop){
        $link=Join-Path $desktop $legacy.Shortcut
        if(Test-Path -LiteralPath $link -PathType Leaf){Remove-Item -LiteralPath $link -Force;$result.Removed+=$link}
    }
    return $result
}
function Get-DawRunCommand {
    # A orde dun valor Run creado por estes scripts (powershell.exe -EncodedCommand), ou $null.
    param([string]$Name)
    $property=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name $Name -ErrorAction SilentlyContinue
    if(-not $property){return $null}
    $value=$property.$Name
    if($value -notmatch '^powershell\.exe .* -EncodedCommand ([A-Za-z0-9+/=]+)$'){throw "$Name ten unha orde allea; conservouse para revisión."}
    [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Matches[1]))
}
function Set-DawAutoStart {
    param([switch]$Enabled)
    $path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    $command="& '$(Get-DawPackageDirectory)\autostart.ps1'"
    $existing=Get-DawRunCommand 'DAWDev'
    if($existing -and $existing -ne $command){throw 'DAWDev apunta a outro programa; conservouse.'}
    if($Enabled){
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        New-ItemProperty -Path $path -Name DAWDev -Value "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encoded" -PropertyType String -Force|Out-Null
    }elseif($existing){Remove-ItemProperty -LiteralPath $path -Name DAWDev -ErrorAction Stop}
}
function Remove-DawLegacyPackage {
    # No posto, como administrador: o paquete e o autoarranque da instalación anterior.
    $legacy=Get-DawLegacyInstall
    $removed=@()
    $existing=Get-DawRunCommand $legacy.RunValue
    if($existing){
        if($existing -ne $legacy.AutoStartCommand){throw "$($legacy.RunValue) apunta a outro programa; conservouse."}
        Remove-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name $legacy.RunValue -ErrorAction Stop
        $removed+="Run:$($legacy.RunValue)"
    }
    $dir=$legacy.PackageDirectory
    if(Test-Path -LiteralPath $dir){
        $items=@(Get-Item -LiteralPath $dir -Force)+@(Get-ChildItem -LiteralPath $dir -Recurse -Force)
        if($items|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}){throw "$dir contén ligazóns ou junctions; conservouse."}
        Remove-Item -LiteralPath $dir -Recurse -Force
        $removed+=$dir
        # O daw-activate das contas sen activar aínda chama ao activador anterior: queda só
        # este, protexido, e leva á activación nova.
        New-Item -ItemType Directory -Path $dir|Out-Null
        Set-DawProtectedAcl $dir
        [IO.File]::WriteAllText((Join-Path $dir $legacy.Activator),(Get-DawLegacyActivatorScript),(New-Object Text.UTF8Encoding($true)))
    }
    return $removed
}
function Get-DawLegacyActivatorScript {
    # Os lanzadores anteriores chaman a activar-dawdev.ps1 cos parámetros de entón.
    @"
# Transición: o daw-activate das contas anteriores a DAW Dev chama a este ficheiro.
param([string]`$Distribution,[switch]`$SenVSCode,[switch]`$SenPausa)
& '$(Get-DawPackageDirectory)\activate.ps1' -SkipVSCode:`$SenVSCode -NoPause:`$SenPausa
exit `$LASTEXITCODE
"@.Replace("`n","`r`n")
}
function Set-DawProtectedAcl {
    # Como o paquete: escritura só para SYSTEM e Administradores; lectura e execución para Usuarios.
    param([string]$Path)
    $acl=New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    $admins=New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $acl.SetOwner($admins)
    foreach($sid in 'S-1-5-18','S-1-5-32-544','S-1-5-32-545'){
        $rights=if($sid -eq 'S-1-5-32-545'){'ReadAndExecute'}else{'FullControl'}
        $identity=New-Object Security.Principal.SecurityIdentifier($sid)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($identity,$rights,'ContainerInherit,ObjectInherit','None','Allow')))
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}
function Find-DawCode {
    foreach($path in @((Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'),(Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\Code.exe'))){
        if(Test-Path -LiteralPath $path){return $path}
    }
    throw 'Falta VS Code. Instalalo para este usuario ou indicar SkipVSCode para unha instalación explicitamente sen IDE.'
}
function Find-DawCodeCli {
    param([string]$Code)
    $dir=Split-Path $Code
    # Desde a 1.10x, VS Code garda os recursos nun directorio co commit (6a49527b96\resources\...);
    # bin\code.cmd apunta ao da versión actual. A ruta antiga queda como alternativa.
    $cmd=[IO.Path]::Combine($dir,'bin','code.cmd')
    if(Test-Path -LiteralPath $cmd -PathType Leaf){
        $m=[regex]::Match([IO.File]::ReadAllText($cmd),'%~dp0\.\.\\([^"%]*?resources\\app\\out\\cli\.js)')
        if($m.Success){
            $cli=[IO.Path]::Combine($dir,$m.Groups[1].Value.Replace('\',[IO.Path]::DirectorySeparatorChar))
            if(Test-Path -LiteralPath $cli -PathType Leaf){return $cli}
        }
    }
    $cli=[IO.Path]::Combine($dir,'resources','app','out','cli.js')
    if(Test-Path -LiteralPath $cli -PathType Leaf){return $cli}
    throw 'Falta a CLI de VS Code.'
}
function Get-DawInstalledCodeExtensions {
    # As extensións do VS Code de Windows desta conta e as súas versións (id@versión), coa CLI de VS Code.
    $code=Find-DawCode
    $cli=Find-DawCodeCli $code
    $old=$env:ELECTRON_RUN_AS_NODE
    try{
        $env:ELECTRON_RUN_AS_NODE='1'
        $lines=@(Invoke-DawNative $code @($cli,'--list-extensions','--show-versions')|ForEach-Object {([string]$_).Trim()}|Where-Object {$_})
    }finally{$env:ELECTRON_RUN_AS_NODE=$old}
    $result=[ordered]@{}
    foreach($line in $lines){
        $parts=$line.Split([char]'@',2)
        $result[$parts[0].ToLowerInvariant()]=if($parts.Count -eq 2){$parts[1]}else{$null}
    }
    $result
}
function Get-DawInstalledCodeExtensionIds {@((Get-DawInstalledCodeExtensions).Keys)}
function Test-DawNewerVersion {
    # Se Candidate (1.2.10) é posterior a Current (1.2.9). Sen dúas versións recoñecibles, non.
    param([string]$Candidate,[string]$Current)
    $a=$null;$b=$null
    if(-not [version]::TryParse($Candidate,[ref]$a) -or -not [version]::TryParse($Current,[ref]$b)){return $false}
    return $a -gt $b
}
function Install-DawCodeExtensions {
    # Dev Containers e WSL no VS Code de Windows. Primeiro o .vsix do paquete, sen Internet; se o
    # paquete non o ten ou VS Code o rexeita, o Marketplace. Falla se algunha non queda instalada.
    param([string]$PackageDirectory)
    $code=Find-DawCode
    $cli=Find-DawCodeCli $code
    $files=@{}
    $manifestPath=if($PackageDirectory){Join-Path $PackageDirectory 'manifest.json'}
    if($manifestPath -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)){
        # O SHA256 xa o comprobou Assert-DawPackage ao comezo da activación.
        $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
        foreach($entry in @(Get-DawPackageCodeExtensions $manifest)){$files[[string]$entry.Id]=Join-Path $PackageDirectory $entry.File}
    }
    $required=Get-DawWindowsCodeExtensionIds
    $versions=Get-DawInstalledCodeExtensions
    $installed=@($versions.Keys)
    $errors=@()
    $old=$env:ELECTRON_RUN_AS_NODE
    try{
        $env:ELECTRON_RUN_AS_NODE='1'
        foreach($id in @($required|Where-Object {$_ -notin $installed})){
            $sources=@()
            if($files.ContainsKey($id)){$sources+=$files[$id]}
            $sources+=$id
            foreach($source in $sources){
                try{Invoke-DawNative $code @($cli,'--install-extension',$source)|Out-Null;break}
                catch{$errors+="${id}: $($_.Exception.Message.Trim())"}
            }
        }
        # Unha versión anterior á do paquete actualízase desde el, sen Internet: sen o paquete,
        # VS Code só a actualizaría con conexión. Se VS Code rexeita o .vsix, segue a instalada.
        foreach($id in @($required|Where-Object {$_ -in $installed -and $files.ContainsKey($_)})){
            try{$version=(Get-DawVsixInfo $files[$id]).Version}catch{continue}
            if(-not(Test-DawNewerVersion $version $versions[$id])){continue}
            try{Invoke-DawNative $code @($cli,'--install-extension',$files[$id])|Out-Null}
            catch{Write-Warning "Non se actualizou $id $($versions[$id]) á $version do paquete: $($_.Exception.Message.Trim())"}
        }
    }finally{$env:ELECTRON_RUN_AS_NODE=$old}
    $installed=@(Get-DawInstalledCodeExtensionIds)
    $missing=@($required|Where-Object {$_ -notin $installed})
    if($missing.Count){
        $detail=if($errors.Count){' ('+($errors -join ' | ')+')'}else{''}
        throw "Extensión non confirmada: $($missing -join ', ')$detail"
    }
    return $required
}
function Get-DawVsixInfo {
    # Identificador, versión e VS Code mínimo (engines.vscode) do package.json dun .vsix.
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($Path)
    try{
        $entry=$zip.GetEntry('extension/package.json')
        if(-not $entry){throw "Non é un .vsix: $Path"}
        $reader=New-Object IO.StreamReader($entry.Open())
        try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}
    }finally{$zip.Dispose()}
    try{
        $json=$text|ConvertFrom-Json
        $info=@{Id=("$($json.publisher).$($json.name)").ToLowerInvariant();Version=[string]$json.version;Engine=[string]$json.engines.vscode}
    }catch{
        # Windows PowerShell 5.1 rexeita claves que só difiren en maiúsculas: só os campos precisos.
        $field={param($pattern) $m=[regex]::Match($text,$pattern);if($m.Success){$m.Groups[1].Value}else{''}}
        $info=@{Id=((& $field '"publisher"\s*:\s*"([^"]+)"')+'.'+(& $field '"name"\s*:\s*"([^"]+)"')).ToLowerInvariant();Version=(& $field '"version"\s*:\s*"([^"]+)"');Engine=(& $field '"engines"\s*:\s*\{[^}]*"vscode"\s*:\s*"([^"]+)"')}
    }
    [pscustomobject]$info
}
function Test-DawCodeEngine {
    # Se un VS Code (1.122.0) cumpre engines.vscode dunha extensión (^1.101.0, >=1.95.0...).
    # Compárase o mínimo; sen versión recoñecible (*), acéptase.
    param([string]$Engine,[string]$CodeVersion)
    $minimum=[regex]::Match([string]$Engine,'\d+\.\d+\.\d+')
    if(-not $minimum.Success){return $true}
    $code=[regex]::Match([string]$CodeVersion,'^\d+\.\d+\.\d+')
    if(-not $code.Success){throw "Versión de VS Code non válida: $CodeVersion"}
    return ([version]$minimum.Value) -le ([version]$code.Value)
}
function New-DawShortcut {
    param([string]$Distribution)
    $desktop=[Environment]::GetFolderPath('Desktop')
    if(-not $desktop -or -not(Test-Path -LiteralPath $desktop)){throw 'Non se atopou o Escritorio do alumno.'}
    $path=Join-Path $desktop 'DAW - Web.lnk'
    $shell=New-Object -ComObject WScript.Shell
    $link=$shell.CreateShortcut($path)
    $link.TargetPath=ConvertTo-DawWslPath $Distribution (Get-DawLinuxWebPath)
    $link.Description='Codigo web de DAW Dev (www)'
    $link.Save()
    if(-not(Test-Path -LiteralPath $path)){throw 'Non se confirmou o acceso directo.'}
    return $path
}
function Get-DawStudent {
    $owners=@{}
    foreach($process in @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'")){
        if($process.SessionId -le 0){continue}
        $sid=Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid
        if($sid.ReturnValue -eq 0){$owners[$sid.Sid]=$true}
    }
    if($owners.Count -ne 1){throw 'Precísase unha única sesión de alumno conectada.'}
    $id=@($owners.Keys)[0]
    $profiles=@(Get-CimInstance Win32_UserProfile|Where-Object {$_.SID -eq $id -and -not $_.Special})
    if($profiles.Count -ne 1){throw 'Non se atopou o perfil do alumno.'}
    [pscustomobject]@{SID=$id;Profile=$profiles[0].LocalPath}
}
function Test-DawRequestState {
    param($State,[string]$RequestId,[string]$UserSid)
    if(-not $State -or -not $State.PSObject.Properties['Schema'] -or $State.Schema -ne 2){return $false}
    foreach($name in @('RequestId','UserSid','Phase','Success','Error')){if(-not $State.PSObject.Properties[$name]){return $false}}
    if($State.Success -isnot [bool]){return $false}
    if($State.RequestId -ne $RequestId -or $State.UserSid -ne $UserSid){return $false}
    return $State.Phase -eq 'Completed'
}
function Invoke-DawStudentInstall {
    param([int]$TimeoutSeconds=1800,[switch]$Reinstall,[switch]$WithoutCode)
    $target=Get-DawPackageDirectory
    if(-not(Test-Path -LiteralPath "$target\daw-classroom.psm1")){throw 'Falta o paquete DAW Dev no equipo: executar antes CopyPackage.'}
    $arguments="-PackageDirectory '$target'"
    if($Reinstall){$arguments+=' -Reinstall'}
    if($WithoutCode){$arguments+=' -SkipVSCode'}
    Invoke-DawUserTask 'InstallUser' "$target\install-user.ps1" $arguments (Get-DawStateFiles).Install 'Instalación' $TimeoutSeconds
}
function Invoke-DawStudentVerify {
    # Comproba a contorna na conta do alumno conectado (verify-user.ps1), sen elevación.
    param([int]$TimeoutSeconds=1800)
    $target=Get-DawPackageDirectory
    if(-not(Test-Path -LiteralPath "$target\verify-user.ps1")){throw 'Falta o paquete DAW Dev no equipo: executar antes CopyPackage.'}
    Invoke-DawUserTask 'Verify' "$target\verify-user.ps1" "-PackageDirectory '$target'" (Get-DawStateFiles).Verify 'Verificación' $TimeoutSeconds
}
function Get-DawWindowsState {
    # No posto, como administrador: o que falta en Windows para usar WSL2.
    $cpu=Get-CimInstance Win32_Processor|Select-Object -First 1
    $virtualization=[bool]($cpu.VirtualizationFirmwareEnabled -or (Get-CimInstance Win32_ComputerSystem).HypervisorPresent)
    $states=@('VirtualMachinePlatform','Microsoft-Windows-Subsystem-Linux'|ForEach-Object {[string](Get-WindowsOptionalFeature -Online -FeatureName $_).State})
    $wsl=$false
    try{& wsl.exe --version *> $null;$wsl=$LASTEXITCODE -eq 0}catch{}
    $pending=($states -contains 'EnablePending') -or
        (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    $sessions=@(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'"|Where-Object {$_.SessionId -gt 0}).Count
    [pscustomobject]@{Virtualization=$virtualization;Features=-not(@($states|Where-Object {$_ -notin @('Enabled','EnablePending')}).Count);Wsl=$wsl;RebootPending=[bool]$pending;Sessions=$sessions}
}
function ConvertTo-DawWindowsStatus {
    # Para deploy.ps1: OK, Preparar (faltan características ou WSL), Reiniciar ou Erro (sen virtualización).
    param($State)
    if(-not $State){return 'Erro'}
    if(-not $State.Virtualization){return 'Erro'}
    if(-not $State.Features -or -not $State.Wsl){return 'Preparar'}
    if($State.RebootPending){return 'Reiniciar'}
    return 'OK'
}
function ConvertTo-DawDeployStatus {
    # Resultado dun posto en deploy.ps1: OK, Sen alumno (non hai unha única sesión), Sen activar
    # (a conta conectada aínda non activou DAW Dev) ou Erro.
    param($Result)
    if(-not $Result){return 'Erro'}
    if($Result.Success){return 'OK'}
    # Só unha mensaxe dunha liña que empece pola frase: un erro que cite o código do módulo
    # (varias liñas) contén tamén estas frases.
    if([string]$Result.Error -cmatch '^Precísase unha única sesión de alumno conectada[^\r\n]*$'){return 'Sen alumno'}
    if([string]$Result.Error -cmatch '^(Verificación \S+ fallou: )?Esta conta aínda non activou DAW Dev[^\r\n]*$'){return 'Sen activar'}
    return 'Erro'
}
function Invoke-DawUserTask {
    # Runs a package script as the single connected student and waits for the state of THIS request.
    param([string]$Name,[string]$Script,[string]$Arguments,[string]$StateFile,[string]$Label,[int]$TimeoutSeconds=1800)
    $user=Get-DawStudent
    $id=[guid]::NewGuid().ToString('N')
    $task="DAW-$Name-$id"
    $status=Join-Path (Get-DawStateDirectory $user.Profile) $StateFile
    $command="& '$Script' -RequestId '$id' -ExpectedUserSid '$($user.SID)'"
    if($Arguments){$command+=' '+$Arguments}
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $registered=$false
    try{
        $principal=New-ScheduledTaskPrincipal -UserId $user.SID -LogonType Interactive -RunLevel Limited
        $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        # Con Windows Terminal como terminal predeterminado, -WindowStyle Hidden non agocha a xanela:
        # o alumno ve a xanela e, se a pecha, a tarefa morre con 0xC000013A (aula 34, 18-11-2026).
        # conhost --headless non abre xanela, pero devolve sempre 0; o fin sen estado detéctase abaixo.
        $conhost=Join-Path $env:SystemRoot 'System32\conhost.exe'
        $action=New-ScheduledTaskAction -Execute $conhost -Argument "--headless `"$ps`" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encoded"
        $settings=New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit (New-TimeSpan -Seconds $TimeoutSeconds) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $task -Principal $principal -Action $action -Settings $settings|Out-Null
        $registered=$true
        $started=Get-Date
        Start-ScheduledTask -TaskName $task
        $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        $endedAt=$null
        do{
            if(Test-Path -LiteralPath $status){
                $state=$null
                try{$state=Get-Content -LiteralPath $status -Raw -Encoding UTF8|ConvertFrom-Json}catch{ } # Old/torn state cannot confirm this request.
                if(Test-DawRequestState $state $id $user.SID){
                    if(-not $state.Success){throw "$Label $id fallou: $($state.Error)"}
                    return $state
                }
            }
            $info=Get-ScheduledTaskInfo -TaskName $task
            $current=Get-ScheduledTask -TaskName $task
            if($current.State -ne 'Running' -and $info.LastRunTime -ge $started.AddSeconds(-2)){
                if($info.LastTaskResult -ne 0){throw "A tarefa $task fallou: $($info.LastTaskResult). Revisar políticas e logs."}
                # Rematou sen erro pero sen o estado desta solicitude: dáselle un momento á escritura.
                if(-not $endedAt){$endedAt=[DateTime]::UtcNow}
                elseif(([DateTime]::UtcNow-$endedAt).TotalSeconds -ge 5){throw "A tarefa $task rematou sen informar do resultado. Revisar $StateFile e o log antes de repetir."}
            }
            Start-Sleep -Milliseconds 500
        }while([DateTime]::UtcNow -lt $deadline)
        throw "Tempo esgotado: $Label $id. Revisar $StateFile e o log; non repetir ata comprobar a operación incompleta."
    }finally{
        if($registered){Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue;Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue}
    }
}
function Invoke-DawBoundedJobs {
    param([object[]]$Items,[ValidateRange(1,10)][int]$ThrottleLimit=5,[scriptblock]$Worker,[object[]]$CommonArguments=@())
    $jobs=@();$results=@()
    try{
        foreach($item in $Items){
            while(@($jobs|Where-Object {$_.State -in @('Running','NotStarted')}).Count -ge $ThrottleLimit){Wait-Job -Job $jobs -Any|Out-Null;$done=@($jobs|Where-Object {$_.State -notin @('Running','NotStarted')});foreach($j in $done){$results+=@(Receive-Job $j -ErrorAction Stop);Remove-Job $j;$jobs=@($jobs|Where-Object {$_.Id -ne $j.Id})}}
            $jobs+=Start-Job -ScriptBlock $Worker -ArgumentList (@($item)+$CommonArguments)
        }
        foreach($job in $jobs){Wait-Job $job|Out-Null;$results+=@(Receive-Job $job -ErrorAction Stop);if($job.State -eq 'Failed'){throw "Job $($job.Id) fallou."}}
        return $results
    }finally{foreach($job in $jobs){Stop-Job $job -ErrorAction SilentlyContinue;Remove-Job $job -Force -ErrorAction SilentlyContinue}}
}
function Get-DawSetupFiles { @('daw.ps1','install-daw-commands.ps1','install-user.ps1','verify-user.ps1','autostart.ps1','activate.ps1','daw-classroom.psm1') }
function Set-DawStartMenuShortcut {
    # Activación manual para calquera usuario: unha entrada no menú Inicio común, nada no inicio de sesión.
    param([string]$Directory=(Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\DAW Dev'),[string]$Package=(Get-DawPackageDirectory))
    New-Item -ItemType Directory -Path $Directory -Force|Out-Null
    $path=Join-Path $Directory 'Activar DAW Dev.lnk'
    $shell=New-Object -ComObject WScript.Shell
    $link=$shell.CreateShortcut($path)
    $link.TargetPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $link.Arguments="-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Package 'activate.ps1')`""
    $link.WorkingDirectory=$Package
    # Texto sen tiles: o módulo non leva BOM e Windows PowerShell 5.1 leríao como ANSI.
    $link.Description='Activa DAW Dev (WSL e Docker) na conta que o abre'
    $link.Save()
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Non se confirmou a entrada do menú Inicio.'}
    return $path
}
function Get-DawActivatorDirectory { 'C:\DAW-Dev' }
function Set-DawActivator {
    # Activación con dobre clic nunha ruta curta e visible no Explorador (ProgramData está oculta),
    # para cando o menú Inicio aínda non amosa a entrada. Por defecto, en C:\ calquera usuario
    # pode crear e cambiar ficheiros: o directorio queda coa ACL do paquete, así que só escriben
    # SYSTEM e Administradores e un alumno non pode cambiar o que executa outro.
    param([string]$Directory=(Get-DawActivatorDirectory),[string]$Package=(Get-DawPackageDirectory))
    $name='Activar DAW Dev.cmd'
    if(Test-Path -LiteralPath $Directory){
        $item=Get-Item -LiteralPath $Directory -Force
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "$Directory é unha ligazón ou junction."}
        if(-not $item.PSIsContainer){throw "$Directory non é un directorio."}
        # Un alumno puido crealo antes: só se acepta baleiro ou co activador.
        if(@(Get-ChildItem -LiteralPath $Directory -Force|Where-Object {$_.Name -ne $name -or $_.PSIsContainer}).Count){throw "$Directory contén ficheiros alleos; non se creou o activador."}
    }
    New-Item -ItemType Directory -Path $Directory -Force|Out-Null
    Set-DawProtectedAcl $Directory
    $path=Join-Path $Directory $name
    $powershell='%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe'
    $text="@echo off`r`nrem Activa DAW Dev na conta que o abre. Igual ca DAW Dev > Activar DAW Dev no menu Inicio.`r`n`"$powershell`" -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Package 'activate.ps1')`"`r`n"
    [IO.File]::WriteAllText($path,$text,(New-Object Text.ASCIIEncoding))
    # Só a ACL herdada do directorio, aínda que o ficheiro xa existise con outra.
    $acl=New-Object Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($false,$false)
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    Set-Acl -LiteralPath $path -AclObject $acl
    return $path
}
function Assert-DawManifest {
    # O manifesto que escribe build-package.ps1; os paquetes de DAW-Aula non se recoñecen.
    param($Manifest)
    foreach($name in 'Schema','Marker','Image','Sha256','LinuxUser','LinuxProjectPath'){
        if(-not $Manifest.PSObject.Properties[$name]){throw 'Manifesto de modelo non recoñecido: crear o paquete con build-package.ps1.'}
    }
    if($Manifest.Schema -ne 2 -or $Manifest.Marker -cne (Get-DawModelMarker).Value -or $Manifest.Image -cne (Get-DawModelArchive) -or $Manifest.Sha256 -notmatch '^[0-9a-fA-F]{64}$' -or $Manifest.LinuxUser -cne 'ad' -or $Manifest.LinuxProjectPath -cnotin @(@(Get-DawLinuxProjectPath)+@(Get-DawPreviousLinuxProjectPaths))){
        throw 'Manifesto de modelo non recoñecido: crear o paquete con build-package.ps1.'
    }
}
function Assert-DawPackage {
    param([string]$Directory)
    $manifest=Get-Content -LiteralPath (Join-Path $Directory 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert-DawManifest $manifest
    if(-not $manifest.PSObject.Properties['ScriptSha256']){throw 'O manifesto non ten os SHA256 dos scripts: actualizalos con update-package.ps1.'}
    foreach($name in Get-DawSetupFiles){
        $property=$manifest.ScriptSha256.PSObject.Properties[$name]
        if(-not $property -or $property.Value -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath (Join-Path $Directory $name) -Algorithm SHA256).Hash -ne $property.Value){throw "SHA256 do script non coincide: $name"}
    }
    if((Get-FileHash -LiteralPath (Join-Path $Directory $manifest.Image) -Algorithm SHA256).Hash -ne $manifest.Sha256){throw 'O SHA256 da imaxe non coincide.'}
    foreach($extra in @(Get-DawPackageImages $manifest)){
        $path=Join-Path $Directory $extra.File
        if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $extra.Sha256.ToUpperInvariant()){throw "SHA256 da imaxe Docker non coincide: $($extra.File)"}
    }
    foreach($server in @(Get-DawPackageCodeServers $manifest)){
        $path=Join-Path $Directory $server.File
        if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $server.Sha256.ToUpperInvariant()){throw "SHA256 de VS Code Server non coincide: $($server.File)"}
    }
    foreach($extension in @(Get-DawPackageCodeExtensions $manifest)){
        $path=Join-Path $Directory $extension.File
        if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $extension.Sha256.ToUpperInvariant()){throw "SHA256 da extensión de VS Code non coincide: $($extension.File)"}
    }
    return $manifest
}
function Get-DawPackageImages {
    # Imaxes Docker adicionais que se cargan na conta cando se precisan.
    param($Manifest)
    if(-not $Manifest.PSObject.Properties['Images']){return @()}
    foreach($extra in @($Manifest.Images)){
        if([string]$extra.File -cnotmatch '^[A-Za-z0-9._-]+\.tar(\.gz)?$' -or [string]$extra.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or [string]$extra.Name -notmatch '^[a-z0-9./:_-]+$'){throw 'Imaxe Docker do manifesto non recoñecida.'}
        $extra
    }
}
function Add-DawPackageImage {
    # No profesor: copia un docker save (.tar ou .tar.gz) ao paquete e rexístrao co seu SHA256.
    param([string]$Directory,[string]$Archive,[string]$Name)
    $manifest=Assert-DawPackage $Directory
    $file=Split-Path -Leaf $Archive
    $target=Join-Path $Directory $file
    if([IO.Path]::GetFullPath($Archive) -ne [IO.Path]::GetFullPath($target)){Copy-Item -LiteralPath $Archive -Destination $target -Force}
    $entry=[pscustomobject]@{File=$file;Name=$Name;Sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash}
    $images=@(Get-DawPackageImages $manifest|Where-Object {$_.File -ne $file -and $_.Name -ne $Name})+$entry
    $manifest|Add-Member NoteProperty Images $images -Force
    Write-DawState (Join-Path $Directory 'manifest.json') $manifest
    Assert-DawPackage $Directory|Out-Null
    return $entry
}
# VS Code Server sen Internet: o paquete leva o servidor de cada commit de VS Code dos postos.
# A activación e daw-code instálano na distribución (Remote - WSL) e na caché de Dev Containers.
function Get-DawCodeServerFile { param([string]$Commit) "vscode-server-$Commit.tar.gz" }
function Get-DawPackageCodeServers {
    param($Manifest)
    if(-not $Manifest.PSObject.Properties['CodeServers']){return @()}
    foreach($server in @($Manifest.CodeServers)){
        if([string]$server.Commit -cnotmatch '^[0-9a-f]{40}$' -or [string]$server.File -cne (Get-DawCodeServerFile $server.Commit) -or [string]$server.Sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'VS Code Server do manifesto non recoñecido.'}
        $server
    }
}
function Add-DawPackageCodeServer {
    # No profesor: copia o servidor descargado ao paquete e rexístrao co seu SHA256.
    param([string]$Directory,[string]$Archive,[string]$Commit)
    if($Commit -cnotmatch '^[0-9a-f]{40}$'){throw "Commit de VS Code non válido: $Commit"}
    $manifest=Assert-DawPackage $Directory
    $file=Get-DawCodeServerFile $Commit
    $target=Join-Path $Directory $file
    if([IO.Path]::GetFullPath($Archive) -ne [IO.Path]::GetFullPath($target)){Copy-Item -LiteralPath $Archive -Destination $target -Force}
    $entry=[pscustomobject]@{Commit=$Commit;File=$file;Sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash}
    $servers=@(Get-DawPackageCodeServers $manifest|Where-Object {$_.Commit -ne $Commit})+$entry
    $manifest|Add-Member NoteProperty CodeServers $servers -Force
    Write-DawState (Join-Path $Directory 'manifest.json') $manifest
    Assert-DawPackage $Directory|Out-Null
    return $entry
}
function Get-DawCodeExtensionFile { param([string]$Id) "vscode-extension-$Id.vsix" }
function Get-DawPackageCodeExtensions {
    param($Manifest)
    if(-not $Manifest.PSObject.Properties['CodeExtensions']){return @()}
    foreach($extension in @($Manifest.CodeExtensions)){
        if([string]$extension.Id -cnotmatch '^[a-z0-9-]+\.[a-z0-9-]+$' -or [string]$extension.File -cne (Get-DawCodeExtensionFile $extension.Id) -or [string]$extension.Sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Extensión de VS Code do manifesto non recoñecida.'}
        $extension
    }
}
function Add-DawPackageCodeExtension {
    # No profesor: copia o .vsix ao paquete e rexístrao co seu SHA256.
    param([string]$Directory,[string]$Archive,[string]$Id)
    if($Id -cnotmatch '^[a-z0-9-]+\.[a-z0-9-]+$'){throw "Extensión de VS Code non válida: $Id"}
    $manifest=Assert-DawPackage $Directory
    $file=Get-DawCodeExtensionFile $Id
    $target=Join-Path $Directory $file
    if([IO.Path]::GetFullPath($Archive) -ne [IO.Path]::GetFullPath($target)){Copy-Item -LiteralPath $Archive -Destination $target -Force}
    $entry=[pscustomobject]@{Id=$Id;File=$file;Sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash}
    $extensions=@(Get-DawPackageCodeExtensions $manifest|Where-Object {$_.Id -ne $Id})+$entry
    $manifest|Add-Member NoteProperty CodeExtensions $extensions -Force
    Write-DawState (Join-Path $Directory 'manifest.json') $manifest
    Assert-DawPackage $Directory|Out-Null
    return $entry
}
function Get-DawCodeExtensionsInstallScript {
    # Como ad, sen rede: instala os .vsix co VS Code Server do commit, en WSL (Remote - WSL) e
    # no volume do Dev Container. O volume énchese cun contedor da imaxe web: root deixa o volume
    # a nome de ad e ad instala nel.
    $text=@'
set -euo pipefail
commit=$1
pkg=$(wslpath -u "$2")
image=$3
volume=$4
shift 4
server=$HOME/.vscode-server/bin/$commit
[[ -x $server/bin/code-server ]] || { echo "Falta VS Code Server $commit." >&2; exit 1; }
files=()
for f in "$@"; do
    [[ -f $pkg/$f ]] || { echo "Falta $f no paquete." >&2; exit 1; }
    "$server/bin/code-server" --install-extension "$pkg/$f" >&2
    files+=("/pkg/$f")
done
docker run --rm --pull never --network none --user root --entrypoint sh -v "$volume:/extensions" "$image" \
    -c 'chown "$(id -u ad):$(id -g ad)" /extensions'
docker run --rm --pull never --network none --user ad --entrypoint sh \
    -v "$volume:/home/ad/.vscode-server/extensions" -v "$server:/server:ro" -v "$pkg:/pkg:ro" "$image" \
    -c 'for v in "$@"; do /server/bin/code-server --install-extension "$v" --extensions-dir /home/ad/.vscode-server/extensions --server-data-dir /tmp/daw-vscode-data >&2; done' sh "${files[@]}"
echo ready
'@
    Expand-DawScriptTemplate $text
}
function Install-DawPackageCodeExtensions {
    # As extensións do paquete, co VS Code Server xa instalado para o commit (Initialize-DawCodeServer).
    param([string]$Distribution,[string]$Commit,[string]$PackageDirectory=(Get-DawPackageDirectory))
    $manifest=Get-Content -LiteralPath (Join-Path $PackageDirectory 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
    # Só as de PHP: as de Windows (Dev Containers, WSL) non van no servidor nin no contedor.
    $extensions=@(Get-DawPackageCodeExtensions $manifest|Where-Object {$_.Id -in @(Get-DawCodeExtensionIds)})
    $files=@($extensions|ForEach-Object {$_.File})
    if(-not $files.Count){return @()}
    $arguments=@('-d',$Distribution,'-u','ad','--exec','bash','-c',(Get-DawCodeExtensionsInstallScript),'daw-code-extensions',$Commit,$PackageDirectory,(Get-DawWebImage),(Get-DawCodeExtensionsVolume))+$files
    Invoke-DawNative 'wsl.exe' $arguments 900|Out-Null
    @($extensions|ForEach-Object {$_.Id})
}
function Set-DawCodeUserSettings {
    # Na aula, evita conexións en segundo plano de VS Code a Microsoft (telemetría no contedor,
    # descargas automáticas de actualizacións que rompen a caché do servidor, consultas ao Marketplace).
    # Só engade as claves que falten: respecta calquera preferencia previa do usuario.
    param([string]$SettingsPath)
    if(-not $SettingsPath){
        if(-not $env:APPDATA){return @()}
        $SettingsPath=Join-Path $env:APPDATA 'Code\User\settings.json'
    }
    $defaults=[ordered]@{
        'telemetry.telemetryLevel'='off'
        'update.mode'='none'
        'extensions.autoCheckUpdates'=$false
        'extensions.autoUpdate'=$false
        'intelephense.telemetry.enabled'=$false
    }
    $data=[ordered]@{}
    $exists=Test-Path -LiteralPath $SettingsPath -PathType Leaf
    if($exists){
        $raw=[IO.File]::ReadAllText($SettingsPath,[Text.Encoding]::UTF8)
        if($raw.Trim()){
            $clean=($raw -split '\r?\n'|Where-Object {$_ -notmatch '^\s*//'}) -join "`n"
            $clean=[regex]::Replace($clean,',(?=\s*[}\]])','')
            $parsed=$clean|ConvertFrom-Json
            if($null -eq $parsed -or $parsed -is [array] -or $parsed -isnot [pscustomobject]){
                throw "settings.json de VS Code non é un obxecto JSON: $SettingsPath"
            }
            foreach($p in $parsed.PSObject.Properties){$data[$p.Name]=$p.Value}
        }
    }
    $added=@()
    foreach($entry in $defaults.GetEnumerator()){
        if(-not $data.Contains($entry.Key)){
            $data[$entry.Key]=$entry.Value
            $added+=$entry.Key
        }
    }
    if($added.Count -or -not $exists){
        $parent=Split-Path -Parent $SettingsPath
        if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
        Write-DawState $SettingsPath $data
    }
    return @($added)
}
function Set-DawCodeMachinePolicy {
    # No posto, como administrador: política oficial de VS Code (VSCode.admx) para todas as contas.
    # Desactiva a telemetría (evita ECONNRESET a OneCollector no Dev Container) e as actualizacións
    # automáticas (evita timeouts e mantén o commit do VS Code Server do paquete).
    param([string]$RegistryPath='HKLM:\SOFTWARE\Policies\Microsoft\VSCode')
    if(-not(Test-Path -LiteralPath $RegistryPath)){New-Item -Path $RegistryPath -Force|Out-Null}
    New-ItemProperty -Path $RegistryPath -Name 'TelemetryLevel' -Value 'off' -PropertyType String -Force|Out-Null
    New-ItemProperty -Path $RegistryPath -Name 'UpdateMode' -Value 'none' -PropertyType String -Force|Out-Null
}
function Get-DawCodeCommit {
    # O commit do VS Code instalado, de product.json, sen abrir VS Code.
    param([string]$Code)
    $product=Join-Path (Split-Path -Parent (Split-Path -Parent (Find-DawCodeCli $Code))) 'product.json'
    $data=Get-Content -LiteralPath $product -Raw -Encoding UTF8|ConvertFrom-Json
    if([string]$data.commit -cnotmatch '^[0-9a-f]{40}$' -or $data.quality -ne 'stable'){throw "VS Code sen commit estable recoñecido: $product"}
    return [string]$data.commit
}
function Get-DawCodeVersion {
    # A versión do VS Code instalado (1.122.0), de product.json, sen abrir VS Code.
    param([string]$Code)
    $product=Join-Path (Split-Path -Parent (Split-Path -Parent (Find-DawCodeCli $Code))) 'product.json'
    $data=Get-Content -LiteralPath $product -Raw -Encoding UTF8|ConvertFrom-Json
    if([string]$data.version -notmatch '^\d+\.\d+\.\d+$'){throw "VS Code sen versión recoñecida: $product"}
    return [string]$data.version
}
function Get-DawInstalledCodePaths {
    # O VS Code instalado neste equipo: para todos os usuarios e no perfil de cada un.
    $paths=@()
    foreach($root in @($env:ProgramFiles,${env:ProgramFiles(x86)})|Where-Object {$_}){$paths+=Join-Path $root 'Microsoft VS Code\Code.exe'}
    foreach($userProfile in @(Get-CimInstance Win32_UserProfile|Where-Object {-not $_.Special})){
        $paths+=Join-Path $userProfile.LocalPath 'AppData\Local\Programs\Microsoft VS Code\Code.exe'
    }
    @($paths|Where-Object {Test-Path -LiteralPath $_ -PathType Leaf})
}
function Get-DawInstalledCodeCommits {
    $commits=foreach($path in Get-DawInstalledCodePaths){
        try{Get-DawCodeCommit $path}catch{Write-Warning "Non se leu o commit de $path`: $($_.Exception.Message)"}
    }
    @($commits|Sort-Object -Unique)
}
function Get-DawInstalledCodeVersions {
    # As versións de VS Code deste equipo: as extensións do paquete teñen que valer para a máis vella.
    $versions=foreach($path in Get-DawInstalledCodePaths){
        try{Get-DawCodeVersion $path}catch{Write-Warning "Non se leu a versión de $path`: $($_.Exception.Message)"}
    }
    @($versions|Sort-Object -Unique)
}
function Get-DawCodeServerInstallScript {
    # Como ad: extrae o servidor nas rutas que usan Remote - WSL e a CLI de VS Code.
    $text=@'
set -euo pipefail
archive=$(wslpath -u "$1")
commit=$2
[[ $commit =~ ^[0-9a-f]{40}$ ]] || { echo "Commit non válido: $commit" >&2; exit 1; }
for dest in "$HOME/.vscode-server/bin/$commit" "$HOME/.vscode-server/cli/servers/Stable-$commit/server"; do
    [[ ! -x $dest/node ]] || continue
    mkdir -p -- "$(dirname -- "$dest")"
    tmp=$(mktemp -d "$(dirname -- "$dest")/.daw-server-XXXXXX")
    tar -xzf "$archive" -C "$tmp" --strip-components 1
    [[ -x $tmp/node ]] || { rm -rf -- "$tmp"; echo "O arquivo non contén VS Code Server." >&2; exit 1; }
    rm -rf -- "$dest"
    mv -- "$tmp" "$dest"
done
echo "ready $commit"
'@
    Expand-DawScriptTemplate $text
}
function Initialize-DawCodeServer {
    # Prepara o VS Code Server do paquete para o VS Code desta conta. Sen servidor para ese commit
    # devolve Missing: VS Code descargarao de Internet. Con ForContainer copia tamén o arquivo na
    # caché de Windows de Dev Containers, que non usa o servidor de WSL.
    param([string]$Distribution,[string]$Code,[string]$PackageDirectory=(Get-DawPackageDirectory),[switch]$ForContainer)
    $commit=Get-DawCodeCommit $Code
    $manifest=Get-Content -LiteralPath (Join-Path $PackageDirectory 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $server=@(Get-DawPackageCodeServers $manifest|Where-Object {$_.Commit -eq $commit})|Select-Object -First 1
    if(-not $server){return [pscustomobject]@{Commit=$commit;Status='Missing'}}
    $archive=Join-Path $PackageDirectory $server.File
    $verified=$false
    $installed=$true
    try{Invoke-DawNative 'wsl.exe' @('-d',$Distribution,'-u','ad','--exec','test','-x',"/home/ad/.vscode-server/bin/$commit/node")|Out-Null}catch{$installed=$false}
    if(-not $installed){
        if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $server.Sha256.ToUpperInvariant()){throw "SHA256 de VS Code Server non coincide: $($server.File)"}
        $verified=$true
        Invoke-DawNative 'wsl.exe' @('-d',$Distribution,'-u','ad','--exec','bash','-c',(Get-DawCodeServerInstallScript),'daw-code-server',$archive,$commit)|Out-Null
    }
    if($ForContainer){
        $directory=Join-Path $env:TEMP "vsch\serverCache\$commit"
        $target=Join-Path $directory 'vscode-server-linux-x64.tar.gz'
        $current=(Test-Path -LiteralPath $target -PathType Leaf) -and (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -eq $server.Sha256.ToUpperInvariant()
        if(-not $current){
            if(-not $verified -and (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $server.Sha256.ToUpperInvariant()){throw "SHA256 de VS Code Server non coincide: $($server.File)"}
            New-Item -ItemType Directory -Path $directory -Force|Out-Null
            $pending=$target+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
            try{
                Copy-Item -LiteralPath $archive -Destination $pending
                if((Get-FileHash -LiteralPath $pending -Algorithm SHA256).Hash -ne $server.Sha256.ToUpperInvariant()){throw 'A copia de VS Code Server para Dev Containers non coincide.'}
                if(Test-Path -LiteralPath $target -PathType Leaf){Remove-Item -LiteralPath $target -Force}
                [IO.File]::Move($pending,$target)
            }finally{if(Test-Path -LiteralPath $pending){Remove-Item -LiteralPath $pending -Force}}
        }
    }
    return [pscustomobject]@{Commit=$commit;Status=if($installed){'Ready'}else{'Installed'}}
}
function Update-DawPackage {
    param([string]$Directory,[string]$Source=$PSScriptRoot)
    $path=Join-Path $Directory 'manifest.json'
    $manifest=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
    Assert-DawManifest $manifest
    if((Get-FileHash -LiteralPath (Join-Path $Directory $manifest.Image) -Algorithm SHA256).Hash -ne $manifest.Sha256){throw 'A imaxe non coincide; non se actualizaron scripts.'}
    $sources=@{}
    foreach($name in Get-DawSetupFiles){
        $base=if($name -in @('daw.ps1','install-daw-commands.ps1')){Split-Path -Parent $Source}else{$Source}
        $file=Join-Path $base $name
        if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw "Falta $file"}
        $sources[$name]=$file
    }
    $backup=Join-Path $Directory ('build/setup-backup-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backup -Force|Out-Null
    foreach($name in @('manifest.json')+@(Get-DawSetupFiles)){if(Test-Path -LiteralPath (Join-Path $Directory $name)){Copy-Item -LiteralPath (Join-Path $Directory $name) -Destination $backup}}
    $hashes=[ordered]@{}
    foreach($name in Get-DawSetupFiles){
        $target=Join-Path $Directory $name
        if([IO.Path]::GetFullPath($sources[$name]) -ne [IO.Path]::GetFullPath($target)){Copy-Item -LiteralPath $sources[$name] -Destination $target -Force}
        $hashes[$name]=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    }
    $manifest|Add-Member NoteProperty ScriptSha256 ([pscustomobject]$hashes) -Force
    Write-DawState $path $manifest
    Assert-DawPackage $Directory|Out-Null
}

# Project files staged in Get-DawProjectDirectory and copied into each student's
# Get-DawLinuxProjectPath. The stage carries its own updater and module, so it does not
# depend on the scripts of the model copied earlier.
# Instalación do paquete nun equipo, igual por WinRM (manage.ps1 CopyPackage) ca no propio
# equipo (install-package.ps1): preparar o destino, copiar os ficheiros e completalo.
function Get-DawPackageFiles {
    param($Manifest)
    @('manifest.json')+@(Get-DawSetupFiles)+@($Manifest.Image)+@(Get-DawPackageImages $Manifest|ForEach-Object {$_.File})+@(Get-DawPackageCodeServers $Manifest|ForEach-Object {$_.File})+@(Get-DawPackageCodeExtensions $Manifest|ForEach-Object {$_.File})
}
function Reset-DawPackageFileAcl {
    # Cada ficheiro só herda a ACL protexida do paquete, sen ACL explícitas dunha copia anterior.
    $admins=New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    Get-ChildItem -LiteralPath (Get-DawPackageDirectory) -File|ForEach-Object {
        $acl=New-Object Security.AccessControl.FileSecurity
        $acl.SetAccessRuleProtection($false,$false)
        $acl.SetOwner($admins)
        Set-Acl -LiteralPath $_.FullName -AclObject $acl
    }
}
function Initialize-DawPackageDirectory {
    # Como administrador no equipo: sen instalacións en curso nin autoarranque, retira o paquete
    # anterior e deixa o destino protexido. Devolve o que retirou.
    Assert-DawNoInstallRunning
    # Un inicio de sesión non debe lanzar o instalador mentres se substitúe o paquete.
    Set-DawAutoStart
    $removed=@(Remove-DawLegacyPackage)
    $target=Get-DawPackageDirectory
    if(Test-Path -LiteralPath $target){
        $items=@(Get-Item -LiteralPath $target -Force)+@(Get-ChildItem -LiteralPath $target -Recurse -Force)
        if($items|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}){throw 'O destino contén ligazóns ou junctions.'}
    }
    New-Item -ItemType Directory -Path $target -Force|Out-Null
    Set-DawProtectedAcl $target
    Reset-DawPackageFileAcl
    return $removed
}
function Copy-DawPackageFiles {
    # Copia os ficheiros do paquete (a unha ruta local ou \\equipo\c$\...). Un ficheiro co mesmo
    # tamaño e data non se volve copiar (a imaxe ocupa 1,4 GB): Complete-DawPackage comproba
    # despois o SHA256 de todos.
    param([string]$Source,[string]$Destination,[string[]]$Files)
    $copied=@()
    foreach($file in $Files){
        $local=Get-Item -LiteralPath (Join-Path $Source $file)
        $target=Join-Path $Destination $file
        $existing=Get-Item -LiteralPath $target -ErrorAction SilentlyContinue
        if($existing -and $existing.Length -eq $local.Length -and $existing.LastWriteTimeUtc -eq $local.LastWriteTimeUtc){continue}
        Copy-Item -LiteralPath $local.FullName -Destination $target -Force
        $copied+=$file
    }
    return $copied
}
function Complete-DawPackage {
    # Despois da copia: ACL, SHA256 de todos os ficheiros, autoarranque opcional, política de VS Code
    # e o directorio protexido para os ficheiros do proxecto.
    param([switch]$AutoStart)
    Reset-DawPackageFileAcl
    Assert-DawPackage (Get-DawPackageDirectory)|Out-Null
    Set-DawAutoStart -Enabled:$AutoStart
    Set-DawCodeMachinePolicy
    Initialize-DawProjectDirectory
}
function Complete-DawProjectStage {
    # Despois de copiar os ficheiros do proxecto: ACL, SHA256 e a entrada Activar DAW Dev.
    param([string]$Revision)
    Reset-DawProjectAcl
    $stage=Assert-DawProjectOverlay (Get-DawProjectDirectory)
    if($stage.Revision -ne $Revision){throw 'A revisión do proxecto copiado non coincide.'}
    [pscustomobject]@{Revision=$stage.Revision;Shortcut=Set-DawStartMenuShortcut;Activator=Set-DawActivator}
}
function Get-DawProjectDirectory { "$(Get-DawPackageDirectory)\project" }
function Get-DawProjectScripts { @('update-project.ps1','daw-classroom.psm1') }
function Test-DawProjectPath {
    # Ruta relativa con '/' e sen segmentos '.' nin '..'. Nunca no código do alumnado: nin www (o
    # anterior) nin html, agás a configuración de VS Code (html/.vscode e html/.devcontainer).
    param([string]$Path)
    if($Path -cnotmatch '^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$'){return $false}
    if(@($Path -split '/'|Where-Object {$_ -in @('.','..')}).Count){return $false}
    if($Path -match '^www(/|$)'){return $false}
    return ($Path -notmatch '^html(/|$)' -or $Path -cmatch '^html/\.(vscode|devcontainer)/')
}
function Get-DawProjectRevision {
    param([object[]]$Files)
    $text=(@($Files|ForEach-Object {'{0} {1} {2}' -f $_.Path,$_.Sha256.ToUpperInvariant(),$_.Mode}) -join "`n")
    $sha=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','')}finally{$sha.Dispose()}
}
function New-DawProjectStage {
    # On the teacher's computer: copy windows/classroom/overlay, the shared repository files and the updater, with SHA256 manifest.
    param([string]$Source,[string]$Destination)
    $files=Join-Path $Source 'overlay'
    if(-not(Test-Path -LiteralPath $files -PathType Container)){throw "Falta $files"}
    if(Test-Path -LiteralPath $Destination){throw "O destino xa existe: $Destination"}
    New-Item -ItemType Directory -Path $Destination|Out-Null
    $root=(Get-Item -LiteralPath $files).FullName.TrimEnd('\','/')
    $entries=@()
    $sources=@{}
    foreach($file in @(Get-ChildItem -LiteralPath $files -Recurse -Force)){
        if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Ligazón no proxecto: $($file.FullName)"}
        if($file.PSIsContainer){continue}
        $sources.Add($file.FullName.Substring($root.Length+1).Replace('\','/'),$file)
    }
    $repo=Split-Path -Parent (Split-Path -Parent ([IO.Path]::GetFullPath($Source)))
    # Ruta na copia = ruta no repositorio. Os axustes de VS Code do repositorio van á
    # configuración do espazo de traballo da aula, ~/html/.vscode.
    $sharedPaths=[ordered]@{}
    foreach($relative in @(
        '.gitignore','Dockerfile','README.md',
        'docs/guia-inicio-alumnado.md','docs/guia-inicio-alumnado.pdf',
        'docs/guia-angular-alumnado.md','docs/guia-angular-alumnado.pdf',
        'docs/wsl2-alumnado.md','docs/vscode-perfis.md','docs/windows11-contedores.md',
        'scripts/daw.sh','scripts/daw_helpers.py','scripts/check.sh','scripts/keep-alive.sh','scripts/setup-angular.sh',
        'compose.yaml','docker/mariadb/healthcheck.sh',
        'docker/angular/.dockerignore','docker/angular/Dockerfile','docker/angular/entrypoint.sh'
    )){$sharedPaths[$relative]=$relative}
    $sharedPaths['html/.vscode/settings.json']='.vscode/settings.json'
    foreach($relative in $sharedPaths.Keys){
        $file=Get-Item -LiteralPath (Join-Path $repo $sharedPaths[$relative]) -Force
        if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Ficheiro non válido: $relative"}
        $sources.Add($relative,$file)
    }
    foreach($relative in @($sources.Keys|Sort-Object)){
        $file=$sources[$relative]
        if(-not(Test-DawProjectPath $relative)){throw "Ruta non permitida no proxecto: $relative"}
        $target=Join-Path (Join-Path $Destination 'files') ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        # Data folders only receive new files; the student's own files are never replaced.
        $mode=if($relative -match '^(data|angular)/'){'CreateOnly'}else{'Replace'}
        $entries+=[pscustomobject]@{Path=$relative;Sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash;Mode=$mode}
    }
    if(-not $entries.Count){throw 'O proxecto non ten ficheiros que copiar.'}
    $scripts=[ordered]@{}
    foreach($name in Get-DawProjectScripts){
        $target=Join-Path $Destination $name
        Copy-Item -LiteralPath (Join-Path $Source $name) -Destination $target
        $scripts[$name]=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    }
    Write-DawState (Join-Path $Destination 'project.json') ([ordered]@{Schema=2;Marker=(Get-DawModelMarker).Value;Revision=(Get-DawProjectRevision $entries);CreatedUtc=[DateTime]::UtcNow.ToString('o');Files=$entries;ScriptSha256=[pscustomobject]$scripts})
    Assert-DawProjectOverlay $Destination
}
function Assert-DawProjectOverlay {
    param([string]$Directory)
    $manifest=Get-Content -LiteralPath (Join-Path $Directory 'project.json') -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($name in @('Schema','Marker','Revision','Files','ScriptSha256')){if(-not $manifest.PSObject.Properties[$name]){throw 'Manifesto do proxecto non recoñecido.'}}
    if($manifest.Schema -ne 2 -or $manifest.Marker -cne (Get-DawModelMarker).Value -or $manifest.Revision -notmatch '^[a-fA-F0-9]{64}$'){throw 'Manifesto do proxecto non recoñecido.'}
    $files=@($manifest.Files)
    if(-not $files.Count){throw 'O manifesto do proxecto non ten ficheiros.'}
    $seen=@{}
    foreach($entry in $files){
        if(-not(Test-DawProjectPath ([string]$entry.Path)) -or $entry.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or $entry.Mode -cnotin @('Replace','CreateOnly')){throw "Entrada do proxecto non válida: $($entry.Path)"}
        if($seen.ContainsKey($entry.Path)){throw "Entrada repetida no proxecto: $($entry.Path)"}
        $seen[$entry.Path]=$true
        $path=Join-Path (Join-Path $Directory 'files') (([string]$entry.Path).Replace('/',[IO.Path]::DirectorySeparatorChar))
        if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.Sha256.ToUpperInvariant()){throw "SHA256 do proxecto non coincide: $($entry.Path)"}
    }
    if((Get-DawProjectRevision $files) -ne $manifest.Revision.ToUpperInvariant()){throw 'A revisión do proxecto non coincide co manifesto.'}
    foreach($name in Get-DawProjectScripts){
        $property=$manifest.ScriptSha256.PSObject.Properties[$name]
        $path=Join-Path $Directory $name
        if(-not $property -or $property.Value -notmatch '^[a-fA-F0-9]{64}$' -or -not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $property.Value.ToUpperInvariant()){throw "SHA256 do script non coincide: $name"}
    }
    return $manifest
}
function Assert-DawNoInstallRunning {
    # An installer or updater holding its lock would read a half-replaced package or stage.
    $legacy=Get-DawLegacyInstall
    foreach($userProfile in @(Get-CimInstance Win32_UserProfile|Where-Object {-not $_.Special})){
        $locks=@((Join-Path (Get-DawStateDirectory $userProfile.LocalPath) (Get-DawStateFiles).Lock),(Join-Path (Join-Path $userProfile.LocalPath $legacy.StateRelativePath) $legacy.Lock))
        foreach($lockPath in $locks){
            if(-not(Test-Path -LiteralPath $lockPath)){continue}
            try{$handle=[IO.File]::Open($lockPath,'Open','ReadWrite','None');$handle.Dispose()}
            catch{throw ("Bloqueo de instalación non dispoñible ({0}): {1}. Revisar antes de copiar." -f $lockPath,$_.Exception.Message)}
        }
    }
}
function Initialize-DawProjectDirectory {
    # Remote admin session: an empty stage that only SYSTEM and Administrators can write.
    $parent=Get-DawPackageDirectory
    $target=Get-DawProjectDirectory
    if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw "Falta $parent`: copiar antes o modelo."}
    $items=@(Get-Item -LiteralPath $parent -Force)
    if(Test-Path -LiteralPath $target){$items+=@(Get-Item -LiteralPath $target -Force)+@(Get-ChildItem -LiteralPath $target -Recurse -Force)}
    if($items|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}){throw 'O destino contén ligazóns ou junctions.'}
    Assert-DawNoInstallRunning
    if(Test-Path -LiteralPath $target){
        # Only a previous stage of ours (or an empty directory) is replaced.
        if(@(Get-ChildItem -LiteralPath $target -Force).Count -and -not(Test-Path -LiteralPath (Join-Path $target 'project.json') -PathType Leaf)){throw "$target contén ficheiros alleos; conservouse."}
        Remove-Item -LiteralPath $target -Recurse -Force
    }
    New-Item -ItemType Directory -Path $target|Out-Null
    $acl=New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    $admins=New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $acl.SetOwner($admins)
    foreach($sid in 'S-1-5-18','S-1-5-32-544','S-1-5-32-545'){
        $rights=if($sid -eq 'S-1-5-32-545'){'ReadAndExecute'}else{'FullControl'}
        $identity=New-Object Security.Principal.SecurityIdentifier($sid)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($identity,$rights,'ContainerInherit,ObjectInherit','None','Allow')))
    }
    Set-Acl -LiteralPath $target -AclObject $acl
}
function Reset-DawProjectAcl {
    # After the SMB copy: every item only inherits the protected ACL of the stage.
    $admins=New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    foreach($item in @(Get-ChildItem -LiteralPath (Get-DawProjectDirectory) -Recurse -Force)){
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'O destino contén ligazóns ou junctions.'}
        $acl=if($item.PSIsContainer){New-Object Security.AccessControl.DirectorySecurity}else{New-Object Security.AccessControl.FileSecurity}
        $acl.SetAccessRuleProtection($false,$false)
        $acl.SetOwner($admins)
        Set-Acl -LiteralPath $item.FullName -AclObject $acl
    }
}
function Invoke-DawProjectUpdate {
    param([int]$TimeoutSeconds=1800,[switch]$Restart)
    $target=Get-DawProjectDirectory
    Assert-DawProjectOverlay $target|Out-Null
    $arguments="-PackageDirectory '$target'"
    if($Restart){$arguments+=' -Restart'}
    Invoke-DawUserTask 'UpdateProject' "$target\update-project.ps1" $arguments (Get-DawStateFiles).Project 'Actualización do proxecto' $TimeoutSeconds
}
function Get-DawProjectOverlayScript {
    # Runs as ad. Arguments: source directory, optional image archive and SHA256, and file triples.
    # Everything is validated before the first change; nothing is deleted and the student's web
    # code is never touched. Paths under html/ (only .vscode and .devcontainer), data/ and
    # angular/ go to the home, next to the project (~/.daw); the rest, to the project.
    $text=@'
set -euo pipefail
fail() { echo "$1" >&2; exit 1; }
[[ $# -ge 6 && $((($# - 3) % 3)) -eq 0 ]] || fail 'Lista de ficheiros do proxecto incorrecta.'
if [[ $1 == /* ]]; then src=$1; else src=$(wslpath -u "$1"); fi
archive=$2 archive_sha=$3
shift 3
project=$PWD
home=${project%/*}
distro=${WSL_DISTRO_NAME:-linux}
[[ $distro =~ ^[A-Za-z0-9._-]+$ ]] || fail 'Nome da distribución WSL non válido.'
[[ -f $project/compose.yaml && ! -L $project/compose.yaml ]] || fail 'Falta o proxecto esperado.'
[[ -d $src && ! -L $src ]] || fail 'Falta o directorio dos ficheiros do proxecto.'
digest() { sha256sum < "$1" | cut -d' ' -f1; }
# O que é do alumnado vai no home, ao lado da contorna.
base() { case $1 in html/*|data/*|angular/*) echo "$home" ;; *) echo "$project" ;; esac; }
args=("$@")
compose=$project/compose.yaml
override=
for ((i = 0; i < ${#args[@]}; i += 3)); do
    rel=${args[i]} sha=${args[i+1]} mode=${args[i+2]}
    [[ $rel =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] || fail "Ruta non válida: $rel"
    [[ /$rel/ != */./* && /$rel/ != */../* ]] || fail "Ruta non válida: $rel"
    lower=${rel,,}
    [[ $lower != www && $lower != www/* ]] || fail "Non se cambia www: $rel"
    case $lower in
        html/.vscode/*|html/.devcontainer/*) ;;
        html|html/*) fail "Non se cambia o código web: $rel" ;;
    esac
    [[ $sha =~ ^[0-9a-f]{64}$ ]] || fail "SHA256 non válido: $rel"
    [[ $mode == Replace || $mode == CreateOnly ]] || fail "Modo non válido: $rel"
    [[ -f $src/$rel && ! -L $src/$rel ]] || fail "Falta no paquete: $rel"
    [[ $(digest "$src/$rel") == "$sha" ]] || fail "SHA256 non coincide: $rel"
    IFS=/ read -ra parts <<< "$rel"
    path=$(base "$rel")
    for ((j = 0; j < ${#parts[@]}; j++)); do
        path=$path/${parts[j]}
        [[ ! -L $path ]] || fail "O destino contén unha ligazón: $rel"
        if ((j < ${#parts[@]} - 1)); then
            [[ ! -e $path || -d $path ]] || fail "O destino non é un directorio: $rel"
        else
            [[ ! -e $path || -f $path ]] || fail "O destino non é un ficheiro: $rel"
        fi
    done
    [[ $rel != compose.yaml ]] || compose=$src/$rel
    [[ $rel != compose.override.yaml ]] || override=$src/$rel
done
backup=.daw-backup/$(date +%Y%m%d-%H%M%S)-$$
tmp=
trap '[[ -z $tmp ]] || rm -f -- "$tmp"' EXIT
compose_args=(--project-directory "$project" -f "$compose")
if [[ -n $override ]]; then
    compose_args+=(-f "$override")
fi
images=$(docker compose "${compose_args[@]}" config --images) \
    || fail 'Compose non acepta os ficheiros novos; non se cambiou nada.'
web_image=__DAW_WEB_IMAGE__
previous_image=__DAW_PREVIOUS_WEB_IMAGE__
if grep -Fxq "$web_image" <<< "$images"; then
    for ((i=0; i<60; i++)); do docker info >/dev/null 2>&1 && break; sleep 1; done
    docker info >/dev/null 2>&1 || fail 'Docker non responde.'
    # Un modelo anterior ao 27-11-2026 trae a imaxe co nome anterior: sen Internet, renoméase.
    if ! docker image inspect "$web_image" >/dev/null 2>&1 && docker image inspect "$previous_image" >/dev/null 2>&1; then
        docker image tag "$previous_image" "$web_image" || fail 'Non se puido renomear a imaxe PHP anterior.'
    fi
    if ! docker image inspect "$web_image" >/dev/null 2>&1; then
        if [[ $archive != - ]]; then
            [[ $archive == /* ]] || archive=$(wslpath -u "$archive")
            [[ -f $archive && ! -L $archive && $(digest "$archive") == "$archive_sha" ]] \
                || fail 'O SHA256 do arquivo Docker de PHP non coincide.'
            docker image load --input "$archive" >&2 || fail 'Non se puido cargar a imaxe de PHP.'
        else
            docker image pull "$web_image" >&2 \
                || fail 'Falta a imaxe de PHP 8.6 coa conta ad. Engádea ao paquete da aula con add-package-image.ps1.'
        fi
        docker image inspect "$web_image" >/dev/null || fail "Falta a etiqueta $web_image na imaxe cargada."
    fi
    docker run --rm --pull never --network none --user ad --entrypoint sh "$web_image" -ec \
        'test "$HOME" = /home/ad && ! id dev >/dev/null 2>&1 && test ! -e /home/dev && test ! -L /home/dev' \
        || fail 'A imaxe PHP non ten a conta ad limpa. Non se cambiou o proxecto.'
fi
for ((i = 0; i < ${#args[@]}; i += 3)); do
    rel=${args[i]} sha=${args[i+1]} mode=${args[i+2]}
    dest=$(base "$rel")/$rel
    permissions=0644
    case $rel in
        .vscode/settings.json|html/.vscode/settings.json)
            replacement="s/\"Debian\"/\"$distro\"/g"
            sha=$(sed "$replacement" "$src/$rel" | sha256sum | cut -d' ' -f1)
            ;;
        scripts/daw.sh|scripts/daw_helpers.py|scripts/check.sh|scripts/keep-alive.sh|scripts/setup-angular.sh) permissions=0755 ;;
    esac
    action=creado
    if [[ -f $dest ]]; then
        if [[ $(digest "$dest") == "$sha" ]] && { [[ $permissions != 0755 ]] || [[ -x $dest ]]; }; then
            echo "igual $rel"; continue
        fi
        if [[ $mode == CreateOnly ]]; then echo "conservado $rel"; continue; fi
        mkdir -p -- "$backup/$(dirname -- "$rel")"
        cp -p -- "$dest" "$backup/$rel"
        action=substituido
    fi
    mkdir -p -- "$(dirname -- "$dest")"
    tmp=$(mktemp "$(dirname -- "$dest")/.daw-project-XXXXXX")
    if [[ $rel == .vscode/settings.json || $rel == html/.vscode/settings.json ]]; then
        sed "$replacement" "$src/$rel" > "$tmp"
    else
        cp -- "$src/$rel" "$tmp"
    fi
    chmod "$permissions" -- "$tmp"
    [[ $(digest "$tmp") == "$sha" ]] || fail "A copia non coincide: $rel"
    mv -f -- "$tmp" "$dest"
    tmp=
    echo "$action $rel"
done
[[ ! -d $backup ]] || echo "copia $project/$backup"
docker compose config --quiet || fail "Compose non acepta o proxecto actualizado. Ficheiros substituídos en $project/$backup"
'@
    Expand-DawScriptTemplate $text
}
function Invoke-DawProjectOverlay {
    param([string]$Distribution,[string]$Directory,$Manifest)
    $arguments=@('-d',$Distribution,'-u','ad','--cd',(Get-DawLinuxProjectPath),'--exec','bash','-c',(Get-DawProjectOverlayScript),'daw-project',[IO.Path]::Combine($Directory,'files'))
    $package=Split-Path -Parent ([IO.Path]::GetFullPath($Directory))
    $packageManifest=Join-Path $package 'manifest.json'
    $image=$null
    if(Test-Path -LiteralPath $packageManifest -PathType Leaf){
        $packageData=Get-Content -LiteralPath $packageManifest -Raw -Encoding UTF8|ConvertFrom-Json
        $image=Get-DawPackageImages $packageData|Where-Object {$_.Name -eq (Get-DawWebImage)}|Select-Object -First 1
    }
    if($image){$arguments+=@((Join-Path $package $image.File),$image.Sha256.ToLowerInvariant())}
    else{$arguments+=@('-','-')}
    $files=@($Manifest.Files)
    foreach($entry in $files){$arguments+=@([string]$entry.Path,$entry.Sha256.ToLowerInvariant(),[string]$entry.Mode)}
    $result=[ordered]@{Created=@();Replaced=@();Unchanged=@();Kept=@();Backup=$null}
    foreach($line in @(Invoke-DawNative 'wsl.exe' $arguments)){
        switch -Regex ($line.Trim()){
            '^creado (.+)$' {$result.Created+=$matches[1]}
            '^substituido (.+)$' {$result.Replaced+=$matches[1]}
            '^igual (.+)$' {$result.Unchanged+=$matches[1]}
            '^conservado (.+)$' {$result.Kept+=$matches[1]}
            '^copia (.+)$' {$result.Backup=$matches[1]}
        }
    }
    $reported=@($result.Created)+@($result.Replaced)+@($result.Unchanged)+@($result.Kept)
    if($reported.Count -ne $files.Count -or @($files|Where-Object {$_.Path -notin $reported}).Count){throw 'A copia non informou de todos os ficheiros do proxecto.'}
    [pscustomobject]$result
}
function Restart-DawProjectWeb {
    # Recrea o backend se está en marcha, aínda que só cambiase un ficheiro montado (docker/*):
    # Docker monta os ficheiros polo seu inodo. Unha sesión de Dev Containers hai que reabrila.
    # scripts/daw.sh, xa copiado na nova versión, retira tamén os contedores dos servizos
    # anteriores ao 27-11-2026 e recrea o backend se estaba en marcha o web anterior.
    param([string]$Distribution)
    $lines=@(Invoke-DawNative 'wsl.exe' @('-d',$Distribution,'-u','ad','--cd',(Get-DawLinuxProjectPath),'--exec','bash','scripts/daw.sh','restart-backend'))
    return (@($lines|ForEach-Object {([string]$_).Trim()}) -contains 'restarted')
}

Export-ModuleMember -Function *-Daw*
