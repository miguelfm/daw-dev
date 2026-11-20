#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
function Assert-DawOrigin {
    param([string]$Distribution,[string]$Marker,[string]$ExpectedSHA,[string]$OriginPath,[bool]$ImportedNow,[switch]$AdoptExisting)
    # Read as root: this works with both old alumno and migrated ad models, without modifying either.
    $actual=(Invoke-DawNative 'wsl.exe' @('-d',$Distribution,'-u','root','--exec','cat','/etc/daw-aula-modelo')) -join ''
    if($actual.Trim() -ne $Marker){throw 'A distribución non é un modelo DAW recoñecido. Conservouse sen modificar.'}
    if(Test-Path -LiteralPath $OriginPath){
        $old=(Get-Content -LiteralPath $OriginPath -Raw -Encoding UTF8).Trim()
        if($old -ne $ExpectedSHA){throw 'Esta distribución procede doutro modelo. Conservouse sen modificar.'}
    }elseif(-not $ImportedNow -and -not $AdoptExisting){
        throw 'Distribución existente sen rexistro de orixe. Revisala e usar AdoptarExistente expresamente; conservouse sen modificar.'
    }
}
function Get-DawMigration {
    # Only run after marker AND origin validation. No pkill, terminate, unregister or recursive chown.
    $text=@'
set -euo pipefail
old=no
if id alumno >/dev/null 2>&1; then
    old=yes
    ! id ad >/dev/null 2>&1 || { echo 'Existen alumno e ad; revisar sen modificar.' >&2; exit 1; }
    ! pgrep -u alumno >/dev/null || { echo 'O usuario alumno ten procesos activos. Gardar traballos e pechalos antes de migrar.' >&2; exit 1; }
    [[ ! -e /home/ad && ! -L /home/ad ]] || { echo '/home/ad xa existe; conservouse.' >&2; exit 1; }
    ! getent group ad >/dev/null || { echo 'O grupo ad xa existe; revisar.' >&2; exit 1; }
    home=/home/alumno
else
    id ad >/dev/null
    home=/home/ad
fi
[[ $(id -u "$( [[ $old == yes ]] && echo alumno || echo ad )") == 1000 ]] || { echo 'UID non recoñecido.' >&2; exit 1; }
account=$( [[ $old == yes ]] && echo alumno || echo ad )
[[ -d "$home" && ! -L "$home" && $(getent passwd "$account" | cut -d: -f6) == "$home" ]] || { echo 'Home do usuario non recoñecido; conservouse.' >&2; exit 1; }
if [[ $old == yes ]] && getent group alumno >/dev/null; then
    [[ $(getent group alumno | cut -d: -f3) == $(id -g alumno) ]] || { echo 'Grupo alumno non recoñecido.' >&2; exit 1; }
fi
[[ -f "$home/proxectos/daw-dev/compose.yaml" ]] || { echo 'Falta o proxecto esperado.' >&2; exit 1; }
if [[ -e "$home/www" || -L "$home/www" ]]; then
    [[ -L "$home/www" && $(readlink "$home/www") == /home/ad/proxectos/daw-dev/www ]] || { echo 'www contén datos ou outra ligazón; conservouse.' >&2; exit 1; }
fi
if [[ $old == no && ( -e /home/alumno || -L /home/alumno ) ]]; then
    [[ -L /home/alumno && $(readlink /home/alumno) == /home/ad ]] || { echo '/home/alumno contén datos alleos; conservouse.' >&2; exit 1; }
fi
[[ -f /etc/wsl.conf && ! -L /etc/wsl.conf ]] || { echo 'Falta wsl.conf do modelo; conservouse.' >&2; exit 1; }
if [[ -f /etc/wsl.conf ]]; then
    sections=$(grep -cE '^[[:space:]]*\[user\][[:space:]]*([#;].*)?$' /etc/wsl.conf || true)
    [[ $sections -le 1 ]] || { echo 'wsl.conf ten varias seccións user; conservouse.' >&2; exit 1; }
fi
if [[ $old == yes ]]; then
    usermod -l ad -d /home/ad -m alumno
fi
if getent group alumno >/dev/null && ! getent group ad >/dev/null; then
    [[ $(getent group alumno | cut -d: -f3) == $(id -g ad) ]] || { echo 'Grupo alumno non recoñecido.' >&2; exit 1; }
    groupmod -n ad alumno
fi
[[ -L /home/alumno ]] || ln -s /home/ad /home/alumno
[[ -L /home/ad/www ]] || ln -s /home/ad/proxectos/daw-dev/www /home/ad/www
# Preserve every other section/key/comment; change only [user].default.
temp=$(mktemp /etc/.wsl.conf.daw-XXXXXX)
trap 'rm -f "$temp"' EXIT
awk '
BEGIN { inside=0; seen=0; written=0 }
/^[[:space:]]*\[/ {
    if (inside && !written) { print "default=ad"; written=1 }
    inside=($0 ~ /^[[:space:]]*\[user\][[:space:]]*([#;].*)?$/)
    if (inside) seen=1
    print; next
}
inside && /^[[:space:]]*default[[:space:]]*=/ { if (!written) print "default=ad"; written=1; next }
{ print }
END { if (inside && !written) print "default=ad"; if (!seen) print "\n[user]\ndefault=ad" }
' /etc/wsl.conf > "$temp"
if ! cmp -s "$temp" /etc/wsl.conf; then
    cp -p /etc/wsl.conf "/etc/wsl.conf.daw-backup-$(date +%Y%m%d%H%M%S)-$$"
    chmod --reference=/etc/wsl.conf "$temp"
    mv "$temp" /etc/wsl.conf
fi
'@
    $text.Replace("`r",'')
}
function Set-DawAutoStart {
    param([switch]$Enabled)
    $path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    $property=Get-ItemProperty -LiteralPath $path -Name DAWAula -ErrorAction SilentlyContinue
    $existing=if($property){$property.DAWAula}else{$null}
    if($existing -and $existing -notmatch '^powershell\.exe .* -EncodedCommand [A-Za-z0-9+/=]+$'){throw 'DAWAula ten unha orde allea; conservouse para revisión.'}
    if($existing){
        $encoded=($existing -split ' ')[-1]
        $decoded=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
        if($decoded -ne "& 'C:\ProgramData\DAW-Aula\iniciar-usuario.ps1'"){throw 'DAWAula apunta a outro programa; conservouse.'}
    }
    if($Enabled){
        $command="& 'C:\ProgramData\DAW-Aula\iniciar-usuario.ps1'"
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        New-ItemProperty -Path $path -Name DAWAula -Value "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encoded" -PropertyType String -Force|Out-Null
    }elseif($existing){Remove-ItemProperty -LiteralPath $path -Name DAWAula -ErrorAction Stop}
}
function Find-DawCode {
    foreach($path in @((Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'),(Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\Code.exe'))){
        if(Test-Path -LiteralPath $path){return $path}
    }
    throw 'Falta VS Code. Instalalo para este usuario ou indicar SenVSCode para unha instalación explicitamente sen IDE.'
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
function Install-DawCodeExtensions {
    $code=Find-DawCode
    $cli=Find-DawCodeCli $code
    $old=$env:ELECTRON_RUN_AS_NODE
    try{
        $env:ELECTRON_RUN_AS_NODE='1'
        $required=@('ms-vscode-remote.remote-containers','ms-vscode-remote.remote-wsl')
        $installed=@(Invoke-DawNative $code @($cli,'--list-extensions'))
        foreach($id in $required){if($id -notin $installed){Invoke-DawNative $code @($cli,'--install-extension',$id)|Out-Null}}
        $installed=@(Invoke-DawNative $code @($cli,'--list-extensions'))
        foreach($id in $required){if($id -notin $installed){throw "Extensión non confirmada: $id"}}
        return $required
    }finally{$env:ELECTRON_RUN_AS_NODE=$old}
}
function New-DawShortcut {
    param([string]$Distribution)
    $desktop=[Environment]::GetFolderPath('Desktop')
    if(-not $desktop -or -not(Test-Path -LiteralPath $desktop)){throw 'Non se atopou o Escritorio do alumno.'}
    $path=Join-Path $desktop 'DAW - Proxectos (www).lnk'
    $shell=New-Object -ComObject WScript.Shell
    $link=$shell.CreateShortcut($path)
    $link.TargetPath="\\wsl.localhost\$Distribution\home\ad\www"
    $link.Description='Cartafol de proxectos web DAW Dev'
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
    param([int]$TimeoutSeconds=1800,[switch]$AdoptExisting,[switch]$WithoutCode)
    $target='C:\ProgramData\DAW-Aula'
    if(-not(Test-Path -LiteralPath "$target\daw-aula.psm1")){throw 'Paquete antigo: actualizar os scripts de aula antes de instalar.'}
    $arguments="-PackageDirectory '$target'"
    if($AdoptExisting){$arguments+=' -AdoptarExistente'}
    if($WithoutCode){$arguments+=' -SenVSCode'}
    Invoke-DawUserTask 'InstalarUsuario' "$target\instalar-alumno.ps1" $arguments 'estado.json' 'Instalación' $TimeoutSeconds
}
function Invoke-DawUserTask {
    # Runs a package script as the single connected student and waits for the state of THIS request.
    param([string]$Name,[string]$Script,[string]$Arguments,[string]$StateFile,[string]$Label,[int]$TimeoutSeconds=1800)
    $user=Get-DawStudent
    $id=[guid]::NewGuid().ToString('N')
    $task="DAW-$Name-$id"
    $status=Join-Path $user.Profile ('AppData\Local\DAW-Aula\'+$StateFile)
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
function Get-DawSetupFiles { @('daw.ps1','install-daw-commands.ps1','instalar-alumno.ps1','iniciar-usuario.ps1','activar-dawdev.ps1','daw-aula.psm1') }
function Set-DawStartMenuShortcut {
    # Activación manual para calquera usuario: unha entrada no menú Inicio común, nada no inicio de sesión.
    param([string]$Directory=(Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\DAW Dev'),[string]$Package='C:\ProgramData\DAW-Aula')
    New-Item -ItemType Directory -Path $Directory -Force|Out-Null
    $path=Join-Path $Directory 'Activar DAW Dev.lnk'
    $shell=New-Object -ComObject WScript.Shell
    $link=$shell.CreateShortcut($path)
    $link.TargetPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $link.Arguments="-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Package 'activar-dawdev.ps1')`""
    $link.WorkingDirectory=$Package
    # Texto sen tiles: o módulo non leva BOM e Windows PowerShell 5.1 leríao como ANSI.
    $link.Description='Activa DAW Dev (WSL e Docker) na conta que o abre'
    $link.Save()
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Non se confirmou a entrada do menú Inicio.'}
    return $path
}
function Assert-DawPackage {
    param([string]$Directory)
    $manifest=Get-Content -LiteralPath (Join-Path $Directory 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($manifest.Schema -ne 1 -or $manifest.Marker -ne 'daw-aula-v1' -or $manifest.Image -notin @('debian-daw.tar','debian-daw.tar.gz') -or $manifest.Sha256 -notmatch '^[0-9a-fA-F]{64}$' -or $manifest.LinuxUser -notin @('alumno','ad')){throw 'Manifesto de modelo non recoñecido.'}
    if(-not $manifest.PSObject.Properties['SetupRevision'] -or $manifest.SetupRevision -ne 2 -or -not $manifest.PSObject.Properties['ScriptSha256']){throw 'Paquete antigo: actualizar os scripts con actualizar-paquete.ps1, conservando a imaxe.'}
    foreach($name in Get-DawSetupFiles){
        $property=$manifest.ScriptSha256.PSObject.Properties[$name]
        if(-not $property -or $property.Value -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath (Join-Path $Directory $name) -Algorithm SHA256).Hash -ne $property.Value){throw "SHA256 do script non coincide: $name"}
    }
    if((Get-FileHash -LiteralPath (Join-Path $Directory $manifest.Image) -Algorithm SHA256).Hash -ne $manifest.Sha256){throw 'O SHA256 da imaxe non coincide.'}
    foreach($extra in @(Get-DawPackageImages $manifest)){
        $path=Join-Path $Directory $extra.File
        if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $extra.Sha256.ToUpperInvariant()){throw "SHA256 da imaxe Docker non coincide: $($extra.File)"}
    }
    foreach($extra in @(Get-DawPackageFiles $manifest)){
        $path=Join-Path $Directory $extra.File
        if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $extra.Sha256.ToUpperInvariant()){throw "SHA256 do VS Code Server non coincide: $($extra.File)"}
    }
    return $manifest
}
function Get-DawPackageImages {
    # Imaxes Docker adicionais do paquete (Angular de DWCC...), que daw.ps1 carga en cada conta.
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
    # daw.ps1 busca a imaxe de Angular co nome fixo dwcc-angular.tar.gz, veña de onde veña.
    if($Name -match '(^|/)dwcc-angular:'){
        if($file -notmatch '\.tar\.gz$'){throw 'A imaxe de Angular vai comprimida: docker save ... | gzip > dwcc-angular.tar.gz'}
        $file='dwcc-angular.tar.gz'
    }
    $target=Join-Path $Directory $file
    if([IO.Path]::GetFullPath($Archive) -ne [IO.Path]::GetFullPath($target)){Copy-Item -LiteralPath $Archive -Destination $target -Force}
    $entry=[pscustomobject]@{File=$file;Name=$Name;Sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash}
    $images=@(Get-DawPackageImages $manifest|Where-Object {$_.File -ne $file -and $_.Name -ne $Name})+$entry
    $manifest|Add-Member NoteProperty Images $images -Force
    Write-DawState (Join-Path $Directory 'manifest.json') $manifest
    Assert-DawPackage $Directory|Out-Null
    return $entry
}
function Get-DawPackageFiles {
    # Outros ficheiros que CopiarModelo leva aos postos: o VS Code Server que daw.ps1 instala
    # en Debian-DAW antes de abrir VS Code (daw-code-angular), sen descargalo en cada conta.
    param($Manifest)
    if(-not $Manifest.PSObject.Properties['Files']){return @()}
    foreach($extra in @($Manifest.Files)){
        if([string]$extra.File -cnotmatch '^vscode-server-linux-(x64|arm64)\.tar\.gz$' -or [string]$extra.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or [string]$extra.Commit -cnotmatch '^[0-9a-f]{40}$'){throw 'Ficheiro do manifesto non recoñecido.'}
        $extra
    }
}
function Get-DawCodeServerInfo {
    # Arquitectura e commit dun paquete do VS Code Server, lidos do seu product.json.
    param([string]$Archive)
    if(-not(Test-Path -LiteralPath $Archive -PathType Leaf)){throw "Non existe $Archive"}
    $tar=Get-Command tar -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1
    if(-not $tar){throw 'Falta tar para ler o paquete do VS Code Server.'}
    foreach($arch in 'x64','arm64'){
        try{$text=(Invoke-DawNative $tar.Source @('-xzOf',$Archive,"vscode-server-linux-$arch/product.json")) -join "`n"}catch{continue}
        $m=[regex]::Match($text,'"commit"\s*:\s*"([0-9a-f]{40})"')
        if($m.Success){return [pscustomobject]@{Arch=$arch;Commit=$m.Groups[1].Value}}
    }
    throw 'O ficheiro non é un paquete do VS Code Server para Linux.'
}
function Add-DawPackageFile {
    # No profesor: copia o VS Code Server ao paquete co nome que busca daw.ps1, o seu commit e o SHA256.
    param([string]$Directory,[string]$Archive,[string]$ExpectedCommit)
    $manifest=Assert-DawPackage $Directory
    $info=Get-DawCodeServerInfo $Archive
    if($ExpectedCommit -and $info.Commit -ne $ExpectedCommit.ToLowerInvariant()){throw "O paquete é do commit $($info.Commit), non de $ExpectedCommit."}
    $file="vscode-server-linux-$($info.Arch).tar.gz"
    $target=Join-Path $Directory $file
    if([IO.Path]::GetFullPath($Archive) -ne [IO.Path]::GetFullPath($target)){Copy-Item -LiteralPath $Archive -Destination $target -Force}
    $entry=[pscustomobject]@{File=$file;Commit=$info.Commit;Sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash}
    $files=@(Get-DawPackageFiles $manifest|Where-Object {$_.File -ne $file})+$entry
    $manifest|Add-Member NoteProperty Files $files -Force
    Write-DawState (Join-Path $Directory 'manifest.json') $manifest
    Assert-DawPackage $Directory|Out-Null
    return $entry
}
function Update-DawPackage {
    param([string]$Directory,[string]$Source=$PSScriptRoot)
    $path=Join-Path $Directory 'manifest.json'
    $manifest=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
    if($manifest.Schema -ne 1 -or $manifest.Marker -ne 'daw-aula-v1' -or $manifest.Image -notin @('debian-daw.tar','debian-daw.tar.gz') -or $manifest.Sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Manifesto non recoñecido; non se actualizaron scripts.'}
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
    $manifest|Add-Member NoteProperty SetupRevision 2 -Force
    $manifest|Add-Member NoteProperty ScriptSha256 ([pscustomobject]$hashes) -Force
    Write-DawState $path $manifest
    Assert-DawPackage $Directory|Out-Null
}

# Project files staged in C:\ProgramData\DAW-Aula\proxecto and copied into each student's
# /home/ad/proxectos/daw-dev. The stage carries its own updater and module, so it does not
# depend on the scripts of the model copied earlier.
function Get-DawProjectDirectory { 'C:\ProgramData\DAW-Aula\proxecto' }
function Get-DawProjectScripts { @('actualizar-proxecto.ps1','daw-aula.psm1') }
function Test-DawProjectPath {
    # Relative project path with '/', no '.' or '..' segments, never inside www.
    param([string]$Path)
    if($Path -cnotmatch '^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$'){return $false}
    if(@($Path -split '/'|Where-Object {$_ -in @('.','..')}).Count){return $false}
    return $Path -notmatch '^www(/|$)'
}
function Get-DawProjectRevision {
    param([object[]]$Files)
    $text=(@($Files|ForEach-Object {'{0} {1} {2}' -f $_.Path,$_.Sha256.ToUpperInvariant(),$_.Mode}) -join "`n")
    $sha=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','')}finally{$sha.Dispose()}
}
function New-DawProjectStage {
    # On the teacher's computer: copy wsl/aula/proxecto/ficheiros and the updater, with SHA256 manifest.
    param([string]$Source,[string]$Destination)
    $files=Join-Path $Source 'proxecto\ficheiros'
    if(-not(Test-Path -LiteralPath $files -PathType Container)){throw "Falta $files"}
    if(Test-Path -LiteralPath $Destination){throw "O destino xa existe: $Destination"}
    New-Item -ItemType Directory -Path $Destination|Out-Null
    $root=(Get-Item -LiteralPath $files).FullName.TrimEnd('\','/')
    $entries=@()
    foreach($file in @(Get-ChildItem -LiteralPath $files -Recurse -Force|Sort-Object FullName)){
        if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Ligazón no proxecto: $($file.FullName)"}
        if($file.PSIsContainer){continue}
        $relative=$file.FullName.Substring($root.Length+1).Replace('\','/')
        if(-not(Test-DawProjectPath $relative)){throw "Ruta non permitida no proxecto: $relative"}
        $target=Join-Path (Join-Path $Destination 'ficheiros') ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
        # Data folders only receive new files; the student's own files are never replaced.
        $mode=if($relative -match '^datos/'){'CreateOnly'}else{'Replace'}
        $entries+=[pscustomobject]@{Path=$relative;Sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash;Mode=$mode}
    }
    if(-not $entries.Count){throw 'O proxecto non ten ficheiros que copiar.'}
    $scripts=[ordered]@{}
    foreach($name in Get-DawProjectScripts){
        $target=Join-Path $Destination $name
        Copy-Item -LiteralPath (Join-Path $Source $name) -Destination $target
        $scripts[$name]=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    }
    Write-DawState (Join-Path $Destination 'proxecto.json') ([ordered]@{Schema=1;Marker='daw-aula-v1';Revision=(Get-DawProjectRevision $entries);CreatedUtc=[DateTime]::UtcNow.ToString('o');Files=$entries;ScriptSha256=[pscustomobject]$scripts})
    Assert-DawProjectOverlay $Destination
}
function Assert-DawProjectOverlay {
    param([string]$Directory)
    $manifest=Get-Content -LiteralPath (Join-Path $Directory 'proxecto.json') -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($name in @('Schema','Marker','Revision','Files','ScriptSha256')){if(-not $manifest.PSObject.Properties[$name]){throw 'Manifesto do proxecto non recoñecido.'}}
    if($manifest.Schema -ne 1 -or $manifest.Marker -ne 'daw-aula-v1' -or $manifest.Revision -notmatch '^[a-fA-F0-9]{64}$'){throw 'Manifesto do proxecto non recoñecido.'}
    $files=@($manifest.Files)
    if(-not $files.Count){throw 'O manifesto do proxecto non ten ficheiros.'}
    $seen=@{}
    foreach($entry in $files){
        if(-not(Test-DawProjectPath ([string]$entry.Path)) -or $entry.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or $entry.Mode -cnotin @('Replace','CreateOnly')){throw "Entrada do proxecto non válida: $($entry.Path)"}
        if($seen.ContainsKey($entry.Path)){throw "Entrada repetida no proxecto: $($entry.Path)"}
        $seen[$entry.Path]=$true
        $path=Join-Path (Join-Path $Directory 'ficheiros') (([string]$entry.Path).Replace('/',[IO.Path]::DirectorySeparatorChar))
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
    # An installer or updater holding its lock would read a half-replaced stage.
    foreach($userProfile in @(Get-CimInstance Win32_UserProfile|Where-Object {-not $_.Special})){
        $lockPath=Join-Path $userProfile.LocalPath 'AppData\Local\DAW-Aula\instalacion.lock'
        if(Test-Path -LiteralPath $lockPath){
            try{$handle=[IO.File]::Open($lockPath,'Open','ReadWrite','None');$handle.Dispose()}
            catch{throw ("Bloqueo de instalación non dispoñible ({0}): {1}. Revisar antes de copiar." -f $lockPath,$_.Exception.Message)}
        }
    }
}
function Initialize-DawProjectDirectory {
    # Remote admin session: an empty stage that only SYSTEM and Administrators can write.
    $parent='C:\ProgramData\DAW-Aula'
    $target=Get-DawProjectDirectory
    if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw "Falta $parent`: copiar antes o modelo."}
    $items=@(Get-Item -LiteralPath $parent -Force)
    if(Test-Path -LiteralPath $target){$items+=@(Get-Item -LiteralPath $target -Force)+@(Get-ChildItem -LiteralPath $target -Recurse -Force)}
    if($items|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}){throw 'O destino contén ligazóns ou junctions.'}
    Assert-DawNoInstallRunning
    if(Test-Path -LiteralPath $target){
        # Only a previous stage of ours (or an empty directory) is replaced.
        if(@(Get-ChildItem -LiteralPath $target -Force).Count -and -not(Test-Path -LiteralPath (Join-Path $target 'proxecto.json') -PathType Leaf)){throw "$target contén ficheiros alleos; conservouse."}
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
    if($Restart){$arguments+=' -Reiniciar'}
    Invoke-DawUserTask 'ActualizarProxecto' "$target\actualizar-proxecto.ps1" $arguments 'proxecto-estado.json' 'Actualización do proxecto' $TimeoutSeconds
}
function Get-DawProjectOverlayScript {
    # Runs as ad in the project directory. Arguments: source directory, then path/SHA256/mode triples.
    # Everything is validated before the first change; nothing is deleted and www is never touched.
    $text=@'
set -euo pipefail
fail() { echo "$1" >&2; exit 1; }
[[ $# -ge 4 && $((($# - 1) % 3)) -eq 0 ]] || fail 'Lista de ficheiros do proxecto incorrecta.'
if [[ $1 == /* ]]; then src=$1; else src=$(wslpath -u "$1"); fi
shift
project=$PWD
[[ -f $project/compose.yaml && ! -L $project/compose.yaml ]] || fail 'Falta o proxecto esperado.'
[[ -d $src && ! -L $src ]] || fail 'Falta o directorio dos ficheiros do proxecto.'
digest() { sha256sum < "$1" | cut -d' ' -f1; }
args=("$@")
override=
for ((i = 0; i < ${#args[@]}; i += 3)); do
    rel=${args[i]} sha=${args[i+1]} mode=${args[i+2]}
    [[ $rel =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] || fail "Ruta non válida: $rel"
    [[ /$rel/ != */./* && /$rel/ != */../* ]] || fail "Ruta non válida: $rel"
    lower=${rel,,}
    [[ $lower != www && $lower != www/* ]] || fail "Non se cambia www: $rel"
    [[ $sha =~ ^[0-9a-f]{64}$ ]] || fail "SHA256 non válido: $rel"
    [[ $mode == Replace || $mode == CreateOnly ]] || fail "Modo non válido: $rel"
    [[ -f $src/$rel && ! -L $src/$rel ]] || fail "Falta no paquete: $rel"
    [[ $(digest "$src/$rel") == "$sha" ]] || fail "SHA256 non coincide: $rel"
    IFS=/ read -ra parts <<< "$rel"
    path=$project
    for ((j = 0; j < ${#parts[@]}; j++)); do
        path=$path/${parts[j]}
        [[ ! -L $path ]] || fail "O destino contén unha ligazón: $rel"
        if ((j < ${#parts[@]} - 1)); then
            [[ ! -e $path || -d $path ]] || fail "O destino non é un directorio: $rel"
        else
            [[ ! -e $path || -f $path ]] || fail "O destino non é un ficheiro: $rel"
        fi
    done
    [[ $rel != compose.override.yaml ]] || override=$src/$rel
done
if [[ -n $override ]]; then
    docker compose --project-directory "$project" -f "$project/compose.yaml" -f "$override" config --quiet \
        || fail 'Compose non acepta os ficheiros novos; non se cambiou nada.'
fi
backup=.daw-backup/$(date +%Y%m%d-%H%M%S)-$$
tmp=
trap '[[ -z $tmp ]] || rm -f -- "$tmp"' EXIT
for ((i = 0; i < ${#args[@]}; i += 3)); do
    rel=${args[i]} sha=${args[i+1]} mode=${args[i+2]}
    dest=$project/$rel
    action=creado
    if [[ -f $dest ]]; then
        if [[ $(digest "$dest") == "$sha" ]]; then echo "igual $rel"; continue; fi
        if [[ $mode == CreateOnly ]]; then echo "conservado $rel"; continue; fi
        mkdir -p -- "$backup/$(dirname -- "$rel")"
        cp -p -- "$dest" "$backup/$rel"
        action=substituido
    fi
    mkdir -p -- "$(dirname -- "$dest")"
    tmp=$(mktemp "$(dirname -- "$dest")/.daw-proxecto-XXXXXX")
    cp -- "$src/$rel" "$tmp"
    chmod 0644 -- "$tmp"
    [[ $(digest "$tmp") == "$sha" ]] || fail "A copia non coincide: $rel"
    mv -f -- "$tmp" "$dest"
    tmp=
    echo "$action $rel"
done
[[ ! -d $backup ]] || echo "copia $project/$backup"
docker compose config --quiet || fail "Compose non acepta o proxecto actualizado. Ficheiros substituídos en $project/$backup"
'@
    $text.Replace("`r",'')
}
function Invoke-DawProjectOverlay {
    param([string]$Distribution,[string]$Directory,$Manifest)
    $arguments=@('-d',$Distribution,'-u','ad','--cd','/home/ad/proxectos/daw-dev','--exec','bash','-c',(Get-DawProjectOverlayScript),'daw-proxecto',[IO.Path]::Combine($Directory,'ficheiros'))
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
    # Recreates web only when it is already running; Dev Containers sessions must be reopened.
    param([string]$Distribution)
    $base=@('-d',$Distribution,'-u','ad','--cd','/home/ad/proxectos/daw-dev','--exec')
    Invoke-DawNative 'wsl.exe' ($base+@('bash','-c','for i in {1..60}; do docker info >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'))|Out-Null
    $running=@(Invoke-DawNative 'wsl.exe' ($base+@('docker','compose','ps','--status','running','--services'))|ForEach-Object {$_.Trim()})
    if('web' -notin $running){return $false}
    Invoke-DawNative 'wsl.exe' ($base+@('docker','compose','up','-d','--no-deps','--wait','--wait-timeout','300','web'))|Out-Null
    return $true
}

Export-ModuleMember -Function *-Daw*
