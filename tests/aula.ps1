#requires -Version 5.1
$ErrorActionPreference='Stop'
$script:Repo=Split-Path $PSScriptRoot
$script:ModulePath=Join-Path $script:Repo 'wsl/aula/daw-aula.psm1'
$script:Temp=Join-Path ([IO.Path]::GetTempPath()) ('daw-tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:Temp|Out-Null
$script:Count=0
function Assert($Condition,[string]$Message='Assertion failed'){if(-not $Condition){throw $Message}}
function Throws([scriptblock]$Body,[string]$Pattern='.'){
    $caught=$false
    try{& $Body|Out-Null}catch{$caught=$true;if($_.Exception.Message -notmatch $Pattern){throw "Unexpected: $($_.Exception.Message)"}}
    Assert $caught 'Expected an exception'
}
function Test([string]$Name,[scriptblock]$Body){
    Remove-Module daw-aula -Force -ErrorAction SilentlyContinue
    Import-Module $script:ModulePath -Force
    $script:M=Get-Module daw-aula
    & $Body
    $script:Count++
    Write-Host "PASS $Name"
}
try{
    Test 'PowerShell sources parse' {
        foreach($f in Get-ChildItem (Join-Path $script:Repo 'wsl') -Recurse -Include *.ps1,*.psm1){
            $e=$null;$null=[Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$null,[ref]$e)
            Assert ($e.Count -eq 0) "$($f.Name): $e"
        }
    }
    Test 'native quoted arguments, errors and timeout' {
        $exe=(Get-Process -Id $PID).Path
        $f=Join-Path $script:Temp 'quoted script.ps1';[IO.File]::WriteAllText($f,'param([string]$Value) $Value | ConvertTo-Json -Compress')
        $value='C:\some folder\a"b\'
        $out=Invoke-DawNative $exe @('-NoProfile','-File',$f,'-Value',$value)
        Assert ((($out -join "`n")|ConvertFrom-Json) -eq $value)
        Throws {Invoke-DawNative $exe @('-NoProfile','-Command','exit 9')} 'exit 9'
        Throws {Invoke-DawNative $exe @('-NoProfile','-Command','Start-Sleep 20') 1} 'Tempo esgotado'
    }
    Test 'state writes atomically and can replace previous result' {
        $p=Join-Path $script:Temp 'state.json'
        Write-DawState $p @{Success=$true;User='alumno'}
        Write-DawState $p @{Success=$false;User='ad'}
        $s=Get-Content $p -Raw -Encoding UTF8|ConvertFrom-Json
        Assert (-not $s.Success -and $s.User -eq 'ad')
        Assert (@(Get-ChildItem $script:Temp -Filter 'state.json.*.tmp').Count -eq 0)
    }
    Test 'unrecognized distro rejected with read-only WSL call' {
        & $script:M {
            $script:Calls=@()
            function script:Invoke-DawNative {param($File,$Arguments) $script:Calls+=, $Arguments; 'foreign-model'}
        }
        Throws {Assert-DawOrigin 'Debian-DAW' 'daw-aula-v1' ('a'*64) (Join-Path $script:Temp 'absent') $false} 'non é un modelo'
        $calls=& $script:M {,$script:Calls}
        Assert ($calls.Count -eq 1 -and $calls[0] -contains 'cat' -and $calls[0] -notcontains 'bash')
    }
    Test 'mismatching origin never migrated; missing origin requires explicit adoption' {
        & $script:M {function script:Invoke-DawNative {param($File,$Arguments) 'daw-aula-v1'}}
        $p=Join-Path $script:Temp 'origin.sha';Set-Content $p ('b'*64)
        Throws {Assert-DawOrigin 'Debian-DAW' 'daw-aula-v1' ('a'*64) $p $false} 'doutro modelo'
        Remove-Item $p
        Throws {Assert-DawOrigin 'Debian-DAW' 'daw-aula-v1' ('a'*64) $p $false} 'sen rexistro'
        Assert-DawOrigin 'Debian-DAW' 'daw-aula-v1' ('a'*64) $p $false -AdoptExisting
        Assert-DawOrigin 'Debian-DAW' 'daw-aula-v1' ('a'*64) $p $true
        Assert (-not(Test-Path $p)) 'Validation itself must never mutate the origin'
    }
    Test 'installer validates marker and source BEFORE invoking migration' {
        $p=Join-Path $script:Repo 'wsl/aula/instalar-alumno.ps1'
        $t=[IO.File]::ReadAllText($p)
        Assert ($t.IndexOf('Assert-DawOrigin') -lt $t.IndexOf('(Get-DawMigration)'))
        $bash=Get-DawMigration
        Assert (-not $bash.Contains("`r")) 'Bash must receive LF even from CRLF Windows source'
        Assert ($bash -notmatch 'pkill|chown -R|wsl --terminate|--unregister')
    }
    Test 'default copy does not re-enable autostart; explicit opt-in is separate' {
        & $script:M {
            $script:Old=$null;$script:Actions=@()
            function script:Get-ItemProperty {param($LiteralPath,$Name,$ErrorAction) if($script:Old){[pscustomobject]@{DAWAula=$script:Old}}}
            function script:New-ItemProperty {param($Path,$Name,$Value,$PropertyType,[switch]$Force) $script:Old=$Value;$script:Actions+='created'}
            function script:Remove-ItemProperty {param($LiteralPath,$Name,$ErrorAction) $script:Old=$null;$script:Actions+='removed'}
        }
        Set-DawAutoStart
        Assert ((& $script:M {$script:Actions.Count}) -eq 0)
        Set-DawAutoStart -Enabled
        Assert ((& $script:M {$script:Actions}) -contains 'created')
        Set-DawAutoStart
        Assert ((& $script:M {$script:Actions}) -contains 'removed')
        & $script:M {$script:Old='some other program'}
        Throws {Set-DawAutoStart} 'allea'
    }
    Test 'remote startup block binds its explicit opt-in parameter' {
        $f=Join-Path $script:Repo 'wsl/aula/gestionar-aula.ps1'
        $ast=[Management.Automation.Language.Parser]::ParseFile($f,[ref]$null,[ref]$null)
        $calls=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Set-DawAutoStart' -and $n.Extent.Text -match '-Enabled:'},$true))
        Assert ($calls.Count -eq 1)
        $block=$calls[0].Parent
        while($block -and $block -isnot [Management.Automation.Language.ScriptBlockAst]){$block=$block.Parent}
        Assert ('enableAuto' -in @($block.ParamBlock.Parameters|ForEach-Object {$_.Name.VariablePath.UserPath}))
    }
    Test 'package update preserves image SHA and rejects corrupted script payloads' {
        $source=Join-Path $script:Temp 'src/wsl/aula';$dest=Join-Path $script:Temp 'package'
        New-Item -ItemType Directory -Path $source,$dest -Force|Out-Null
        foreach($name in Get-DawSetupFiles){
            $base=if($name -in @('daw.ps1','install-daw-commands.ps1')){Split-Path -Parent $source}else{$source}
            [IO.File]::WriteAllText((Join-Path $base $name),('payload '+$name))
        }
        $image=Join-Path $dest 'debian-daw.tar.gz';[IO.File]::WriteAllText($image,'model bytes')
        $sha=(Get-FileHash $image -Algorithm SHA256).Hash
        Write-DawState (Join-Path $dest 'manifest.json') @{Schema=1;Marker='daw-aula-v1';LinuxUser='alumno';Image='debian-daw.tar.gz';Sha256=$sha}
        Update-DawPackage $dest $source
        $m=Assert-DawPackage $dest
        Assert ($m.Sha256 -eq $sha -and $m.SetupRevision -eq 2)
        Assert ([IO.File]::ReadAllText($image) -eq 'model bytes')
        Assert (@(Get-ChildItem (Join-Path $dest 'build') -Directory).Count -eq 1)
        [IO.File]::WriteAllText((Join-Path $dest 'instalar-alumno.ps1'),'corrupt')
        Throws {Assert-DawPackage $dest} 'SHA256 do script'
    }
    Test 'stale, wrong-user, running and old-schema status cannot confirm a request' {
        $s=[pscustomobject]@{Schema=2;RequestId='request';UserSid='sid';Phase='Completed';Success=$true;Error=$null}
        Assert (Test-DawRequestState $s 'request' 'sid')
        Assert (-not(Test-DawRequestState $s 'old-request' 'sid'))
        Assert (-not(Test-DawRequestState $s 'request' 'other-sid'))
        $s.Phase='Running';Assert (-not(Test-DawRequestState $s 'request' 'sid'))
        Assert (-not(Test-DawRequestState ([pscustomobject]@{Success=$true}) 'request' 'sid'))
        Assert (-not(Test-DawRequestState ([pscustomobject]@{Schema=2}) 'request' 'sid'))
    }
    Test 'VS Code CLI success without installed extensions is rejected' {
        & $script:M {
            function script:Find-DawCode {Join-Path $script:Temp 'Code.exe'}
            function script:Test-Path {param($LiteralPath) $true}
            function script:Invoke-DawNative {param($File,$Arguments) @()}
        }
        # Use module-local path: no actual VS Code process is launched.
        & $script:M {function script:Find-DawCode {'/fake/Code.exe'}}
        Throws {Install-DawCodeExtensions} 'non confirmada'
    }
    Test 'CLI errors remain failures and ELECTRON_RUN_AS_NODE restored' {
        & $script:M {
            function script:Find-DawCode {'/fake/Code.exe'}
            function script:Test-Path {param($LiteralPath) $true}
            function script:Invoke-DawNative {param($File,$Arguments) throw 'marketplace blocked'}
        }
        $old=$env:ELECTRON_RUN_AS_NODE
        Throws {Install-DawCodeExtensions} 'marketplace blocked'
        Assert ($env:ELECTRON_RUN_AS_NODE -eq $old)
    }
    Test 'bounded jobs really stay below the requested concurrency' {
        $worker={param($item) $s=[datetime]::UtcNow.Ticks;Start-Sleep -Milliseconds 400;[pscustomobject]@{Item=$item;Start=$s;End=[datetime]::UtcNow.Ticks}}
        $result=@(Invoke-DawBoundedJobs @(1,2,3,4,5,6) 2 $worker)
        Assert ($result.Count -eq 6)
        foreach($r in $result){$active=@($result|Where-Object {$_.Start -le $r.Start -and $_.End -gt $r.Start}).Count;Assert ($active -le 2) 'Throttle exceeded'}
    }
    Test 'failed background jobs fail and do not leak jobs' {
        $before=@(Get-Job).Count
        Throws {Invoke-DawBoundedJobs @(1,2) 1 {param($n) throw 'worker failed'}} 'worker failed'
        Assert (@(Get-Job).Count -eq $before)
    }

    Test 'project stage from the repository: modes, hashes and tampering' {
        $stage=Join-Path $script:Temp 'stage'
        $m=New-DawProjectStage (Join-Path $script:Repo 'wsl/aula') $stage
        $paths=@($m.Files|ForEach-Object {$_.Path})
        foreach($p in @('compose.override.yaml','.devcontainer/devcontainer.json','docker/aula/zz-aula.ini','docker/aula/000-default.conf','datos/LEME.txt')){Assert ($p -in $paths) "Missing $p"}
        Assert ((@($m.Files|Where-Object {$_.Mode -eq 'CreateOnly'}|ForEach-Object {$_.Path}) -join ',') -eq 'datos/LEME.txt')
        Assert ((Assert-DawProjectOverlay $stage).Revision -eq $m.Revision)
        Throws {New-DawProjectStage (Join-Path $script:Repo 'wsl/aula') $stage} 'xa existe'
        $file=Join-Path $stage 'ficheiros/compose.override.yaml'
        $original=[IO.File]::ReadAllBytes($file)
        [IO.File]::WriteAllText($file,'services: {}')
        Throws {Assert-DawProjectOverlay $stage} 'SHA256 do proxecto'
        [IO.File]::WriteAllBytes($file,$original)
        Assert ((Assert-DawProjectOverlay $stage).Revision -eq $m.Revision)
        [IO.File]::AppendAllText((Join-Path $stage 'actualizar-proxecto.ps1'),'#')
        Throws {Assert-DawProjectOverlay $stage} 'SHA256 do script'
    }
    Test 'project paths stay inside the project and outside www' {
        foreach($p in @('compose.override.yaml','.devcontainer/devcontainer.json','datos/LEME.txt','docker/aula/zz-aula.ini')){Assert (Test-DawProjectPath $p) "Rejected: $p"}
        foreach($p in @('','/etc/passwd','../x','a/../../x','a/./b','www','www/u3/t1.php','WWW/x','a\b','a//b','a b','C:/x')){Assert (-not(Test-DawProjectPath $p)) "Accepted: $p"}
        # A manifest edited by hand cannot reach outside the project either.
        $stage=Join-Path $script:Temp 'stage-paths'
        $null=New-DawProjectStage (Join-Path $script:Repo 'wsl/aula') $stage
        $path=Join-Path $stage 'proxecto.json'
        $m=Get-Content $path -Raw -Encoding UTF8|ConvertFrom-Json
        $m.Files[0].Path='../compose.yaml'
        Write-DawState $path $m
        Throws {Assert-DawProjectOverlay $stage} 'non válida'
    }
    Test 'overlay devcontainer differs from the repository only by the override file' {
        $repo=[IO.File]::ReadAllLines((Join-Path $script:Repo '.devcontainer/devcontainer.json'))
        $overlay=[IO.File]::ReadAllLines((Join-Path $script:Repo 'wsl/aula/proxecto/ficheiros/.devcontainer/devcontainer.json'))
        Assert ($repo.Count -eq $overlay.Count)
        $diff=@(0..($repo.Count-1)|Where-Object {$repo[$_] -ne $overlay[$_]})
        Assert ($diff.Count -eq 1)
        Assert ($overlay[$diff[0]] -eq $repo[$diff[0]].Replace('"../compose.yaml", ','"../compose.yaml", "../compose.override.yaml", '))
    }
    Test 'project updater validates package and origin BEFORE copying' {
        $t=[IO.File]::ReadAllText((Join-Path $script:Repo 'wsl/aula/actualizar-proxecto.ps1'))
        $package=$t.IndexOf('Assert-DawProjectOverlay $PackageDirectory');$origin=$t.IndexOf('Assert-DawOrigin');$copy=$t.IndexOf('Invoke-DawProjectOverlay')
        Assert ($package -gt 0 -and $package -lt $origin -and $origin -lt $copy)
        $bash=Get-DawProjectOverlayScript
        Assert (-not $bash.Contains("`r")) 'Bash must receive LF even from CRLF Windows source'
        Assert ($bash -notmatch 'rm -rf|rm -r |chown|down -v|prune|--unregister|wsl --terminate')
    }
    Test 'overlay copy passes path triples and must report every file' {
        $manifest=[pscustomobject]@{Files=@([pscustomobject]@{Path='compose.override.yaml';Sha256='A'*64;Mode='Replace'},[pscustomobject]@{Path='datos/LEME.txt';Sha256='B'*64;Mode='CreateOnly'})}
        & $script:M {
            $script:Lines=@('substituido compose.override.yaml','conservado datos/LEME.txt','copia /home/ad/proxectos/daw-dev/.daw-backup/x','');$script:Passed=$null
            function script:Invoke-DawNative {param($File,$Arguments) $script:Passed=$Arguments;$script:Lines}
        }
        $r=Invoke-DawProjectOverlay 'Debian-DAW' 'C:\ProgramData\DAW-Aula\proxecto' $manifest
        Assert ((@($r.Replaced) -join ',') -eq 'compose.override.yaml' -and (@($r.Kept) -join ',') -eq 'datos/LEME.txt' -and $r.Backup -like '*/.daw-backup/x')
        $passed=& $script:M {,$script:Passed}
        Assert (($passed[0..7] -join ' ') -eq '-d Debian-DAW -u ad --cd /home/ad/proxectos/daw-dev --exec bash')
        Assert ($passed[-6] -eq 'compose.override.yaml' -and $passed[-5] -eq ('a'*64) -and $passed[-4] -eq 'Replace' -and $passed[-1] -eq 'CreateOnly')
        & $script:M {$script:Lines=@('igual compose.override.yaml')}
        Throws {Invoke-DawProjectOverlay 'Debian-DAW' 'C:\ProgramData\DAW-Aula\proxecto' $manifest} 'non informou'
    }
    # The installer and the project updater share the task runner; both must keep its guarantees.
    foreach($kind in @('install','project')){
    foreach($mode in @('success','stale','corrupt','failure','policy')){
        Test "student task correlation and cleanup: $kind $mode" {
            $root=Join-Path $script:Temp ('task-'+$kind+'-'+$mode)
            New-Item -ItemType Directory -Path (Join-Path $root 'AppData/Local/DAW-Aula') -Force|Out-Null
            & $script:M {
                param($root,$mode,$kind)
                $script:Profile=$root;$script:Mode=$mode;$script:Trace=@();$script:Principal=$null;$script:Command=''
                $script:StateFile=if($kind -eq 'install'){'estado.json'}else{'proxecto-estado.json'}
                function script:Get-DawStudent {[pscustomobject]@{SID='S-1-5-21-123';Profile=$script:Profile}}
                function script:Assert-DawProjectOverlay {param($Directory) if($Directory -ne 'C:\ProgramData\DAW-Aula\proxecto'){throw 'Unexpected stage'};[pscustomobject]@{Revision='r'}}
                function script:Test-Path {param($LiteralPath) if($LiteralPath -eq 'C:\ProgramData\DAW-Aula\daw-aula.psm1'){return $true};Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath}
                function script:New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) $script:Principal=@{User=$UserId;Logon=$LogonType;Level=$RunLevel};[pscustomobject]$script:Principal}
                function script:New-ScheduledTaskAction {param($Execute,$Argument) $script:Command=$Argument;[pscustomobject]@{Command=$Argument}}
                function script:New-ScheduledTaskSettingsSet {param([switch]$Hidden,$ExecutionTimeLimit,[switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries) [pscustomobject]@{Hidden=$true}}
                function script:Register-ScheduledTask {param($TaskName,$Principal,$Action,$Settings) $script:Trace+='registered'}
                function script:Start-ScheduledTask {
                    param($TaskName)
                    $script:Trace+='started'
                    $encoded=($script:Command -split ' ')[-1]
                    $decoded=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
                    if($decoded -notmatch "-RequestId '([0-9a-f]{32})'"){throw 'Missing request identity'}
                    $request=$matches[1]
                    if($script:Mode -eq 'stale'){$request='stale-success'}
                    $state=@{Schema=2;RequestId=$request;UserSid='S-1-5-21-123';Phase='Completed';Success=($script:Mode -ne 'failure');Error='component failed'}
                    $path=Join-Path $script:Profile ('AppData/Local/DAW-Aula/'+$script:StateFile)
                    if($script:Mode -eq 'corrupt'){[IO.File]::WriteAllText($path,'{torn json')}else{Write-DawState $path $state}
                }
                function script:Get-ScheduledTaskInfo {param($TaskName) [pscustomobject]@{LastRunTime=if($script:Mode -eq 'policy'){Get-Date}else{[datetime]::MinValue};LastTaskResult=1}}
                function script:Get-ScheduledTask {param($TaskName) [pscustomobject]@{State='Ready'}}
                function script:Stop-ScheduledTask {param($TaskName,$ErrorAction) $script:Trace+='stopped'}
                function script:Unregister-ScheduledTask {param($TaskName,$Confirm,$ErrorAction) $script:Trace+='removed'}
            } $root $mode $kind
            $call=if($kind -eq 'install'){{Invoke-DawStudentInstall 1}}else{{Invoke-DawProjectUpdate 1 -Restart}}
            $old=$env:SystemRoot;if(-not $old){$env:SystemRoot=$script:Temp}
            try{
                switch($mode){
                    'success' {$r=& $call;Assert $r.Success}
                    'stale' {Throws $call 'Tempo esgotado'}
                    'corrupt' {Throws $call 'Tempo esgotado'}
                    'failure' {Throws $call 'component failed'}
                    # A current failure report would precede policy checking, so make it stale too.
                    'policy' {
                        & $script:M {function script:Start-ScheduledTask {param($TaskName) $script:Trace+='started'}}
                        Throws $call 'Revisar políticas'
                    }
                }
            }finally{$env:SystemRoot=$old}
            $principal=& $script:M {$script:Principal}
            Assert ($principal.User -eq 'S-1-5-21-123' -and $principal.Logon -eq 'Interactive' -and $principal.Level -eq 'Limited')
            Assert (((& $script:M {$script:Trace}) -join ',') -eq 'registered,started,stopped,removed')
            $decoded=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(((& $script:M {$script:Command}) -split ' ')[-1]))
            $expected=if($kind -eq 'install'){"^& 'C:\\ProgramData\\DAW-Aula\\instalar-alumno\.ps1' -RequestId '[0-9a-f]{32}' -ExpectedUserSid 'S-1-5-21-123' -PackageDirectory 'C:\\ProgramData\\DAW-Aula'$"}else{"^& 'C:\\ProgramData\\DAW-Aula\\proxecto\\actualizar-proxecto\.ps1' -RequestId '[0-9a-f]{32}' -ExpectedUserSid 'S-1-5-21-123' -PackageDirectory 'C:\\ProgramData\\DAW-Aula\\proxecto' -Reiniciar$"}
            Assert ($decoded -match $expected) ('Unexpected task command: '+$decoded)
        }
    }
    }
    if($env:OS -eq 'Windows_NT'){
        Test 'actual Windows task principal constructor' {
            $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            $p=New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Limited
            # Windows may canonicalize a supplied SID to DOMAIN\user in the returned CIM object.
            $actual=if($p.UserId -match '^S-1-'){ $p.UserId }else{ (New-Object Security.Principal.NTAccount($p.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value }
            Assert ($actual -eq $sid) ('Unexpected principal: '+$p.UserId)
            Assert ($p.LogonType -in @('Interactive',3) -and $p.RunLevel -in @('Limited',0)) ('Unexpected token: '+$p.LogonType+'/'+$p.RunLevel)
        }
    }
    Write-Host "ALL $script:Count POWERSHELL TESTS PASSED"
}finally{Remove-Module daw-aula -Force -ErrorAction SilentlyContinue;Remove-Item -LiteralPath $script:Temp -Recurse -Force}
