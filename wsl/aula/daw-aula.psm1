#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-DawArgument {
    param([AllowEmptyString()][string]$Value)
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
function Install-DawCodeExtensions {
    $code=Find-DawCode
    $cli=Join-Path (Split-Path $code) 'resources\app\out\cli.js'
    if(-not(Test-Path -LiteralPath $cli)){throw 'Falta a CLI de VS Code.'}
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
    if($State.RequestId -ne $RequestId -or $State.UserSid -ne $UserSid){return $false}
    return $State.Phase -eq 'Completed'
}
function Invoke-DawStudentInstall {
    param([int]$TimeoutSeconds=1800,[switch]$AdoptExisting,[switch]$WithoutCode)
    $user=Get-DawStudent
    $id=[guid]::NewGuid().ToString('N')
    $task='DAW-InstalarUsuario-'+$id
    $target='C:\ProgramData\DAW-Aula'
    $status=Join-Path $user.Profile 'AppData\Local\DAW-Aula\estado.json'
    if(-not(Test-Path -LiteralPath "$target\daw-aula.psm1")){throw 'Paquete antigo: actualizar os scripts de aula antes de instalar.'}
    $command="& '$target\instalar-alumno.ps1' -PackageDirectory '$target' -RequestId '$id' -ExpectedUserSid '$($user.SID)'"
    if($AdoptExisting){$command+=' -AdoptarExistente'}
    if($WithoutCode){$command+=' -SenVSCode'}
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $registered=$false
    try{
        $principal=New-ScheduledTaskPrincipal -UserId $user.SID -LogonType Interactive -RunLevel Limited
        $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $action=New-ScheduledTaskAction -Execute $ps -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encoded"
        $settings=New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit (New-TimeSpan -Seconds $TimeoutSeconds) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $task -Principal $principal -Action $action -Settings $settings|Out-Null
        $registered=$true
        $started=Get-Date
        Start-ScheduledTask -TaskName $task
        $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        do{
            if(Test-Path -LiteralPath $status){
                $state=Get-Content -LiteralPath $status -Raw -Encoding UTF8|ConvertFrom-Json
                if(Test-DawRequestState $state $id $user.SID){
                    if(-not $state.Success){throw "Instalación $id fallou: $($state.Error)"}
                    return $state
                }
            }
            $info=Get-ScheduledTaskInfo -TaskName $task
            $current=Get-ScheduledTask -TaskName $task
            if($current.State -ne 'Running' -and $info.LastRunTime -ge $started.AddSeconds(-2) -and $info.LastTaskResult -ne 0){throw "A tarefa $task fallou: $($info.LastTaskResult). Revisar políticas e logs."}
            Start-Sleep -Milliseconds 500
        }while([DateTime]::UtcNow -lt $deadline)
        throw "Tempo esgotado na instalación $id. Revisar estado.json/log; non repetir ata comprobar a operación incompleta."
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
function Get-DawSetupFiles { @('daw.ps1','install-daw-commands.ps1','instalar-alumno.ps1','iniciar-usuario.ps1','daw-aula.psm1') }
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
    return $manifest
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

Export-ModuleMember -Function *-Daw*
