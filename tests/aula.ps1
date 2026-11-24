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
        # wsl.exe 3.0 executa "--list" como orde: as opcións van sen comiñas.
        foreach($bare in '--list','-d','Debian','C:\ProgramData\DAW-Aula\','/home/ad/proxectos/daw-dev'){Assert ((ConvertTo-DawArgument $bare) -ceq $bare) "Quoted: $bare"}
        Assert ((ConvertTo-DawArgument '') -eq '""')
        Assert ((ConvertTo-DawArgument 'a b\') -eq '"a b\\"')
        Assert ((ConvertTo-DawArgument 'a"b') -eq '"a\"b"')
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
    Test 'account without distributions lists none; other WSL errors stop' {
        & $script:M {
            $script:Registered=@()
            function script:Invoke-DawNative {param($File,$Arguments) throw 'wsl.exe (exit -1): Subsistema de Windows para Linux no tiene distribuciones instaladas.'}
            function script:Get-DawRegisteredDistributions {$script:Registered}
        }
        Assert (@(Get-DawDistributions).Count -eq 0) 'A fresh account must report no distributions'
        & $script:M {$script:Registered=@('Debian')}
        Throws {Get-DawDistributions} 'exit -1'
        & $script:M {
            $script:Registered=@()
            function script:Invoke-DawNative {param($File,$Arguments) throw 'wsl.exe (exit 1): WSL non dispoñible'}
        }
        Throws {Get-DawDistributions} 'exit 1'
        & $script:M {function script:Invoke-DawNative {param($File,$Arguments) "D`0e`0b`0i`0a`0n`0",'',' Ubuntu '}}
        $list=@(Get-DawDistributions)
        Assert ($list.Count -eq 2 -and $list[0] -eq 'Debian' -and $list[1] -eq 'Ubuntu')
        foreach($name in 'instalar-alumno.ps1','actualizar-proxecto.ps1'){
            $t=[IO.File]::ReadAllText((Join-Path $script:Repo "wsl/aula/$name"))
            Assert ($t.Contains('Get-DawDistributions') -and -not $t.Contains("'--list'")) "$name must use Get-DawDistributions"
        }
    }
    Test 'unrecognized distro rejected with read-only WSL call' {
        & $script:M {
            $script:Calls=@()
            function script:Invoke-DawNative {param($File,$Arguments) $script:Calls+=, $Arguments; 'foreign-model'}
        }
        Throws {Assert-DawOrigin 'Debian' 'daw-aula-v1' ('a'*64) (Join-Path $script:Temp 'absent') $false} 'non é un modelo'
        $calls=& $script:M {,$script:Calls}
        Assert ($calls.Count -eq 1 -and $calls[0] -contains 'cat' -and $calls[0] -notcontains 'bash')
    }
    Test 'mismatching origin never migrated; missing origin requires explicit adoption' {
        & $script:M {function script:Invoke-DawNative {param($File,$Arguments) 'daw-aula-v1'}}
        $p=Join-Path $script:Temp 'origin.sha';Set-Content $p ('b'*64)
        Throws {Assert-DawOrigin 'Debian' 'daw-aula-v1' ('a'*64) $p $false} 'doutro modelo'
        Remove-Item $p
        Throws {Assert-DawOrigin 'Debian' 'daw-aula-v1' ('a'*64) $p $false} 'sen rexistro'
        Assert-DawOrigin 'Debian' 'daw-aula-v1' ('a'*64) $p $false -AdoptExisting
        Assert-DawOrigin 'Debian' 'daw-aula-v1' ('a'*64) $p $true
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
        $image=Join-Path $dest 'debian.tar.gz';[IO.File]::WriteAllText($image,'model bytes')
        $sha=(Get-FileHash $image -Algorithm SHA256).Hash
        Write-DawState (Join-Path $dest 'manifest.json') @{Schema=1;Marker='daw-aula-v1';LinuxUser='ad';Image='debian.tar.gz';Sha256=$sha}
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
        & $script:M {function script:Find-DawCode {'/fake/Code.exe'};function script:Find-DawCodeCli {param($Code) '/fake/cli.js'}}
        Throws {Install-DawCodeExtensions} 'non confirmada'
    }
    Test 'VS Code CLI found in versioned and legacy layouts' {
        $sep=[IO.Path]::DirectorySeparatorChar
        function New-Layout([string]$Name,[string]$CliDir,[string]$Cmd){
            $root=Join-Path $script:Temp $Name
            New-Item -ItemType Directory -Path (Join-Path $root 'bin') -Force|Out-Null
            if($CliDir){
                $out=Join-Path $root ($CliDir.Replace('\',$sep))
                New-Item -ItemType Directory -Path $out -Force|Out-Null
                Set-Content -LiteralPath (Join-Path $out 'cli.js') ''
            }
            if($Cmd){[IO.File]::WriteAllText((Join-Path $root ('bin'+$sep+'code.cmd')),$Cmd)}
            Join-Path $root 'Code.exe'
        }
        # VS Code 1.122: recursos no directorio do commit, sinalado por bin\code.cmd.
        $code=New-Layout 'vscode-versioned' '6a49527b96\resources\app\out' "@echo off`r`n`"%~dp0..\Code.exe`" `"%~dp0..\6a49527b96\resources\app\out\cli.js`" %*`r`n"
        Assert ((Find-DawCodeCli $code).Replace($sep,'\').EndsWith('vscode-versioned\6a49527b96\resources\app\out\cli.js'))
        $code=New-Layout 'vscode-legacy' 'resources\app\out' $null
        Assert ((Find-DawCodeCli $code).Replace($sep,'\').EndsWith('vscode-legacy\resources\app\out\cli.js'))
        $code=New-Layout 'vscode-missing' $null "@echo off`r`n`"%~dp0..\Code.exe`" `"%~dp0..\0000000000\resources\app\out\cli.js`" %*`r`n"
        Throws {Find-DawCodeCli $code} 'Falta a CLI'
    }
    Test 'CLI errors remain failures and ELECTRON_RUN_AS_NODE restored' {
        & $script:M {
            function script:Find-DawCode {'/fake/Code.exe'}
            function script:Find-DawCodeCli {param($Code) '/fake/cli.js'}
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
        foreach($p in @('compose.override.yaml','.devcontainer/devcontainer.json','.vscode/launch.json','.vscode/settings.json','docs/guia-inicio-alumnado.pdf','scripts/daw.sh','docker/aula/zz-aula.ini','docker/aula/000-default.conf','datos/LEME.txt')){Assert ($p -in $paths) "Missing $p"}
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
        foreach($p in @('compose.override.yaml','.devcontainer/devcontainer.json','.vscode/launch.json','datos/LEME.txt','docker/aula/zz-aula.ini')){Assert (Test-DawProjectPath $p) "Rejected: $p"}
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
    Test 'extra Docker images in the package are registered, verified and copied' {
        $dest=Join-Path $script:Temp 'package-images'
        New-Item -ItemType Directory -Path $dest -Force|Out-Null
        foreach($name in Get-DawSetupFiles){[IO.File]::WriteAllText((Join-Path $dest $name),('payload '+$name))}
        $image=Join-Path $dest 'debian.tar.gz';[IO.File]::WriteAllText($image,'model bytes')
        $hashes=[ordered]@{};foreach($name in Get-DawSetupFiles){$hashes[$name]=(Get-FileHash (Join-Path $dest $name) -Algorithm SHA256).Hash}
        Write-DawState (Join-Path $dest 'manifest.json') @{Schema=1;Marker='daw-aula-v1';LinuxUser='ad';Image='debian.tar.gz';Sha256=(Get-FileHash $image -Algorithm SHA256).Hash;SetupRevision=2;ScriptSha256=[pscustomobject]$hashes}
        Assert (@(Get-DawPackageImages (Assert-DawPackage $dest)).Count -eq 0)
        $archive=Join-Path $script:Temp 'dwcc-angular.tar.gz';[IO.File]::WriteAllText($archive,'angular bytes')
        $entry=Add-DawPackageImage $dest $archive 'ghcr.io/miguelfm/dwcc-angular:22'
        Assert ($entry.File -eq 'dwcc-angular.tar.gz' -and (Test-Path (Join-Path $dest 'dwcc-angular.tar.gz')))
        $null=Add-DawPackageImage $dest $archive 'ghcr.io/miguelfm/dwcc-angular:22'
        $images=@(Get-DawPackageImages (Assert-DawPackage $dest))
        Assert ($images.Count -eq 1 -and $images[0].Name -eq 'ghcr.io/miguelfm/dwcc-angular:22') 'Repeating the image must replace its entry'
        [IO.File]::WriteAllText((Join-Path $dest 'dwcc-angular.tar.gz'),'tampered')
        Throws {Assert-DawPackage $dest} 'imaxe Docker'
        Throws {Get-DawPackageImages ([pscustomobject]@{Images=@([pscustomobject]@{File='../x.tar';Sha256=('a'*64);Name='x'})})} 'non recoñecida'
        $t=[IO.File]::ReadAllText((Join-Path $script:Repo 'wsl/aula/gestionar-aula.ps1'))
        Assert ($t.Contains('Get-DawPackageImages $manifest')) 'CopiarModelo must copy the extra images'
    }
    Test 'Angular is a profiled service started, stopped and logged by the launcher' {
        $compose=[IO.File]::ReadAllText((Join-Path $script:Repo 'compose.yaml'))
        Assert ($compose.Contains('profiles: ["angular"]') -and $compose.Contains('./angular:/home/node/proxectos') -and $compose.Contains('127.0.0.1:2222') -and $compose.Contains('127.0.0.1:4200'))
        $daw=[IO.File]::ReadAllText((Join-Path $script:Repo 'wsl/daw.ps1'))
        foreach($s in "'stop' { `$composeArgs = @('--profile', 'angular', '--profile', 'doc', 'stop') }","'start-angular' { `$composeArgs = @('--profile', 'angular')","'logs' { `$composeArgs = @('--profile', 'angular', '--profile', 'doc'"){Assert ($daw.Contains($s)) "Missing: $s"}
        Assert ([IO.File]::ReadAllText((Join-Path $script:Repo 'wsl/install-daw-commands.ps1')).Contains("'daw-start-angular' = 'start-angular'"))
    }
    Test 'offline docs are a profiled service loaded from the package and started by the launcher' {
        $compose=[IO.File]::ReadAllText((Join-Path $script:Repo 'compose.yaml'))
        foreach($s in 'profiles: ["doc"]','127.0.0.1:8080}:80','127.0.0.1:5042}:9292','127.0.0.1:8088}:80'){Assert ($compose.Contains($s)) "Missing: $s"}
        $daw=[IO.File]::ReadAllText((Join-Path $script:Repo 'wsl/daw.ps1'))
        foreach($s in "'start-doc' { `$composeArgs = @('--profile', 'doc')","'daw-doc-php.tar.gz'","'daw-doc-devdocs.tar.gz'","'daw-doc-laravel.tar.gz'","'start-angular', 'start-doc')"){Assert ($daw.Contains($s)) "Missing: $s"}
        Assert ([IO.File]::ReadAllText((Join-Path $script:Repo 'wsl/install-daw-commands.ps1')).Contains("'daw-start-doc' = 'start-doc'"))
    }
    Test 'manual activation installs, then applies the staged project, and reports failures' {
        $exe=(Get-Process -Id $PID).Path
        $dir=Join-Path $script:Temp 'activation'
        New-Item -ItemType Directory -Path (Join-Path $dir 'proxecto') -Force|Out-Null
        Copy-Item (Join-Path $script:Repo 'wsl/aula/activar-dawdev.ps1') $dir
        $log=Join-Path $dir 'calls.txt'
        [IO.File]::WriteAllText((Join-Path $dir 'instalar-alumno.ps1'),"param(`$PackageDirectory) Add-Content '$log' ('install '+`$PackageDirectory); if(`$env:DAW_TEST_FAIL){throw 'install failed'}")
        [IO.File]::WriteAllText((Join-Path $dir 'proxecto/actualizar-proxecto.ps1'),"param(`$PackageDirectory) Add-Content '$log' ('project '+`$PackageDirectory)")
        $script=Join-Path $dir 'activar-dawdev.ps1'
        # Sen proxecto.json no equipo, só instala.
        $null=& $exe -NoProfile -File $script -SenPausa
        Assert ($LASTEXITCODE -eq 0)
        $calls=@(Get-Content $log)
        Assert ($calls.Count -eq 1 -and $calls[0] -eq "install $dir") ($calls -join ';')
        [IO.File]::WriteAllText((Join-Path $dir 'proxecto/proxecto.json'),'{}')
        Remove-Item $log
        $null=& $exe -NoProfile -File $script -SenPausa
        $calls=@(Get-Content $log)
        Assert ($LASTEXITCODE -eq 0 -and $calls.Count -eq 2 -and $calls[1] -eq ('project '+(Join-Path $dir 'proxecto'))) ($calls -join ';')
        Remove-Item $log
        $env:DAW_TEST_FAIL='1'
        try{$out=& $exe -NoProfile -File $script -SenPausa 6>&1|Out-String}finally{Remove-Item Env:\DAW_TEST_FAIL}
        Assert ($LASTEXITCODE -eq 1 -and @(Get-Content $log).Count -eq 1 -and $out -match 'install failed')
        # O executor de GitHub remata co último LASTEXITCODE: o fallo simulado non pode quedar nel.
        $global:LASTEXITCODE=0
    }
    if($env:OS -eq 'Windows_NT'){
        Test 'start menu entry runs the activation script of the package' {
            $dir=Join-Path $script:Temp 'start menu'
            $path=Set-DawStartMenuShortcut -Directory $dir -Package 'C:\ProgramData\DAW-Aula'
            $link=(New-Object -ComObject WScript.Shell).CreateShortcut($path)
            Assert ($link.TargetPath -match 'WindowsPowerShell\\v1\.0\\powershell\.exe$')
            Assert ($link.Arguments -eq '-NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\DAW-Aula\activar-dawdev.ps1"')
        }
    }
    Test 'CopiarModelo stages the project and creates the start menu entry, without autostart' {
        $t=[IO.File]::ReadAllText((Join-Path $script:Repo 'wsl/aula/gestionar-aula.ps1'))
        foreach($s in 'Initialize-DawProjectDirectory','Assert-DawProjectOverlay (Get-DawProjectDirectory)','Set-DawStartMenuShortcut','Set-DawAutoStart -Enabled:$enableAuto'){Assert ($t.Contains($s)) "Missing: $s"}
        Assert ('activar-dawdev.ps1' -in @(Get-DawSetupFiles))
    }
    Test 'overlay Compose and Angular files are the repository ones' {
        foreach($p in 'compose.yaml','docker/angular/Dockerfile','docker/angular/inicio.sh','docker/angular/.dockerignore'){
            $a=[IO.File]::ReadAllBytes((Join-Path $script:Repo $p))
            $b=[IO.File]::ReadAllBytes((Join-Path $script:Repo ('wsl/aula/proxecto/ficheiros/'+$p)))
            Assert ([Convert]::ToBase64String($a) -eq [Convert]::ToBase64String($b)) "Overlay differs: $p"
        }
    }
    Test 'overlay launch.json is the repository one and maps the classroom web root' {
        $repo=[IO.File]::ReadAllText((Join-Path $script:Repo '.vscode/launch.json'))
        Assert ($repo -eq [IO.File]::ReadAllText((Join-Path $script:Repo 'wsl/aula/proxecto/ficheiros/.vscode/launch.json')))
        Assert ($repo.Contains('"/home/ad/html": "${workspaceFolder}/www"') -and $repo.Contains('"/var/www/html": "${workspaceFolder}/www"'))
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
        $r=Invoke-DawProjectOverlay 'Debian' 'C:\ProgramData\DAW-Aula\proxecto' $manifest
        Assert ((@($r.Replaced) -join ',') -eq 'compose.override.yaml' -and (@($r.Kept) -join ',') -eq 'datos/LEME.txt' -and $r.Backup -like '*/.daw-backup/x')
        $passed=& $script:M {,$script:Passed}
        Assert (($passed[0..7] -join ' ') -eq '-d Debian -u ad --cd /home/ad/proxectos/daw-dev --exec bash')
        Assert ($passed[-6] -eq 'compose.override.yaml' -and $passed[-5] -eq ('a'*64) -and $passed[-4] -eq 'Replace' -and $passed[-1] -eq 'CreateOnly')
        & $script:M {$script:Lines=@('igual compose.override.yaml')}
        Throws {Invoke-DawProjectOverlay 'Debian' 'C:\ProgramData\DAW-Aula\proxecto' $manifest} 'non informou'
    }
    # The installer and the project updater share the task runner; both must keep its guarantees.
    foreach($kind in @('install','project')){
    foreach($mode in @('success','stale','corrupt','failure','policy','silent')){
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
                function script:New-ScheduledTaskAction {param($Execute,$Argument) $script:Execute=$Execute;$script:Command=$Argument;[pscustomobject]@{Command=$Argument}}
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
                function script:Get-ScheduledTaskInfo {param($TaskName) [pscustomobject]@{LastRunTime=if($script:Mode -in @('policy','silent')){Get-Date}else{[datetime]::MinValue};LastTaskResult=if($script:Mode -eq 'silent'){0}else{1}}}
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
                    # conhost --headless devolve 0 aínda que PowerShell morra sen escribir o estado.
                    'silent' {
                        & $script:M {function script:Start-ScheduledTask {param($TaskName) $script:Trace+='started'}}
                        $call=if($kind -eq 'install'){{Invoke-DawStudentInstall 30}}else{{Invoke-DawProjectUpdate 30 -Restart}}
                        Throws $call 'rematou sen informar'
                    }
                }
            }finally{$env:SystemRoot=$old}
            Assert ((& $script:M {$script:Execute}) -match 'conhost\.exe$' -and (& $script:M {$script:Command}) -match '^--headless "') 'Task must run in headless conhost'
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
