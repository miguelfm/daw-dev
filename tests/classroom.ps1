#requires -Version 5.1
$ErrorActionPreference='Stop'
$script:Repo=Split-Path $PSScriptRoot
$script:ModulePath=Join-Path $script:Repo 'windows/classroom/daw-classroom.psm1'
$script:Temp=Join-Path ([IO.Path]::GetTempPath()) ('daw-tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:Temp|Out-Null
$script:Count=0
# daw.ps1 repón os lanzadores en .local\bin: nas probas, só no perfil temporal da súa.
$env:DAW_SKIP_LAUNCHER_REPAIR='1'
function Assert($Condition,[string]$Message='Assertion failed'){if(-not $Condition){throw $Message}}
function Throws([scriptblock]$Body,[string]$Pattern='.'){
    $caught=$false
    try{& $Body|Out-Null}catch{$caught=$true;if($_.Exception.Message -notmatch $Pattern){throw "Unexpected: $($_.Exception.Message)"}}
    Assert $caught 'Expected an exception'
}
function Test([string]$Name,[scriptblock]$Body){
    Remove-Module daw-classroom -Force -ErrorAction SilentlyContinue
    Import-Module $script:ModulePath -Force
    $script:M=Get-Module daw-classroom
    & $Body
    $script:Count++
    Write-Host "PASS $Name"
}
try{
    Test 'PowerShell sources parse' {
        foreach($f in @('windows','wsl','tests')|ForEach-Object {Get-ChildItem (Join-Path $script:Repo $_) -Recurse -Include *.ps1,*.psm1}){
            $e=$null;$null=[Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$null,[ref]$e)
            Assert ($e.Count -eq 0) "$($f.Name): $e"
        }
    }
    Test 'advanced scripts do not use PSScriptRoot as a parameter default' {
        # Con [CmdletBinding()] e powershell.exe -File, Windows PowerShell 5.1 deixa baleiro
        # $PSScriptRoot nos valores por defecto: verify-user.ps1 fallaba coa orde documentada.
        foreach($f in @('windows','wsl')|ForEach-Object {Get-ChildItem (Join-Path $script:Repo $_) -Recurse -Include *.ps1}){
            $ast=[Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$null,[ref]$null)
            if(-not $ast.ParamBlock -or -not @($ast.ParamBlock.Attributes|Where-Object {$_.TypeName.Name -eq 'CmdletBinding'}).Count){continue}
            foreach($p in $ast.ParamBlock.Parameters){
                Assert (-not($p.DefaultValue -and $p.DefaultValue.Extent.Text -match 'PSScriptRoot')) "$($f.Name): $($p.Name.Extent.Text)"
            }
        }
        $script=Join-Path $script:Temp 'psscriptroot.ps1'
        [IO.File]::WriteAllText($script,"[CmdletBinding()]`r`nparam([string]`$PackageDirectory)`r`nif(-not `$PackageDirectory){`$PackageDirectory=`$PSScriptRoot}`r`n`$PackageDirectory")
        if($IsWindows -ne $false){
            $out=& (Join-Path $PSHOME $(if($PSVersionTable.PSEdition -eq 'Core'){'pwsh.exe'}else{'powershell.exe'})) -NoProfile -ExecutionPolicy Bypass -File $script
            Assert ("$out".Trim() -eq $script:Temp) "With -File: [$out]"
        }
    }
    Test 'terminal activation uses the classroom activator in the selected distribution' {
        $package=Join-Path $script:Temp 'terminal activation'
        New-Item -ItemType Directory -Path $package|Out-Null
        $entry=Join-Path $package 'activate.ps1'
        [IO.File]::WriteAllText($entry,@'
param([string]$Distribution,[switch]$Reinstall,[switch]$SkipVSCode,[switch]$NoPause)
Write-Output "$Distribution|$Reinstall|$SkipVSCode|$NoPause"
exit 0
'@)
        $launcher=Join-Path $script:Repo 'windows/daw.ps1'
        $result=& $launcher -Action activate -Distribution 'linux-proba' -PackageDirectory $package -SkipVSCode
        Assert ($LASTEXITCODE -eq 0 -and $result -eq 'linux-proba|False|True|True') "Unexpected: $result"
        $result=& $launcher -Action activate -Distribution 'linux-proba' -PackageDirectory $package -Reinstall
        Assert ($LASTEXITCODE -eq 0 -and $result -eq 'linux-proba|True|False|True') "Unexpected: $result"
        Throws { & $launcher -Action activate -PackageDirectory (Join-Path $package 'missing') } 'not been deployed'
    }
    if($IsWindows -ne $false){Test 'any daw command restores missing launchers and PATH without mixing installs' {
        $saved=@{USERPROFILE=$env:USERPROFILE;LOCALAPPDATA=$env:LOCALAPPDATA;Path=$env:Path;Skip=$env:DAW_SKIP_LAUNCHER_REPAIR;SkipPath=$env:DAW_SKIP_USER_PATH}
        $launcher=Join-Path $script:Repo 'windows/daw.ps1'
        try{
            Remove-Item Env:DAW_SKIP_LAUNCHER_REPAIR
            $env:DAW_SKIP_USER_PATH='1'
            $enc=[Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
            function Get-Bin([string]$Name){$p=Join-Path $script:Temp $Name;$env:USERPROFILE=$p;$env:LOCALAPPDATA=Join-Path $p 'AppData\Local';$b=Join-Path $p '.local\bin';New-Item -ItemType Directory -Path $b -Force|Out-Null;$b}
            # Os lanzadores anteriores a -Distribution (Debian por defecto) reciben os que faltan.
            $bin=Get-Bin 'repair old'
            $old="@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$launcher"" -Action start %*`r`nexit /b %ERRORLEVEL%`r`n"
            [IO.File]::WriteAllText((Join-Path $bin 'daw-start.cmd'),$old,$enc)
            $null=& $launcher -Action help
            Assert ([IO.File]::ReadAllText((Join-Path $bin 'daw-start.cmd'),$enc) -ceq $old) 'Replaced an existing launcher'
            $activate=[IO.File]::ReadAllText((Join-Path $bin 'daw-activate.cmd'),$enc)
            Assert ($activate.Contains("-File ""$launcher"" -Action activate -Distribution ""Debian"" %*")) 'daw-activate not restored'
            Assert (@(Get-ChildItem $bin -Filter 'daw-*.cmd').Count -eq 20)
            Assert (($env:Path -split ';') -contains $bin) 'PATH not restored'
            # Sen ningún lanzador, restáuranse todos.
            $bin=Get-Bin 'repair empty'
            $null=& $launcher -Action help -Distribution 'Debian-Proba'
            Assert (@(Get-ChildItem $bin -Filter 'daw-*.cmd').Count -eq 20)
            Assert ([IO.File]::ReadAllText((Join-Path $bin 'daw-www.cmd'),$enc).Contains('-Distribution "Debian-Proba"'))
            # Variante da aula: a copia do launcher leva o instalador e mantén a ruta e o usuario.
            $bin=Get-Bin 'repair aula'
            $installer=Join-Path $script:Repo 'windows/install-daw-commands.ps1'
            $null=& $installer -Distribution 'linux' -LinuxProjectPath '/home/ad/.daw' -LinuxUser ad
            $copy=Join-Path $env:LOCALAPPDATA 'DAW-Dev\launcher'
            Assert (Test-Path -LiteralPath (Join-Path $copy 'install-daw-commands.ps1')) 'Installer not copied with the launcher'
            Remove-Item -LiteralPath (Join-Path $bin 'daw-activate.cmd')
            $null=& (Join-Path $copy 'daw.ps1') -Action help -Distribution 'linux' -ProjectPath '/home/ad/.daw' -LinuxUser ad
            Assert ([IO.File]::ReadAllText((Join-Path $bin 'daw-activate.cmd'),$enc).Contains('-File "%LOCALAPPDATA%\DAW-Dev\launcher\daw.ps1" -Action activate -Distribution "linux" -ProjectPath "/home/ad/.daw" -LinuxUser ad %*'))
            # Lanzadores doutra distribución: non se mesturan.
            Remove-Item -LiteralPath (Join-Path $bin 'daw-activate.cmd')
            $null=& (Join-Path $copy 'daw.ps1') -Action help -Distribution 'Outra' -ProjectPath '/home/ad/.daw' -LinuxUser ad
            Assert (-not (Test-Path -LiteralPath (Join-Path $bin 'daw-activate.cmd'))) 'Mixed launchers of another install'
        }finally{
            $env:USERPROFILE=$saved.USERPROFILE;$env:LOCALAPPDATA=$saved.LOCALAPPDATA;$env:Path=$saved.Path;$env:DAW_SKIP_LAUNCHER_REPAIR=$saved.Skip;$env:DAW_SKIP_USER_PATH=$saved.SkipPath
        }
    }}
    Test 'native quoted arguments, errors and timeout' {
        $exe=(Get-Process -Id $PID).Path
        $f=Join-Path $script:Temp 'quoted script.ps1';[IO.File]::WriteAllText($f,'param([string]$Value) $Value | ConvertTo-Json -Compress')
        $value='C:\some folder\a"b\'
        $out=Invoke-DawNative $exe @('-NoProfile','-File',$f,'-Value',$value)
        Assert ((($out -join "`n")|ConvertFrom-Json) -eq $value)
        Throws {Invoke-DawNative $exe @('-NoProfile','-Command','exit 9')} 'exit 9'
        # wsl.exe 3.0 executa "--list" como orde: as opcións van sen comiñas.
        foreach($bare in '--list','-d','linux','C:\ProgramData\DAW-Dev\','/home/ad/.daw'){Assert ((ConvertTo-DawArgument $bare) -ceq $bare) "Quoted: $bare"}
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
        foreach($name in 'install-user.ps1','update-project.ps1'){
            $t=[IO.File]::ReadAllText((Join-Path $script:Repo "windows/classroom/$name"))
            Assert ($t.Contains('Get-DawDistributions') -and -not $t.Contains("'--list'")) "$name must use Get-DawDistributions"
        }
    }
    Test 'the model marker is read without changing the distribution' {
        & $script:M {
            $script:Calls=@();$script:Answer='foreign-model'
            function script:Invoke-DawNative {param($File,$Arguments) $script:Calls+=, $Arguments; if($script:Answer -eq 'fail'){throw 'wsl.exe (exit 1)'}; $script:Answer}
        }
        Assert (-not(Test-DawModelMarker 'linux'))
        $calls=& $script:M {,$script:Calls}
        Assert ($calls.Count -eq 1 -and $calls[0] -contains 'cat' -and $calls[0] -contains '/etc/daw-dev-model' -and $calls[0] -notcontains 'bash')
        & $script:M {$script:Answer="daw-dev-v2`n"}
        Assert (Test-DawModelMarker 'linux')
        Assert (-not(Test-DawModelMarker 'Debian' '/etc/daw-aula-modelo' 'daw-aula-v1')) 'Another marker value'
        & $script:M {$script:Answer='fail'}
        Assert (-not(Test-DawModelMarker 'linux')) 'A distribution that does not start is not ours'
    }
    Test 'a distribution is removed only with the marker of its model' {
        $saved=$env:LOCALAPPDATA
        try{
            $env:LOCALAPPDATA=Join-Path $script:Temp 'remove-distro'
            $dir=Join-Path $env:LOCALAPPDATA 'wsl/linux';New-Item -ItemType Directory -Path $dir -Force|Out-Null
            & $script:M {
                $script:Calls=@();$script:Answer='foreign'
                function script:Invoke-DawNative {param($File,$Arguments) $script:Calls+=, ($Arguments -join ' '); $script:Answer}
            }
            Throws {Remove-DawDistribution 'linux'} 'non é un modelo'
            Assert (-not((& $script:M {$script:Calls}) -match '--unregister')) 'Unregistered a foreign distribution'
            Assert (Test-Path -LiteralPath $dir)
            & $script:M {$script:Answer='daw-dev-v2'}
            Remove-DawDistribution 'linux'
            Assert ((& $script:M {$script:Calls}) -contains '--unregister linux')
            Assert (-not(Test-Path -LiteralPath $dir)) 'The install directory remains'
        }finally{$env:LOCALAPPDATA=$saved}
    }
    Test 'legacy cleanup removes the old DAW model, state and launchers, never a personal Debian' {
        $saved=$env:LOCALAPPDATA
        try{
            foreach($case in 'model','personal'){
                $env:LOCALAPPDATA=Join-Path $script:Temp ('legacy-'+$case)
                foreach($d in 'DAW-Aula','daw-dev-launcher','wsl/Debian'){New-Item -ItemType Directory -Path (Join-Path $env:LOCALAPPDATA $d) -Force|Out-Null}
                Set-Content (Join-Path $env:LOCALAPPDATA 'DAW-Aula/Debian.sha256') ('a'*64)
                & $script:M {
                    param($case)
                    $script:Calls=@();$script:Case=$case
                    function script:Get-DawDocumentsDirectory {'C:\Users\proba\Documents'}
                    function script:Get-DawDistributions {'Debian','Ubuntu'}
                    function script:Invoke-DawNative {
                        param($File,$Arguments)
                        $line=$Arguments -join ' '
                        $script:Calls+=, $(if($line -match ' daw-backup '){'backup '+$Arguments[-3]+' '+$Arguments[-2]+' '+$Arguments[-1]}else{$line})
                        if($script:Case -ne 'model'){return 'other'}
                        if($line -eq '-d Debian -u root --exec cat /etc/daw-aula-modelo'){return 'daw-aula-v1'}
                        if($line -match ' daw-backup '){return 'copied'}
                        'other'
                    }
                } $case
                $pending=Join-Path $env:LOCALAPPDATA 'web-restore.txt'
                $result=Remove-DawLegacyInstall -PendingRestore $pending
                $removed=@($result.Removed)
                $calls=@(& $script:M {$script:Calls})
                Assert (-not(Test-Path (Join-Path $env:LOCALAPPDATA 'DAW-Aula')) -and -not(Test-Path (Join-Path $env:LOCALAPPDATA 'daw-dev-launcher'))) "$case`: old state or launchers remain"
                if($case -eq 'model'){
                    Assert ($calls -contains '--unregister Debian' -and $removed -contains 'wsl:Debian' -and -not(Test-Path (Join-Path $env:LOCALAPPDATA 'wsl/Debian')))
                    $backup=[array]::IndexOf($calls,($calls -match '^backup ')[0]);$unregister=[array]::IndexOf($calls,'--unregister Debian')
                    Assert ($backup -ge 0 -and $backup -lt $unregister) 'The web root must be copied before removing the distribution'
                    Assert (($calls -match '^backup ')[0] -match ' /home/ad/proxectos/daw-dev /home/alumno/proxectos/daw-dev$') 'Old project paths'
                    Assert ($result.Backup -match 'DAW-Dev-www-\d{8}-\d{6}-Debian$' -and (Get-Content $pending) -eq $result.Backup) 'The copy must be pending restore'
                }else{
                    Assert (-not($calls -match '--unregister|^backup') -and (Test-Path (Join-Path $env:LOCALAPPDATA 'wsl/Debian'))) 'A personal Debian must be kept'
                    Assert ($null -eq $result.Backup -and -not(Test-Path $pending))
                }
                Assert (-not($calls -match 'Ubuntu')) 'Only the legacy distribution name is checked'
            }
        }finally{$env:LOCALAPPDATA=$saved}
    }
    Test 'pending web root copies are restored in order into ~/html, then forgotten' {
        $pending=Join-Path $script:Temp 'web-restore.txt'
        Assert (@(Restore-DawPendingWebRoot 'linux' $pending).Count -eq 0) 'Nothing pending'
        Set-Content -LiteralPath $pending -Value @('C:\Users\a\Documents\DAW-Dev-www-1-Debian','C:\Users\a\Documents\DAW-Dev-www-2-linux') -Encoding UTF8
        & $script:M {$script:Calls=@();function script:Invoke-DawNative {param($File,$Arguments) $script:Calls+=, $Arguments}}
        $restored=@(Restore-DawPendingWebRoot 'linux' $pending)
        $calls=@(& $script:M {$script:Calls})
        Assert ($restored.Count -eq 2 -and $calls.Count -eq 2 -and -not(Test-Path $pending))
        Assert (($calls[0][0..5] -join ' ') -eq '-d linux -u ad --exec bash' -and $calls[0][-2] -like '*DAW-Dev-www-1-Debian' -and $calls[0][-1] -eq '/home/ad/html')
        Assert ((Get-DawWebRootBackupScript) -match 'WWW_DIR' -and (Get-DawWebRootRestoreScript) -match '--no-preserve=mode')
    }
    Test 'the installer removes the previous install and only reinstalls on request' {
        $t=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/install-user.ps1'))
        $package=$t.IndexOf('Assert-DawPackage $PackageDirectory');$legacy=$t.IndexOf('Remove-DawLegacyInstall');$check=$t.IndexOf('Test-DawModelMarker $Distribution')
        Assert ($package -gt 0 -and $package -lt $legacy -and $legacy -lt $check)
        $refuse=$t.IndexOf('elseif(-not $Reinstall){throw');$remove=$t.IndexOf('Remove-DawDistribution $Distribution')
        Assert ($refuse -gt $check -and $remove -gt $refuse) 'Another package must be refused before any removal'
        $backup=$t.IndexOf('Backup-DawWebRoot $Distribution');$import=$t.IndexOf("'--import'");$restore=$t.IndexOf('Restore-DawPendingWebRoot')
        Assert ($refuse -lt $backup -and $backup -lt $remove -and $remove -lt $import -and $import -lt $restore) 'Copy, remove, import and restore, in this order'
        Assert ($t.Contains('if($origin -eq $manifest.Sha256 -and -not $Reinstall){$import=$false}')) 'The same package must keep the distribution'
        foreach($f in Get-ChildItem (Join-Path $script:Repo 'windows') -Recurse -Include *.ps1){Assert (-not([IO.File]::ReadAllText($f.FullName).Contains('--unregister'))) "$($f.Name) unregisters outside the module"}
    }
    Test 'default copy does not re-enable autostart; explicit opt-in is separate' {
        & $script:M {
            $script:Run=@{};$script:Actions=@()
            function script:Get-ItemProperty {param($LiteralPath,$Name,$ErrorAction) if($script:Run.ContainsKey($Name)){[pscustomobject]@{$Name=$script:Run[$Name]}}}
            function script:New-ItemProperty {param($Path,$Name,$Value,$PropertyType,[switch]$Force) $script:Run[$Name]=$Value;$script:Actions+="created $Name"}
            function script:Remove-ItemProperty {param($LiteralPath,$Name,$ErrorAction) $script:Run.Remove($Name);$script:Actions+="removed $Name"}
        }
        Set-DawAutoStart
        Assert ((& $script:M {$script:Actions.Count}) -eq 0)
        Set-DawAutoStart -Enabled
        Assert ((& $script:M {$script:Actions}) -contains 'created DAWDev')
        Assert ((& $script:M {Get-DawRunCommand 'DAWDev'}) -eq "& 'C:\ProgramData\DAW-Dev\autostart.ps1'")
        Set-DawAutoStart
        Assert ((& $script:M {$script:Actions}) -contains 'removed DAWDev')
        & $script:M {$script:Run['DAWDev']='some other program'}
        Throws {Set-DawAutoStart} 'allea'
    }
    Test 'the previous autostart entry is removed only when it runs the previous installer' {
        $directory=Join-Path $script:Temp 'previous-package'
        New-Item -ItemType Directory -Path $directory|Out-Null
        $oldFile=Join-Path $directory 'old-package-file.txt'
        [IO.File]::WriteAllText($oldFile,'previous package')
        & $script:M {
            param($directory)
            $script:Run=@{};$script:Actions=@()
            $script:Legacy=Get-DawLegacyInstall
            $script:Legacy.PackageDirectory=$directory
            function script:Get-DawLegacyInstall {$script:Legacy}
            function script:Set-DawProtectedAcl {param($Directory)}
            function script:Get-ItemProperty {param($LiteralPath,$Name,$ErrorAction) if($script:Run.ContainsKey($Name)){[pscustomobject]@{$Name=$script:Run[$Name]}}}
            function script:Remove-ItemProperty {param($LiteralPath,$Name,$ErrorAction) $script:Run.Remove($Name);$script:Actions+="removed $Name"}
            function script:Encode([string]$Command){'powershell.exe -NoProfile -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))}
            $script:Run['DAWAula']=Encode "& 'C:\ProgramData\DAW-Aula\iniciar-usuario.ps1'"
        } $directory
        $removed=@(Remove-DawLegacyPackage)
        Assert ($removed -contains 'Run:DAWAula' -and (& $script:M {$script:Actions}) -contains 'removed DAWAula')
        Assert ($removed -contains $directory -and -not (Test-Path -LiteralPath $oldFile))
        Assert ((@(Get-ChildItem -LiteralPath $directory -Name) -join ',') -ceq 'activar-dawdev.ps1')
        & $script:M {$script:Run['DAWAula']=Encode "& 'C:\outro\programa.ps1'"}
        Throws {Remove-DawLegacyPackage} 'outro programa'
    }
    Test 'package files are copied once: unchanged files are skipped' {
        $src=Join-Path $script:Temp 'copy-src';$dst=Join-Path $script:Temp 'copy-dst'
        New-Item -ItemType Directory -Path $src,$dst -Force|Out-Null
        foreach($f in 'a.tar.gz','b.ps1'){[IO.File]::WriteAllText((Join-Path $src $f),"content $f")}
        Assert ((@(Copy-DawPackageFiles $src $dst @('a.tar.gz','b.ps1')) -join ',') -eq 'a.tar.gz,b.ps1')
        Assert (@(Copy-DawPackageFiles $src $dst @('a.tar.gz','b.ps1')).Count -eq 0) 'Unchanged files must not be copied again'
        [IO.File]::WriteAllText((Join-Path $src 'b.ps1'),'changed content')
        Assert ((@(Copy-DawPackageFiles $src $dst @('a.tar.gz','b.ps1')) -join ',') -eq 'b.ps1')
        Assert ([IO.File]::ReadAllText((Join-Path $dst 'b.ps1')) -eq 'changed content')
        $local=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/install-package.ps1'))
        Assert ($local.Contains('IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)') -and $local.Contains('New-DawProjectStage $PSScriptRoot'))
    }
    Test 'remote startup block binds its explicit opt-in parameter' {
        $f=Join-Path $script:Repo 'windows/classroom/manage.ps1'
        $ast=[Management.Automation.Language.Parser]::ParseFile($f,[ref]$null,[ref]$null)
        $calls=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Complete-DawPackage' -and $n.Extent.Text -match '-AutoStart:'},$true))
        Assert ($calls.Count -eq 1)
        $block=$calls[0].Parent
        while($block -and $block -isnot [Management.Automation.Language.ScriptBlockAst]){$block=$block.Parent}
        Assert ('enableAuto' -in @($block.ParamBlock.Parameters|ForEach-Object {$_.Name.VariablePath.UserPath}))
    }
    Test 'package update preserves image SHA and rejects corrupted script payloads' {
        $source=Join-Path $script:Temp 'src/windows/classroom';$dest=Join-Path $script:Temp 'package'
        New-Item -ItemType Directory -Path $source,$dest -Force|Out-Null
        foreach($name in Get-DawSetupFiles){
            $base=if($name -in @('daw.ps1','install-daw-commands.ps1')){Split-Path -Parent $source}else{$source}
            [IO.File]::WriteAllText((Join-Path $base $name),('payload '+$name))
        }
        $image=Join-Path $dest 'linux.tar.gz';[IO.File]::WriteAllText($image,'model bytes')
        $sha=(Get-FileHash $image -Algorithm SHA256).Hash
        $manifest=@{Schema=2;Marker='daw-dev-v2';LinuxUser='ad';LinuxProjectPath='/home/ad/.daw';Image='linux.tar.gz';Sha256=$sha}
        Write-DawState (Join-Path $dest 'manifest.json') $manifest
        Update-DawPackage $dest $source
        $m=Assert-DawPackage $dest
        Assert ($m.Sha256 -eq $sha -and $m.ScriptSha256.'install-user.ps1' -match '^[0-9A-F]{64}$')
        Assert ([IO.File]::ReadAllText($image) -eq 'model bytes')
        Assert (@(Get-ChildItem (Join-Path $dest 'build') -Directory).Count -eq 1)
        [IO.File]::WriteAllText((Join-Path $dest 'install-user.ps1'),'corrupt')
        Throws {Assert-DawPackage $dest} 'SHA256 do script'
        # Un paquete de DAW-Aula non se recoñece: hai que crear outro con build-package.ps1.
        $old=Join-Path $script:Temp 'old-package';New-Item -ItemType Directory -Path $old|Out-Null
        Write-DawState (Join-Path $old 'manifest.json') @{Schema=1;Marker='daw-aula-v1';LinuxUser='ad';Image='debian.tar.gz';Sha256=$sha;SetupRevision=2}
        Throws {Assert-DawPackage $old} 'build-package'
        Throws {Update-DawPackage $old $source} 'build-package'
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
    Test 'Windows VS Code extensions come from the package, then the Marketplace' {
        # A31EQ01 (26-11-2026): sen Marketplace, a activación fallaba enteira (ETIMEDOUT).
        $pkg=Join-Path $script:Temp 'pkg-windows-ext';New-Item -ItemType Directory -Path $pkg|Out-Null
        $entries=foreach($id in Get-DawPackageCodeExtensionIds){
            $file=Get-DawCodeExtensionFile $id;[IO.File]::WriteAllText((Join-Path $pkg $file),$id)
            [pscustomobject]@{Id=$id;File=$file;Sha256=(Get-FileHash (Join-Path $pkg $file) -Algorithm SHA256).Hash}
        }
        Write-DawState (Join-Path $pkg 'manifest.json') @{CodeExtensions=@($entries)}
        & $script:M {
            function script:Find-DawCode {'/fake/Code.exe'}
            function script:Find-DawCodeCli {param($Code) '/fake/cli.js'}
            $script:Installed=@('ms-vscode-remote.remote-wsl','ms-vscode-remote.remote-ssh');$script:Calls=@()
            function script:Invoke-DawNative {param($File,$Arguments,$TimeoutSeconds)
                $script:Calls+=,@($Arguments)
                if($Arguments -contains '--list-extensions'){return $script:Installed}
                $source=$Arguments[-1]
                if($source -like '*.vsix' -and $env:DAW_TEST_REJECT_VSIX){throw 'not compatible'}
                if($source -notlike '*.vsix' -and $env:DAW_TEST_NO_MARKETPLACE){throw 'ETIMEDOUT'}
                $script:Installed+=$(if($source -like '*.vsix'){(Split-Path -Leaf $source) -replace '^vscode-extension-(.+)\.vsix$','$1'}else{$source})
            }
        }
        try{
            Assert ((@(Install-DawCodeExtensions $pkg) -join ',') -eq ((Get-DawWindowsCodeExtensionIds) -join ','))
            $installs=@(& $script:M {$script:Calls}|Where-Object {$_ -contains '--install-extension'})
            Assert ($installs.Count -eq 1 -and $installs[0][-1] -like '*vscode-extension-ms-vscode-remote.remote-containers.vsix') 'Only the missing one, from the package'
            # VS Code rexeita o .vsix: o Marketplace.
            & $script:M {$script:Installed=@();$script:Calls=@()};$env:DAW_TEST_REJECT_VSIX='1'
            $null=Install-DawCodeExtensions $pkg
            $sources=@(& $script:M {$script:Calls}|Where-Object {$_ -contains '--install-extension'}|ForEach-Object {$_[-1]})
            Assert ($sources.Count -eq 6 -and $sources[1] -eq 'ms-vscode-remote.remote-containers' -and $sources[3] -eq 'ms-vscode-remote.remote-wsl' -and $sources[5] -eq 'ms-vscode-remote.remote-ssh') ($sources -join ',')
            # Nin paquete nin Marketplace: falla coa causa das dúas orixes.
            & $script:M {$script:Installed=@()};$env:DAW_TEST_NO_MARKETPLACE='1'
            Throws {Install-DawCodeExtensions $pkg} '(?s)non confirmada.*not compatible.*ETIMEDOUT'
        }finally{Remove-Item env:DAW_TEST_REJECT_VSIX,env:DAW_TEST_NO_MARKETPLACE -ErrorAction SilentlyContinue}
        # No servidor de WSL e no volume do contedor, só as de PHP.
        & $script:M {$script:Calls=@()}
        Assert ((@(Install-DawPackageCodeExtensions 'linux' ('a'*40) $pkg) -join ',') -eq ((Get-DawCodeExtensionIds) -join ','))
        $wsl=@(& $script:M {$script:Calls})[0]
        Assert (-not(@($wsl|Where-Object {$_ -like '*remote-*'}).Count) -and @($wsl|Where-Object {$_ -like '*.vsix'}).Count -eq 2) ($wsl -join ' ')
        # O activador segue sen elas; verify-user.ps1 compróbaas.
        $install=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/install-user.ps1'))
        Assert ($install -match 'try\{\$status\.CodeExtensions=@\(Install-DawCodeExtensions \$PackageDirectory\)\}\s*catch\{\s*\$status\.CodeExtensionsError') 'Extensions must not stop the activation'
        Assert ([IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/verify-user.ps1')).Contains("Test-DawStep 'Extensións de VS Code'"))
    }
    Test 'vsix engine is read and compared with the oldest VS Code' {
        Assert (Test-DawCodeEngine '^1.101.0' '1.122.0') ; Assert (Test-DawCodeEngine '>=1.122.0' '1.122.0')
        Assert (-not(Test-DawCodeEngine '^1.123.0' '1.122.0')) ; Assert (Test-DawCodeEngine '*' '1.0.0')
        Throws {Test-DawCodeEngine '^1.0.0' 'stable'} 'non válida'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        function New-Vsix([string]$Name,[string]$Json){
            $path=Join-Path $script:Temp $Name
            $zip=[IO.Compression.ZipFile]::Open($path,'Create')
            try{$w=New-Object IO.StreamWriter(($zip.CreateEntry('extension/package.json')).Open());try{$w.Write($Json)}finally{$w.Dispose()}}finally{$zip.Dispose()}
            $path
        }
        $info=Get-DawVsixInfo (New-Vsix 'plain.vsix' '{"name":"remote-wsl","publisher":"ms-vscode-remote","version":"1.104.7","engines":{"vscode":"^1.104.0"}}')
        Assert ($info.Id -eq 'ms-vscode-remote.remote-wsl' -and $info.Version -eq '1.104.7' -and $info.Engine -eq '^1.104.0') ($info|Out-String)
        # Claves que só difiren en maiúsculas: ConvertFrom-Json rexéitaas.
        $info=Get-DawVsixInfo (New-Vsix 'dup.vsix' '{"name":"php-debug","publisher":"xdebug","version":"1.40.2","engines":{"vscode":"^1.66.1"},"contributes":{"a":1,"A":2}}')
        Assert ($info.Id -eq 'xdebug.php-debug' -and $info.Version -eq '1.40.2' -and $info.Engine -eq '^1.66.1') ($info|Out-String)
        $bad=Join-Path $script:Temp 'bad.vsix';$zip=[IO.Compression.ZipFile]::Open($bad,'Create');$zip.Dispose()
        Throws {Get-DawVsixInfo $bad} 'Non é un .vsix'
    }
    Test 'versions compare numerically, and unreadable ones are not newer' {
        Assert (Test-DawNewerVersion '1.2.10' '1.2.9') ; Assert (-not(Test-DawNewerVersion '1.2.9' '1.2.10'))
        Assert (-not(Test-DawNewerVersion '1.2.9' '1.2.9')) ; Assert (-not(Test-DawNewerVersion '1.2.9' $null))
        Assert (-not(Test-DawNewerVersion 'x' '1.0.0'))
    }
    Test 'an older Windows extension is updated from the package, never downgraded' {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $pkg=Join-Path $script:Temp 'pkg-windows-update';New-Item -ItemType Directory -Path $pkg|Out-Null
        $versions=@{'ms-vscode-remote.remote-containers'='0.440.0';'ms-vscode-remote.remote-wsl'='0.90.0';'ms-vscode-remote.remote-ssh'='0.120.0'}
        $entries=foreach($id in Get-DawWindowsCodeExtensionIds){
            $file=Get-DawCodeExtensionFile $id;$path=Join-Path $pkg $file
            $publisher,$name=$id.Split('.',2)
            $zip=[IO.Compression.ZipFile]::Open($path,'Create')
            try{$w=New-Object IO.StreamWriter(($zip.CreateEntry('extension/package.json')).Open());try{$w.Write("{""name"":""$name"",""publisher"":""$publisher"",""version"":""$($versions[$id])""}")}finally{$w.Dispose()}}finally{$zip.Dispose()}
            [pscustomobject]@{Id=$id;File=$file;Sha256=(Get-FileHash $path -Algorithm SHA256).Hash}
        }
        Write-DawState (Join-Path $pkg 'manifest.json') @{CodeExtensions=@($entries)}
        & $script:M {
            function script:Find-DawCode {'/fake/Code.exe'}
            function script:Find-DawCodeCli {param($Code) '/fake/cli.js'}
            # remote-containers is older than the package; remote-wsl, newer; remote-ssh, equal.
            $script:Installed=@('ms-vscode-remote.remote-containers@0.430.0','ms-vscode-remote.remote-wsl@0.99.0','ms-vscode-remote.remote-ssh@0.120.0');$script:Calls=@()
            function script:Invoke-DawNative {param($File,$Arguments,$TimeoutSeconds)
                $script:Calls+=,@($Arguments)
                if($Arguments -contains '--list-extensions'){return $script:Installed}
                if($env:DAW_TEST_REJECT_VSIX){throw 'not compatible'}
            }
        }
        try{
            Assert ((@(Install-DawCodeExtensions $pkg) -join ',') -eq ((Get-DawWindowsCodeExtensionIds) -join ','))
            $calls=@(& $script:M {$script:Calls})
            Assert (@($calls|Where-Object {$_ -contains '--list-extensions'})[0] -contains '--show-versions') 'The installed versions are needed'
            $installs=@($calls|Where-Object {$_ -contains '--install-extension'})
            Assert ($installs.Count -eq 1 -and $installs[0][-1] -like '*vscode-extension-ms-vscode-remote.remote-containers.vsix' -and $installs[0] -notcontains '--force') ($installs|ForEach-Object {$_ -join ' '}|Out-String)
            # VS Code rejects the package file: the installed version stays and the activation goes on.
            $env:DAW_TEST_REJECT_VSIX='1'
            $warnings=@(Install-DawCodeExtensions $pkg 3>&1|Where-Object {$_ -is [Management.Automation.WarningRecord]})
            Assert (@($warnings).Count -eq 1 -and "$($warnings[0])" -match 'remote-containers 0\.430\.0 á 0\.440\.0') ($warnings|Out-String)
        }finally{Remove-Item env:DAW_TEST_REJECT_VSIX -ErrorAction SilentlyContinue}
    }
    Test 'add-vscode-extensions.ps1 downloads only a newer compatible version' {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $dir=Join-Path $script:Temp 'add-extensions';New-Item -ItemType Directory -Path $dir|Out-Null
        foreach($f in 'add-vscode-extensions.ps1','daw-classroom.psm1'){Copy-Item (Join-Path $script:Repo "windows/classroom/$f") $dir}
        $pkg=Join-Path $dir 'package';New-Item -ItemType Directory -Path $pkg|Out-Null
        foreach($name in Get-DawSetupFiles){[IO.File]::WriteAllText((Join-Path $pkg $name),('payload '+$name))}
        $image=Join-Path $pkg 'linux.tar.gz';[IO.File]::WriteAllText($image,'model')
        $hashes=[ordered]@{};foreach($name in Get-DawSetupFiles){$hashes[$name]=(Get-FileHash (Join-Path $pkg $name) -Algorithm SHA256).Hash}
        Write-DawState (Join-Path $pkg 'manifest.json') @{Schema=2;Marker='daw-dev-v2';LinuxUser='ad';LinuxProjectPath='/home/ad/.daw';Image='linux.tar.gz';Sha256=(Get-FileHash $image -Algorithm SHA256).Hash;ScriptSha256=[pscustomobject]$hashes}
        $global:DawTestVsix={param($path,$version)
            $zip=[IO.Compression.ZipFile]::Open($path,'Create')
            try{$w=New-Object IO.StreamWriter(($zip.CreateEntry('extension/package.json')).Open());try{$w.Write("{""name"":""remote-containers"",""publisher"":""ms-vscode-remote"",""version"":""$version"",""engines"":{""vscode"":""^1.100.0""}}")}finally{$w.Dispose()}}finally{$zip.Dispose()}
        }
        $first=Join-Path $dir 'first.vsix';& $global:DawTestVsix $first '0.440.0'
        $null=Add-DawPackageCodeExtension $pkg $first 'ms-vscode-remote.remote-containers'
        # The Marketplace: 0.440.0 needs VS Code 1.100; 0.450.0, VS Code 1.130.
        function global:Invoke-RestMethod {
            $v=@(@{version='0.450.0';targetPlatform=$null;properties=@(@{key='Microsoft.VisualStudio.Code.Engine';value='^1.130.0'})},
                 @{version='0.440.0';targetPlatform=$null;properties=@(@{key='Microsoft.VisualStudio.Code.Engine';value='^1.100.0'})})
            [pscustomobject]@{results=@([pscustomobject]@{extensions=@([pscustomobject]@{versions=@($v|ForEach-Object {[pscustomobject]$_})})})}
        }
        $global:DawTestDownloads=@()
        function global:curl.exe {
            $out=$args[[array]::IndexOf($args,'--output')+1];$url=$args[-1]
            $global:DawTestDownloads+=$url
            & $global:DawTestVsix $out ([regex]::Match($url,'/(\d+\.\d+\.\d+)/vspackage').Groups[1].Value)
            $global:LASTEXITCODE=0
        }
        try{
            $out=& (Join-Path $dir 'add-vscode-extensions.ps1') -PackageDirectory $pkg -Id 'ms-vscode-remote.remote-containers' -CodeVersion 1.122.0 6>&1|Out-String
            Assert ($global:DawTestDownloads.Count -eq 0 -and $out -match 'xa está no paquete') "Same version must not be downloaded: $out"
            $null=& (Join-Path $dir 'add-vscode-extensions.ps1') -PackageDirectory $pkg -Id 'ms-vscode-remote.remote-containers' -CodeVersion 1.130.0 6>&1
            $file=Join-Path $pkg (Get-DawCodeExtensionFile 'ms-vscode-remote.remote-containers')
            Assert ($global:DawTestDownloads.Count -eq 1 -and $global:DawTestDownloads[0] -like '*/0.450.0/vspackage' -and (Get-DawVsixInfo $file).Version -eq '0.450.0') ($global:DawTestDownloads -join ' ')
            Assert ($null -ne (Assert-DawPackage $pkg)) 'The package must stay valid'
            # One bad extension does not stop the others, and the error names it.
            $global:DawTestDownloads=@()
            Throws {& (Join-Path $dir 'add-vscode-extensions.ps1') -PackageDirectory $pkg -Id 'Not.Valid','ms-vscode-remote.remote-containers' 6>$null} 'Non se engadiron: Not\.Valid'
        }finally{Remove-Item function:global:Invoke-RestMethod,function:global:curl.exe,variable:global:DawTestVsix,variable:global:DawTestDownloads -ErrorAction SilentlyContinue}
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
        $m=New-DawProjectStage (Join-Path $script:Repo 'windows/classroom') $stage
        $paths=@($m.Files|ForEach-Object {$_.Path})
        foreach($p in @('compose.override.yaml','html/.devcontainer/devcontainer.json','html/.devcontainer/compose.devcontainer.yaml','html/.vscode/launch.json','html/.vscode/settings.json','docs/guia-inicio-alumnado.pdf','scripts/daw.sh','docker/classroom/zz-classroom.ini','data/README.txt')){Assert ($p -in $paths) "Missing $p"}
        # In the classroom the environment is ~/.daw: VS Code opens ~/html, with its own settings.
        foreach($p in @('.devcontainer/devcontainer.json','.devcontainer/compose.devcontainer.yaml','.vscode/launch.json','.vscode/settings.json')){Assert ($p -notin $paths) "Unused in the classroom: $p"}
        $settings=[IO.File]::ReadAllBytes((Join-Path $stage 'files/html/.vscode/settings.json'))
        Assert ([Convert]::ToBase64String($settings) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $script:Repo '.vscode/settings.json')))) 'html/.vscode/settings.json comes from the repository'
        Assert ((@($m.Files|Where-Object {$_.Mode -eq 'CreateOnly'}|ForEach-Object {$_.Path}) -join ',') -eq 'data/README.txt')
        Assert ((Assert-DawProjectOverlay $stage).Revision -eq $m.Revision)
        Throws {New-DawProjectStage (Join-Path $script:Repo 'windows/classroom') $stage} 'xa existe'
        $file=Join-Path $stage 'files/compose.override.yaml'
        $original=[IO.File]::ReadAllBytes($file)
        [IO.File]::WriteAllText($file,'services: {}')
        Throws {Assert-DawProjectOverlay $stage} 'SHA256 do proxecto'
        [IO.File]::WriteAllBytes($file,$original)
        Assert ((Assert-DawProjectOverlay $stage).Revision -eq $m.Revision)
        [IO.File]::AppendAllText((Join-Path $stage 'update-project.ps1'),'#')
        Throws {Assert-DawProjectOverlay $stage} 'SHA256 do script'
    }
    Test 'project paths stay inside the project and outside the web code' {
        foreach($p in @('compose.override.yaml','html/.devcontainer/devcontainer.json','html/.vscode/launch.json','data/README.txt','angular/README.txt','docker/classroom/zz-classroom.ini')){Assert (Test-DawProjectPath $p) "Rejected: $p"}
        foreach($p in @('','/etc/passwd','../x','a/../../x','a/./b','www','www/u3/t1.php','WWW/x','html','html/u3/t1.php','html/index.php','html/.vscodex/a','a\b','a//b','a b','C:/x')){Assert (-not(Test-DawProjectPath $p)) "Accepted: $p"}
        # A manifest edited by hand cannot reach outside the project either.
        $stage=Join-Path $script:Temp 'stage-paths'
        $null=New-DawProjectStage (Join-Path $script:Repo 'windows/classroom') $stage
        $path=Join-Path $stage 'project.json'
        $m=Get-Content $path -Raw -Encoding UTF8|ConvertFrom-Json
        $m.Files[0].Path='../compose.yaml'
        Write-DawState $path $m
        Throws {Assert-DawProjectOverlay $stage} 'non válida'
    }
    Test 'the classroom Dev Container opens ~/html and reuses the environment in ~/.daw' {
        $read={param($path) ([IO.File]::ReadAllLines((Join-Path $script:Repo $path))|Where-Object {$_ -notmatch '^\s*//'}) -join [char]10|ConvertFrom-Json}
        $repo=& $read '.devcontainer/devcontainer.json'
        $aula=& $read 'windows/classroom/overlay/html/.devcontainer/devcontainer.json'
        Assert (($aula.dockerComposeFile -join ',') -eq '../../.daw/compose.yaml,../../.daw/compose.override.yaml,compose.devcontainer.yaml') ($aula.dockerComposeFile -join ',')
        Assert ($aula.workspaceFolder -ceq '/home/ad/html' -and $aula.initializeCommand.Contains('${localWorkspaceFolder}/../.daw/scripts/daw.sh'))
        foreach($name in 'name','service','remoteUser','shutdownAction'){Assert ($aula.$name -ceq $repo.$name) "Differs from the repository: $name"}
        Assert (($aula.runServices -join ',') -eq 'backend') 'A rebuilt Dev Container should start only the backend.'
        Assert (($aula.customizations|ConvertTo-Json -Depth 8) -eq ($repo.customizations|ConvertTo-Json -Depth 8)) 'Same VS Code settings and extensions'
        $compose=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/overlay/html/.devcontainer/compose.devcontainer.yaml'))
        Assert ($compose.Contains('XDEBUG_CONFIG: client_host=localhost') -and $compose.Contains('build: !reset null') -and $compose -notmatch '- \.:') 'No project mount: the override mounts ~/html'
    }
    Test 'extra Docker images in the package are registered, verified and copied' {
        $dest=Join-Path $script:Temp 'package-images'
        New-Item -ItemType Directory -Path $dest -Force|Out-Null
        foreach($name in Get-DawSetupFiles){[IO.File]::WriteAllText((Join-Path $dest $name),('payload '+$name))}
        $image=Join-Path $dest 'linux.tar.gz';[IO.File]::WriteAllText($image,'model bytes')
        $hashes=[ordered]@{};foreach($name in Get-DawSetupFiles){$hashes[$name]=(Get-FileHash (Join-Path $dest $name) -Algorithm SHA256).Hash}
        Write-DawState (Join-Path $dest 'manifest.json') @{Schema=2;Marker='daw-dev-v2';LinuxUser='ad';LinuxProjectPath='/home/ad/.daw';Image='linux.tar.gz';Sha256=(Get-FileHash $image -Algorithm SHA256).Hash;ScriptSha256=[pscustomobject]$hashes}
        Assert (@(Get-DawPackageImages (Assert-DawPackage $dest)).Count -eq 0)
        $archive=Join-Path $script:Temp 'daw-angular.tar.gz';[IO.File]::WriteAllText($archive,'angular bytes')
        $entry=Add-DawPackageImage $dest $archive 'ghcr.io/miguelfm/daw-angular:22'
        Assert ($entry.File -eq 'daw-angular.tar.gz' -and (Test-Path (Join-Path $dest 'daw-angular.tar.gz')))
        $null=Add-DawPackageImage $dest $archive 'ghcr.io/miguelfm/daw-angular:22'
        $images=@(Get-DawPackageImages (Assert-DawPackage $dest))
        Assert ($images.Count -eq 1 -and $images[0].Name -eq 'ghcr.io/miguelfm/daw-angular:22') 'Repeating the image must replace its entry'
        [IO.File]::WriteAllText((Join-Path $dest 'daw-angular.tar.gz'),'tampered')
        Throws {Assert-DawPackage $dest} 'imaxe Docker'
        Throws {Get-DawPackageImages ([pscustomobject]@{Images=@([pscustomobject]@{File='../x.tar';Sha256=('a'*64);Name='x'})})} 'non recoñecida'
        $t=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/manage.ps1'))
        Assert ($t.Contains('$files = Get-DawPackageFiles $manifest')) 'CopyPackage must copy every package file'
        Assert ($images[0].File -in @(Get-DawPackageFiles (Get-Content (Join-Path $dest 'manifest.json') -Raw|ConvertFrom-Json))) 'The extra images are package files'
    }
    Test 'VS Code Server in the package is registered, verified and copied' {
        $dest=Join-Path $script:Temp 'package-code-server'
        New-Item -ItemType Directory -Path $dest -Force|Out-Null
        foreach($name in Get-DawSetupFiles){[IO.File]::WriteAllText((Join-Path $dest $name),('payload '+$name))}
        $image=Join-Path $dest 'linux.tar.gz';[IO.File]::WriteAllText($image,'model bytes')
        $hashes=[ordered]@{};foreach($name in Get-DawSetupFiles){$hashes[$name]=(Get-FileHash (Join-Path $dest $name) -Algorithm SHA256).Hash}
        Write-DawState (Join-Path $dest 'manifest.json') @{Schema=2;Marker='daw-dev-v2';LinuxUser='ad';LinuxProjectPath='/home/ad/.daw';Image='linux.tar.gz';Sha256=(Get-FileHash $image -Algorithm SHA256).Hash;ScriptSha256=[pscustomobject]$hashes}
        $archive=Join-Path $script:Temp 'server.tar.gz';[IO.File]::WriteAllText($archive,'server bytes')
        Throws {Add-DawPackageCodeServer $dest $archive 'abc'} 'non válido'
        $commit='0123456789abcdef0123456789abcdef01234567'
        $entry=Add-DawPackageCodeServer $dest $archive $commit
        Assert ($entry.File -eq "vscode-server-$commit.tar.gz" -and (Test-Path (Join-Path $dest $entry.File)))
        $null=Add-DawPackageCodeServer $dest $archive $commit
        $servers=@(Get-DawPackageCodeServers (Assert-DawPackage $dest))
        Assert ($servers.Count -eq 1 -and $servers[0].Commit -eq $commit) 'Repeating the commit must replace its entry'
        [IO.File]::WriteAllText((Join-Path $dest $entry.File),'tampered')
        Throws {Assert-DawPackage $dest} 'VS Code Server'
        Throws {Get-DawPackageCodeServers ([pscustomobject]@{CodeServers=@([pscustomobject]@{Commit=$commit;File='../x.tar.gz';Sha256=('a'*64)})})} 'non recoñecido'
        $t=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/manage.ps1'))
        Assert ($t.Contains('$files = Get-DawPackageFiles $manifest')) 'CopyPackage must copy every package file'
    }
    Test 'the VS Code commit comes from product.json of the current version' {
        $root=Join-Path $script:Temp 'vscode-commit'
        $out=Join-Path $root '6a49527b96/resources/app/out';New-Item -ItemType Directory -Path $out,(Join-Path $root 'bin') -Force|Out-Null
        Set-Content -LiteralPath (Join-Path $out 'cli.js') ''
        [IO.File]::WriteAllText((Join-Path $root 'bin/code.cmd'),"@echo off`r`n`"%~dp0..\Code.exe`" `"%~dp0..\6a49527b96\resources\app\out\cli.js`" %*`r`n")
        $product=Join-Path $root '6a49527b96/resources/app/product.json'
        [IO.File]::WriteAllText($product,'{"commit":"6a49527b96aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","quality":"stable"}')
        Assert ((Get-DawCodeCommit (Join-Path $root 'Code.exe')) -eq '6a49527b96aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
        [IO.File]::WriteAllText($product,'{"commit":"6a49527b96aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","quality":"insider"}')
        Throws {Get-DawCodeCommit (Join-Path $root 'Code.exe')} 'estable'
    }
    Test 'the package VS Code Server is installed in WSL and copied to the Dev Containers cache' {
        $package=Join-Path $script:Temp 'code-server-package';New-Item -ItemType Directory -Path $package -Force|Out-Null
        $commit='0123456789abcdef0123456789abcdef01234567'
        $archive=Join-Path $package "vscode-server-$commit.tar.gz";[IO.File]::WriteAllText($archive,'server bytes')
        $sha=(Get-FileHash $archive -Algorithm SHA256).Hash
        Write-DawState (Join-Path $package 'manifest.json') @{CodeServers=@(@{Commit=$commit;File="vscode-server-$commit.tar.gz";Sha256=$sha})}
        $saved=$env:TEMP
        try{
            $env:TEMP=Join-Path $script:Temp 'code-server-temp'
            & $script:M {
                param($commit)
                $script:Commit=$commit;$script:Installed=$false;$script:Calls=@()
                function script:Get-DawCodeCommit {param($Code) $script:Commit}
                function script:Invoke-DawNative {
                    param($File,$Arguments)
                    $script:Calls+=, ($Arguments -join ' ')
                    if($Arguments -contains 'test' -and -not $script:Installed){throw 'wsl.exe (exit 1)'}
                    if($Arguments -contains 'daw-code-server'){$script:Installed=$true;"ready $script:Commit"}
                }
            } $commit
            $r=Initialize-DawCodeServer -Distribution linux -Code 'Code.exe' -PackageDirectory $package -ForContainer
            $calls=@(& $script:M {$script:Calls})
            Assert ($r.Status -eq 'Installed' -and $r.Commit -eq $commit)
            Assert (@($calls -match "(?s)^-d linux -u ad --exec bash -c .* daw-code-server .*vscode-server-$commit\.tar\.gz $commit$").Count -eq 1) ($calls -join ';')
            $cache=Join-Path $env:TEMP "vsch/serverCache/$commit/vscode-server-linux-x64.tar.gz"
            Assert ((Get-FileHash $cache -Algorithm SHA256).Hash -eq $sha) 'Dev Containers cache'
            & $script:M {$script:Calls=@()}
            $r=Initialize-DawCodeServer -Distribution linux -Code 'Code.exe' -PackageDirectory $package
            Assert ($r.Status -eq 'Ready' -and -not(@(& $script:M {$script:Calls}) -match 'daw-code-server')) 'An installed server is not extracted again'
            & $script:M {$script:Commit='fedcba9876543210fedcba9876543210fedcba98'}
            Assert ((Initialize-DawCodeServer -Distribution linux -Code 'Code.exe' -PackageDirectory $package).Status -eq 'Missing')
        }finally{$env:TEMP=$saved}
        $daw=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/daw.ps1'))
        Assert ($daw.Contains('Initialize-DawCodeServer -Distribution $Distribution -Code $CodeExe') -and -not $daw.Contains('instalar.ps1'))
        $install=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/install-user.ps1'))
        Assert ($install.Contains('Initialize-DawCodeServer -Distribution $Distribution -Code (Find-DawCode)'))
    }
    Test 'deploy.ps1 copies to every computer and verifies the connected accounts' {
        Assert ((ConvertTo-DawDeployStatus ([pscustomobject]@{Success=$true;Error=$null})) -eq 'OK')
        Assert ((ConvertTo-DawDeployStatus ([pscustomobject]@{Success=$false;Error='Precísase unha única sesión de alumno conectada.'})) -eq 'Sen alumno')
        Assert ((ConvertTo-DawDeployStatus ([pscustomobject]@{Success=$false;Error='Verificación x fallou: Esta conta aínda non activou DAW Dev (falta a distribución linux).'})) -eq 'Sen activar')
        Assert ((ConvertTo-DawDeployStatus ([pscustomobject]@{Success=$false;Error='Web e MariaDB: timeout'})) -eq 'Erro')
        # Unha ParameterBindingException cita o módulo enteiro, que contén as dúas frases (A31EQ01, 26-11-2026).
        $quoted="No se puede enlazar el parámetro 'ScriptBlock'. No se puede convertir el valor `"$([IO.File]::ReadAllText($script:ModulePath))`" al tipo ScriptBlock."
        Assert ((ConvertTo-DawDeployStatus ([pscustomobject]@{Success=$false;Error=$quoted})) -eq 'Erro') 'An error quoting the module must not look like a missing student'
        # Nos postos, o módulo cárgase desde un ficheiro temporal: New-Module rexeita o bloque nalgúns.
        foreach($f in 'manage.ps1','deploy.ps1'){Assert (-not([IO.File]::ReadAllText((Join-Path $script:Repo "windows/classroom/$f")) -match 'New-Module\s+-ScriptBlock')) "$f must load the module from a file"}
        Assert ((ConvertTo-DawDeployStatus $null) -eq 'Erro')
        $deploy=Join-Path $script:Repo 'windows/classroom/deploy.ps1'
        Throws {& $deploy -PackageDirectory (Join-Path $script:Temp 'none') -SkipCopy} 'SkipCopy só'
        $t=[IO.File]::ReadAllText($deploy)
        Assert ($t.Contains('-Action CopyPackage') -and $t.Contains('-Action Verify') -and -not $t.Contains('InstallUser')) 'deploy.ps1 must not activate accounts'
        $manage=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/manage.ps1'))
        Assert ($manage.Contains("'Verify'") -and $manage.Contains('Invoke-DawStudentVerify'))
        $daw=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/daw.ps1'))
        foreach($name in Get-DawPackageImageNames){Assert ($daw.Contains("'$name'")) "daw.ps1 does not load $name"}
        Assert ('verify-user.ps1' -in @(Get-DawSetupFiles))
    }
    Test 'verify-user.ps1 uses the account launchers and only stops what it started' {
        $t=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/verify-user.ps1'))
        $package=$t.IndexOf('Assert-DawPackage $PackageDirectory');$marker=$t.IndexOf('Test-DawModelMarker $Distribution');$start=$t.IndexOf("Invoke-DawLauncher 'start-db'")
        Assert ($package -gt 0 -and $package -lt $marker -and $marker -lt $start)
        foreach($s in "Invoke-DawLauncher 'start-doc'","if(-not `$wasRunning){try{Invoke-DawLauncher 'stop-all'}","'http://localhost/'","'http://localhost:5042/'",'aínda non activou DAW Dev'){Assert ($t.Contains($s)) "Missing: $s"}
        Assert ($t -notmatch 'Remove-Daw|--unregister|--import|install-daw-commands') 'Verification must not change the installation'
    }
    Test 'the previous daw-activate reaches the new activation' {
        $shim=Get-DawLegacyActivatorScript
        Assert ($shim.Contains("& 'C:\ProgramData\DAW-Dev\activate.ps1' -SkipVSCode:`$SenVSCode -NoPause:`$SenPausa"))
        $e=$null;$null=[Management.Automation.Language.Parser]::ParseInput($shim,[ref]$null,[ref]$e)
        Assert ($e.Count -eq 0) "$e"
        Assert ((Get-DawLegacyInstall).Activator -eq 'activar-dawdev.ps1')
        $module=[IO.File]::ReadAllText($script:ModulePath)
        Assert ($module.Contains('Set-DawProtectedAcl $dir')) 'The transitional activator must not be writable by users'
    }
    Test 'add-doc-images.ps1 verifies each release archive before registering it' {
        $t=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/add-doc-images.ps1'))
        $sha=$t.IndexOf('Get-FileHash -LiteralPath $path');$tags=$t.IndexOf('manifest.json');$add=$t.IndexOf('Add-DawPackageImage $PackageDirectory')
        Assert ($sha -gt 0 -and $sha -lt $tags -and $tags -lt $add) 'SHA256 and image name must be checked before registering'
        Assert ($t.Contains("Get-DawPackageImageNames | Where-Object { `$_ -match '/daw-doc-[a-z]+:' }") -and $t.Contains("'SHA256SUMS'"))
        $docs=@(Get-DawPackageImageNames|Where-Object {$_ -match '/daw-doc-[a-z]+:'})
        Assert ((($docs|ForEach-Object {(($_ -split '/')[-1] -split ':')[0]+'.tar.gz'}) -join ',') -eq 'daw-doc-php.tar.gz,daw-doc-devdocs.tar.gz,daw-doc-laravel.tar.gz')
    }
    Test 'the VS Code commits of a computer come from every installation' {
        $saved=@{PF=$env:ProgramFiles;PF86=${env:ProgramFiles(x86)}}
        try{
            $env:ProgramFiles='/pf';${env:ProgramFiles(x86)}=$null
            & $script:M {
                $script:Tried=@()
                function script:Get-CimInstance {param($ClassName) [pscustomobject]@{LocalPath='/users/a';Special=$false},[pscustomobject]@{LocalPath='/users/b';Special=$false},[pscustomobject]@{LocalPath='/sys';Special=$true}}
                function script:Test-Path {param($LiteralPath,$PathType) $script:Tried+=$LiteralPath; $LiteralPath -match '[\\/](pf|users[\\/]b)[\\/]'}
                function script:Get-DawCodeCommit {param($Code) if($Code -match '[\\/]pf[\\/]'){'a'*40}else{'b'*40}}
            }
            $commits=@(Get-DawInstalledCodeCommits)
            Assert (($commits -join ',') -eq (('a'*40)+','+('b'*40))) ("commits: $($commits -join ','); paths: $((& $script:M {$script:Tried}) -join ' | ')")
        }finally{$env:ProgramFiles=$saved.PF;${env:ProgramFiles(x86)}=$saved.PF86}
    }
    Test 'deploy.ps1 builds and completes the package before copying it' {
        $t=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/deploy.ps1'))
        $order=@("& `$build -OutputDirectory `$PackageDirectory -Resume","& `$build -OutputDirectory `$PackageDirectory -Distribution `$model",'$manifest = Assert-DawPackage $PackageDirectory','check-remote.ps1',"'add-doc-images.ps1'",'Add-DawAngularImage $name',"'add-vscode-extensions.ps1'",'Get-DawPostCodeCommits $reachable',"'add-vscode-server.ps1'",'-Action CopyPackage','-Action Verify')|ForEach-Object {$t.IndexOf($_)}
        Assert (-not($order -contains -1)) 'Missing deploy step'
        Assert (($order -join ',') -eq (@($order|Sort-Object) -join ',')) "deploy.ps1 steps out of order: $($order -join ',')"
        Assert ($t.Contains('$prepare = -not ($SkipPrepare -or $SkipCopy)') -and $t.Contains('Import-Module $file -Force')) 'Package preparation must be optional and load the module from a file'
        Assert ($t.Contains("'DAW-Model-' + (Get-Date") ) 'A new build must not reuse an existing model distribution'
    }
    Test 'deploy.ps1 runs end to end with simulated computers' {
        # deploy.ps1 e o módulo nun directorio propio, con check-remote.ps1 e manage.ps1 simulados.
        $dir=Join-Path $script:Temp 'deploy-run';New-Item -ItemType Directory -Path $dir|Out-Null
        foreach($f in 'deploy.ps1','daw-classroom.psm1'){Copy-Item (Join-Path $script:Repo "windows/classroom/$f") $dir}
        $log=Join-Path $dir 'calls.txt'
        [IO.File]::WriteAllText((Join-Path $dir 'check-remote.ps1'),@'
param($Classroom,$Number,$Domain)
foreach($n in $Number){[pscustomobject]@{Computer=('A{0}EQ{1:D2}.{2}' -f $Classroom,$n,$Domain);IP="172.21.$Classroom.$n";Diagnostico=if($n -eq 4){'Sen resposta TCP'}else{'WSMan responde'}}}
'@)
        # Con BOM: Windows PowerShell 5.1 le como ANSI un script UTF-8 sen BOM e estropearía os tiles.
        [IO.File]::WriteAllText((Join-Path $dir 'manage.ps1'),@"
param(`$Action,`$Classroom,[int[]]`$Number,`$Domain,`$PackageDirectory,`$ThrottleLimit,`$TimeoutSeconds)
Add-Content '$log' ("`$Action "+(`$Number -join ','))
foreach(`$n in `$Number){
    `$computer='A{0}EQ{1:D2}.{2}' -f `$Classroom,`$n,`$Domain
    `$error=switch(`$Action){'CopyPackage'{if(`$n -eq 3){'disco cheo'}} 'Verify'{if(`$n -eq 2){'Precísase unha única sesión de alumno conectada.'}elseif(`$n -eq 7){'Verificación x fallou: Esta conta aínda non activou DAW Dev'}}}
    [pscustomobject]@{Computer=`$computer;Action=`$Action;Success=-not `$error;Error=`$error;Data=`$null}
}
"@,(New-Object Text.UTF8Encoding($true)))
        $pkg=Join-Path $script:Temp 'deploy-package';New-Item -ItemType Directory -Path $pkg|Out-Null
        foreach($name in Get-DawSetupFiles){[IO.File]::WriteAllText((Join-Path $pkg $name),('payload '+$name))}
        [IO.File]::WriteAllText((Join-Path $pkg 'linux.tar.gz'),'model')
        $h=[ordered]@{};foreach($name in Get-DawSetupFiles){$h[$name]=(Get-FileHash (Join-Path $pkg $name) -Algorithm SHA256).Hash}
        Write-DawState (Join-Path $pkg 'manifest.json') @{Schema=2;Marker='daw-dev-v2';LinuxUser='ad';LinuxProjectPath='/home/ad/.daw';Image='linux.tar.gz';Sha256=(Get-FileHash (Join-Path $pkg 'linux.tar.gz') -Algorithm SHA256).Hash;ScriptSha256=[pscustomobject]$h}
        $saved=$env:LOCALAPPDATA
        try{
            $env:LOCALAPPDATA=Join-Path $script:Temp 'deploy-appdata'
            $report=@(& (Join-Path $dir 'deploy.ps1') -Classroom 31 -Number 7,2,3,4 -PackageDirectory $pkg -SkipPrepare -Verify 3>$null 6>$null)
        }finally{$env:LOCALAPPDATA=$saved}
        Assert (($report|ForEach-Object Number) -join ',' -eq '2,3,4,7') 'Report sorted by computer'
        $byNumber=@{};foreach($r in $report){$byNumber[$r.Number]=$r}
        Assert ($byNumber[4].WinRM -eq $false -and $byNumber[4].Package -eq '-' -and $byNumber[4].Detail -eq 'Sen resposta TCP')
        Assert ($byNumber[3].Package -eq 'Erro' -and $byNumber[3].Verify -eq '-' -and $byNumber[3].Detail -eq 'disco cheo') 'A failed copy is not verified'
        Assert ($byNumber[2].Package -eq 'OK' -and $byNumber[2].Verify -eq 'Sen alumno')
        Assert ($byNumber[7].Package -eq 'OK' -and $byNumber[7].Verify -eq 'Sen activar')
        Assert ((Get-Content $log) -join ';' -eq 'CopyPackage 2,3,7;Verify 2,7') ((Get-Content $log) -join ';')
        Assert (@(Get-ChildItem (Join-Path $script:Temp 'deploy-appdata') -Recurse -Filter 'deploy-31-*.csv').Count -eq 1) 'CSV report'
        $windows=[pscustomobject]@{Virtualization=$true;Features=$true;Wsl=$true;RebootPending=$false;Sessions=0}
        Assert ((ConvertTo-DawWindowsStatus $windows) -eq 'OK')
        $windows.RebootPending=$true;Assert ((ConvertTo-DawWindowsStatus $windows) -eq 'Reiniciar')
        $windows.Wsl=$false;Assert ((ConvertTo-DawWindowsStatus $windows) -eq 'Preparar')
        $windows.Virtualization=$false;Assert ((ConvertTo-DawWindowsStatus $windows) -eq 'Erro')
        Throws {& (Join-Path $dir 'deploy.ps1') -PackageDirectory $pkg -RestartComputers} 'RestartComputers só'
    }
    Test 'PHP extensions for VS Code are package files installed offline at activation' {
        $devcontainer=([IO.File]::ReadAllLines((Join-Path $script:Repo '.devcontainer/devcontainer.json'))|Where-Object {$_ -notmatch '^\s*//'}) -join "`n"|ConvertFrom-Json
        Assert ((@($devcontainer.customizations.vscode.extensions) -join ',') -eq ((Get-DawCodeExtensionIds) -join ',')) 'The package extensions must be the Dev Container ones'
        $override=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/overlay/compose.override.yaml'))
        Assert ($override.Contains('vscode-extensions:/home/ad/.vscode-server/extensions') -and $override.Contains("name: $(Get-DawCodeExtensionsVolume)"))
        Assert ([IO.File]::ReadAllText((Join-Path $script:Repo 'Dockerfile')).Contains('/home/ad/.vscode-server/extensions')) 'The image must own the extensions directory'
        # With an image that lacks ~/.vscode-server, Docker creates it as root to mount the volume.
        Assert ($override -match '(?s)\n    post_start:\r?\n( +#[^\n]*\n)*      - user: root\r?\n        command:.*chown ad: /home/ad/\.vscode-server /home/ad/\.vscode-server/extensions') 'The override must give ad the VS Code Server directory with any image'
        $dest=Join-Path $script:Temp 'package-extensions';New-Item -ItemType Directory -Path $dest|Out-Null
        foreach($name in Get-DawSetupFiles){[IO.File]::WriteAllText((Join-Path $dest $name),('payload '+$name))}
        $image=Join-Path $dest 'linux.tar.gz';[IO.File]::WriteAllText($image,'model')
        $hashes=[ordered]@{};foreach($name in Get-DawSetupFiles){$hashes[$name]=(Get-FileHash (Join-Path $dest $name) -Algorithm SHA256).Hash}
        Write-DawState (Join-Path $dest 'manifest.json') @{Schema=2;Marker='daw-dev-v2';LinuxUser='ad';LinuxProjectPath='/home/ad/.daw';Image='linux.tar.gz';Sha256=(Get-FileHash $image -Algorithm SHA256).Hash;ScriptSha256=[pscustomobject]$hashes}
        $vsix=Join-Path $script:Temp 'x.vsix';[IO.File]::WriteAllText($vsix,'PK vsix')
        Throws {Add-DawPackageCodeExtension $dest $vsix 'Not Valid'} 'non válida'
        $entry=Add-DawPackageCodeExtension $dest $vsix 'xdebug.php-debug'
        $null=Add-DawPackageCodeExtension $dest $vsix 'xdebug.php-debug'
        $m=Assert-DawPackage $dest
        Assert (@(Get-DawPackageCodeExtensions $m).Count -eq 1 -and $entry.File -eq 'vscode-extension-xdebug.php-debug.vsix' -and $entry.File -in @(Get-DawPackageFiles $m))
        [IO.File]::WriteAllText((Join-Path $dest $entry.File),'tampered')
        Throws {Assert-DawPackage $dest} 'extensión de VS Code'
        $script=Get-DawCodeExtensionsInstallScript
        foreach($s in '--network none','--pull never','--server-data-dir','chown','--install-extension'){Assert ($script.Contains($s)) "Missing in the install script: $s"}
        Assert (-not $script.Contains("`r"))
        $install=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/install-user.ps1'))
        Assert ($install.IndexOf('Initialize-DawCodeServer') -lt $install.IndexOf('Install-DawPackageCodeExtensions $Distribution $server.Commit')) 'Extensions need the VS Code Server first'
        Assert ([IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/verify-user.ps1')).Contains("Test-DawStep 'Extensións de PHP'"))
    }
    Test 'VS Code classroom defaults disable background Microsoft traffic without overwriting user settings' {
        $fresh=Join-Path $script:Temp 'vscode-user-fresh/Code/User/settings.json'
        $added=@(Set-DawCodeUserSettings -SettingsPath $fresh)
        Assert (($added -join ',') -ceq 'telemetry.telemetryLevel,update.mode,extensions.autoCheckUpdates,extensions.autoUpdate,intelephense.telemetry.enabled') ($added -join ',')
        $parsed=Get-Content -LiteralPath $fresh -Raw -Encoding UTF8|ConvertFrom-Json
        Assert ($parsed.'telemetry.telemetryLevel' -ceq 'off' -and $parsed.'update.mode' -ceq 'none' -and $parsed.'extensions.autoCheckUpdates' -eq $false -and $parsed.'extensions.autoUpdate' -eq $false -and $parsed.'intelephense.telemetry.enabled' -eq $false)
        # Second call is a no-op and does not rewrite the file.
        $before=[IO.File]::GetLastWriteTimeUtc($fresh)
        Assert (@(Set-DawCodeUserSettings -SettingsPath $fresh).Count -eq 0)
        Assert ([IO.File]::GetLastWriteTimeUtc($fresh) -eq $before)
        # Existing JSONC settings and explicit overrides are preserved.
        $custom=Join-Path $script:Temp 'vscode-user-custom/settings.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $custom) -Force|Out-Null
        [IO.File]::WriteAllText($custom,"{`n  // User comment`n  `"editor.fontSize`": 16,`n  `"update.mode`": `"manual`",`n  `"nested`": { `"a`": 1 },`n}`n",(New-Object Text.UTF8Encoding($false)))
        $added=@(Set-DawCodeUserSettings -SettingsPath $custom)
        Assert ($added -notcontains 'update.mode' -and $added -contains 'telemetry.telemetryLevel' -and $added -contains 'intelephense.telemetry.enabled') ($added -join ',')
        $parsed=Get-Content -LiteralPath $custom -Raw -Encoding UTF8|ConvertFrom-Json
        Assert ($parsed.'editor.fontSize' -eq 16 -and $parsed.'update.mode' -ceq 'manual' -and $parsed.nested.a -eq 1 -and $parsed.'telemetry.telemetryLevel' -ceq 'off')
        # Corrupted or non-object JSON is rejected without altering the file.
        $bad=Join-Path $script:Temp 'vscode-user-bad/settings.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $bad) -Force|Out-Null
        [IO.File]::WriteAllText($bad,'[1, 2, 3]')
        Throws {Set-DawCodeUserSettings -SettingsPath $bad} 'non é un obxecto'
        Assert ([IO.File]::ReadAllText($bad) -ceq '[1, 2, 3]')
        $install=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/install-user.ps1'))
        Assert ($install -match 'try\{\$status\.CodeSettings=@\(Set-DawCodeUserSettings\)\}\s*catch\{Write-Warning') 'User settings must not stop activation'
    }
    Test 'VS Code machine policy disables telemetry and auto-updates for every account' {
        & $script:M {
            $script:Keys=@();$script:Props=@{}
            function script:Test-Path {param($LiteralPath) $LiteralPath -in $script:Keys}
            function script:New-Item {param($Path,[switch]$Force) $script:Keys+=$Path}
            function script:New-ItemProperty {param($Path,$Name,$Value,$PropertyType,[switch]$Force) $script:Props["$Path|$Name"]="$PropertyType|$Value"}
        }
        Set-DawCodeMachinePolicy
        $keys=@(& $script:M {$script:Keys})
        $props=& $script:M {$script:Props}
        $reg='HKLM:\SOFTWARE\Policies\Microsoft\VSCode'
        Assert ($keys -contains $reg)
        Assert ($props["$reg|TelemetryLevel"] -ceq 'String|off' -and $props["$reg|UpdateMode"] -ceq 'String|none') ($props|Out-String)
    }
    Test 'the frontend (Angular) is a profiled service started, stopped and logged through daw.sh' {
        $compose=[IO.File]::ReadAllText((Join-Path $script:Repo 'compose.yaml'))
        Assert ($compose.Contains('profiles: ["frontend"]') -and $compose.Contains('./angular:/home/node/proxectos') -and $compose.Contains('127.0.0.1:2222') -and $compose.Contains('127.0.0.1:4200'))
        $sh=[IO.File]::ReadAllText((Join-Path $script:Repo 'scripts/daw.sh'))
        foreach($s in '--profile frontend --profile doc stop','--profile frontend up -d --wait --wait-timeout 300 frontend','--profile frontend --profile doc logs','daw-start-frontend|daw-start-angular) ACTION="start-frontend"'){Assert ($sh.Contains($s)) "Missing in daw.sh: $s"}
        $daw=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/daw.ps1'))
        Assert ($daw.Contains("{ `$_ -in 'start-frontend', 'start-angular' } { `$dawAction = 'start-frontend' }") -and $daw.Contains('--exec env DAW_SKIP_SSH_SETUP=1 bash scripts/daw.sh $dawAction'))
        # daw.ps1 names no service: it works with a project of another version. Only the
        # fallback for a project from before 27-11-2026 names the previous angular service.
        $compose=@([regex]::Matches($daw,'--exec docker compose[^\r\n]*'))
        Assert ($compose.Count -eq 1 -and $compose[0].Value -match '--profile angular up .* angular$') (($compose|ForEach-Object Value) -join ' | ')
        $install=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/install-daw-commands.ps1'))
        Assert ($install.Contains("'daw-start-frontend' = 'start-frontend'") -and $install.Contains("'daw-start-angular' = 'start-frontend'"))
    }
    Test 'the MariaDB health check changes the previous default password and reaches the classroom' {
        $compose=[IO.File]::ReadAllText((Join-Path $script:Repo 'compose.yaml'))
        Assert ($compose.Contains('./docker/mariadb/healthcheck.sh:/usr/local/bin/daw-healthcheck.sh:ro') -and $compose.Contains('test: ["CMD", "sh", "/usr/local/bin/daw-healthcheck.sh"]')) 'Missing health check'
        Assert (-not $compose.Contains('abc123.}')) 'Previous default password'
        Assert ([IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/daw-classroom.psm1')).Contains("'docker/mariadb/healthcheck.sh'"))
        # daw.ps1 starts everything through daw.sh, which migrates .env first.
        Assert ([IO.File]::ReadAllText((Join-Path $script:Repo 'scripts/daw.sh')).Contains('start|start-all|start-db|start-doc|start-frontend|migrar-env) migrar_env ;;'))
    }
    Test 'offline docs are a profiled service loaded from the package and started through daw.sh' {
        $compose=[IO.File]::ReadAllText((Join-Path $script:Repo 'compose.yaml'))
        foreach($s in 'profiles: ["doc"]','127.0.0.1:8080}:80','127.0.0.1:5042}}:9292','127.0.0.1:8088}:80'){Assert ($compose.Contains($s)) "Missing: $s"}
        Assert ([IO.File]::ReadAllText((Join-Path $script:Repo 'scripts/daw.sh')).Contains('doc-php doc-web doc-laravel'))
        $daw=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/daw.ps1'))
        foreach($s in "'daw-doc-php.tar.gz'","'daw-doc-devdocs.tar.gz'","'daw-doc-laravel.tar.gz'","if (`$dawAction -eq 'start-doc')","'start-frontend', 'start-doc')"){Assert ($daw.Contains($s)) "Missing: $s"}
        Assert ([IO.File]::ReadAllText((Join-Path $script:Repo 'windows/install-daw-commands.ps1')).Contains("'daw-start-doc' = 'start-doc'"))
    }
    Test 'containers are named by role: service = hostname, container with -c' {
        $config=try{(& docker compose -f (Join-Path $script:Repo 'compose.yaml') --profile frontend --profile doc config --format json 2>$null) -join "`n"}catch{$null}
        if(-not $config -or $LASTEXITCODE -ne 0){$global:LASTEXITCODE=0;return}
        $services=($config|ConvertFrom-Json).services
        $names=@($services.PSObject.Properties.Name|Sort-Object)
        Assert (($names -join ',') -eq 'backend,db,db-admin,doc-laravel,doc-php,doc-web,frontend') ($names -join ',')
        foreach($n in $names){$s=$services.$n;Assert ($s.hostname -ceq $n -and $s.container_name -ceq "$n-c") "${n}: $($s.hostname) $($s.container_name)"}
        $sh=[IO.File]::ReadAllText((Join-Path $script:Repo 'scripts/daw.sh'))
        Assert ($sh.Contains("OLD_SERVICES='web:backend phpmyadmin:db-admin angular:frontend doc-devdocs:doc-web'"))
        Assert ([IO.File]::ReadAllText((Join-Path $script:Repo 'scripts/check.sh')).Contains('bash scripts/daw.sh remove-old-services')) 'check.sh starts Compose itself'
        $restart=[IO.File]::ReadAllText($script:ModulePath)
        Assert ($restart.Contains("'--exec','bash','scripts/daw.sh','restart-backend'")) 'The activation restarts through daw.sh'
    }
    Test 'manual activation installs, then applies the staged project, and reports failures' {
        $exe=(Get-Process -Id $PID).Path
        $dir=Join-Path $script:Temp 'activation'
        New-Item -ItemType Directory -Path (Join-Path $dir 'project') -Force|Out-Null
        Copy-Item (Join-Path $script:Repo 'windows/classroom/activate.ps1') $dir
        $log=Join-Path $dir 'calls.txt'
        [IO.File]::WriteAllText((Join-Path $dir 'install-user.ps1'),"param(`$PackageDirectory,[switch]`$Reinstall,[switch]`$SkipVSCode,`$Distribution) Add-Content '$log' ('install '+`$PackageDirectory+' '+`$Reinstall+' '+`$Distribution); if(`$env:DAW_TEST_FAIL){throw 'install failed'}")
        [IO.File]::WriteAllText((Join-Path $dir 'project/update-project.ps1'),"param(`$PackageDirectory,`$Distribution,[switch]`$RestartIfChanged) Add-Content '$log' ('project '+`$PackageDirectory+' '+`$Distribution+' '+`$RestartIfChanged)")
        $script=Join-Path $dir 'activate.ps1'
        # Sen project.json no equipo, só instala.
        $null=& $exe -NoProfile -File $script -NoPause
        Assert ($LASTEXITCODE -eq 0)
        $calls=@(Get-Content $log)
        Assert ($calls.Count -eq 1 -and $calls[0] -eq "install $dir False ") ($calls -join ';')
        [IO.File]::WriteAllText((Join-Path $dir 'project/project.json'),'{}')
        Remove-Item $log
        $null=& $exe -NoProfile -File $script -NoPause -Reinstall -Distribution linux-proba
        $calls=@(Get-Content $log)
        Assert ($LASTEXITCODE -eq 0 -and $calls.Count -eq 2 -and $calls[0] -eq "install $dir True linux-proba" -and $calls[1] -eq ('project '+(Join-Path $dir 'project')+' linux-proba True')) ($calls -join ';')
        Remove-Item $log
        $env:DAW_TEST_FAIL='1'
        try{$out=& $exe -NoProfile -File $script -NoPause 6>&1|Out-String}finally{Remove-Item Env:\DAW_TEST_FAIL}
        Assert ($LASTEXITCODE -eq 1 -and @(Get-Content $log).Count -eq 1 -and $out -match 'install failed')
        # O executor de GitHub remata co último LASTEXITCODE: o fallo simulado non pode quedar nel.
        $global:LASTEXITCODE=0
    }
    if($env:OS -eq 'Windows_NT'){
        Test 'start menu entry runs the activation script of the package' {
            $dir=Join-Path $script:Temp 'start menu'
            $path=Set-DawStartMenuShortcut -Directory $dir -Package 'C:\ProgramData\DAW-Dev'
            $link=(New-Object -ComObject WScript.Shell).CreateShortcut($path)
            Assert ($link.TargetPath -match 'WindowsPowerShell\\v1\.0\\powershell\.exe$')
            Assert ($link.Arguments -eq '-NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\DAW-Dev\activate.ps1"')
        }
        Test 'C:\DAW-Dev activator runs the package script and refuses foreign files' {
            # Cambiar o propietario a Administradores require elevación: a ACL compróbase aparte.
            & $script:M {$script:Acls=@();function script:Set-Acl {param($LiteralPath,$AclObject) $script:Acls+=,@($LiteralPath,$AclObject)}}
            $dir=Join-Path $script:Temp 'DAW-Dev'
            $path=Set-DawActivator -Directory $dir -Package 'C:\ProgramData\DAW-Dev'
            $text=[IO.File]::ReadAllText($path)
            Assert ((Split-Path -Leaf $path) -eq 'Activar DAW Dev.cmd' -and $text.Contains('"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\DAW-Dev\activate.ps1"')) $text
            Assert ($text -notmatch '[^\x00-\x7F]' -and $text.Contains("`r`n")) 'cmd.exe needs ASCII and CRLF'
            $acls=@(& $script:M {$script:Acls})
            Assert ($acls.Count -eq 2 -and $acls[0][0] -eq $dir -and $acls[0][1].AreAccessRulesProtected -and $acls[1][0] -eq $path -and -not $acls[1][1].AreAccessRulesProtected) 'Protected directory, inherited file'
            $rules=@($acls[0][1].GetAccessRules($true,$false,[Security.Principal.SecurityIdentifier]))
            Assert (@($rules|Where-Object {$_.IdentityReference.Value -eq 'S-1-5-32-545' -and ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::Write)}).Count -eq 0) 'Users must not write'
            $null=Set-DawActivator -Directory $dir -Package 'C:\ProgramData\DAW-Dev'
            [IO.File]::WriteAllText((Join-Path $dir 'outro.cmd'),'x')
            Throws {Set-DawActivator -Directory $dir} 'alleos'
            Assert (-not([IO.File]::ReadAllText($path).Contains('outro'))) 'A refused directory is left as it was'
        }
    }
    Test 'CopyPackage stages the project and creates the start menu entry, without autostart' {
        # manage.ps1 (por WinRM) e install-package.ps1 (no propio equipo) fan os mesmos pasos do módulo.
        foreach($f in 'manage.ps1','install-package.ps1'){
            $t=[IO.File]::ReadAllText((Join-Path $script:Repo "windows/classroom/$f"))
            $steps=@('Initialize-DawPackageDirectory','Copy-DawPackageFiles','Complete-DawPackage','Complete-DawProjectStage')|ForEach-Object {$t.IndexOf($_)}
            Assert (-not($steps -contains -1)) "$f does not use every package step"
            Assert (($steps -join ',') -eq (@($steps|Sort-Object) -join ',')) "$f runs the package steps out of order"
        }
        $module=[IO.File]::ReadAllText($script:ModulePath)
        foreach($fn in 'Initialize-DawPackageDirectory','Complete-DawPackage','Complete-DawProjectStage'){
            $body=$module.Substring($module.IndexOf("function $fn {"));$body=$body.Substring(0,$body.IndexOf("`nfunction "))
            switch($fn){
                'Initialize-DawPackageDirectory' {Assert ($body.IndexOf('Assert-DawNoInstallRunning') -lt $body.IndexOf('Remove-DawLegacyPackage') -and $body.Contains('Set-DawProtectedAcl $target')) 'Check running installers before removing the previous package'}
                'Complete-DawPackage' {Assert ($body.Contains('Assert-DawPackage (Get-DawPackageDirectory)') -and $body.Contains('Set-DawAutoStart -Enabled:$AutoStart') -and $body.Contains('Set-DawCodeMachinePolicy') -and $body.Contains('Initialize-DawProjectDirectory'))}
                'Complete-DawProjectStage' {Assert ($body.Contains('Assert-DawProjectOverlay (Get-DawProjectDirectory)') -and $body.Contains('Set-DawStartMenuShortcut') -and $body.Contains('Activator=Set-DawActivator'))}
            }
        }
        Assert ('activate.ps1' -in @(Get-DawSetupFiles))
    }
    Test 'the stage takes Compose, Angular and keep-alive from the repository, without overlay copies' {
        $stage=Join-Path $script:Temp 'shared-stage'
        $null=New-DawProjectStage (Join-Path $script:Repo 'windows/classroom') $stage
        foreach($p in 'compose.yaml','docker/angular/Dockerfile','docker/angular/entrypoint.sh','docker/angular/.dockerignore','scripts/daw.sh','scripts/daw_helpers.py','scripts/keep-alive.sh','scripts/setup-angular.sh','scripts/check.sh','docker/mariadb/healthcheck.sh','docs/guia-angular-alumnado.md'){
            Assert (-not(Test-Path -LiteralPath (Join-Path $script:Repo ('windows/classroom/overlay/'+$p)))) "Duplicated in overlay: $p"
            $a=[IO.File]::ReadAllBytes((Join-Path $script:Repo $p))
            $b=[IO.File]::ReadAllBytes((Join-Path $stage ('files/'+$p)))
            Assert ([Convert]::ToBase64String($a) -eq [Convert]::ToBase64String($b)) "Stage differs: $p"
        }
    }
    Test 'deployment names of DAW Dev and of the previous install' {
        Assert ((Get-DawPackageDirectory) -ceq 'C:\ProgramData\DAW-Dev')
        Assert ((Get-DawProjectDirectory) -ceq 'C:\ProgramData\DAW-Dev\project')
        Assert ((Get-DawStateRelativePath) -ceq 'AppData\Local\DAW-Dev')
        $f=Get-DawStateFiles
        Assert ($f.Lock -ceq 'install.lock' -and $f.Install -ceq 'install-state.json' -and $f.InstallLog -ceq 'install.log' -and $f.Project -ceq 'project-state.json' -and $f.ProjectLog -ceq 'project.log')
        Assert ((Get-DawDistribution) -ceq 'linux' -and (Get-DawLinuxProjectPath) -ceq '/home/ad/.daw')
        Assert ((Get-DawLinuxWebPath) -ceq '/home/ad/html' -and (Get-DawLinuxDataPath) -ceq '/home/ad/data' -and (Get-DawLinuxAngularPath) -ceq '/home/ad/angular')
        Assert ((Get-DawWebImage) -ceq 'ghcr.io/miguelfm/daw-php:8.6' -and (Get-DawPreviousWebImage) -ceq 'ghcr.io/miguelfm/dwcs-php:8.6-ad' -and (Get-DawModelArchive) -ceq 'linux.tar.gz')
        Assert ((Get-DawModelMarker).Path -ceq '/etc/daw-dev-model' -and (Get-DawModelMarker).Value -ceq 'daw-dev-v2')
        $legacy=Get-DawLegacyInstall
        Assert ($legacy.PackageDirectory -ceq 'C:\ProgramData\DAW-Aula' -and $legacy.StateRelativePath -ceq 'AppData\Local\DAW-Aula' -and $legacy.Distribution -ceq 'Debian' -and $legacy.Marker -ceq 'daw-aula-v1' -and $legacy.RunValue -ceq 'DAWAula')
        Assert ((ConvertTo-DawAdminSharePath 'A34EQ01.example' 'C:\ProgramData\DAW-Dev\project') -ceq '\\A34EQ01.example\c$\ProgramData\DAW-Dev\project')
        Throws {ConvertTo-DawAdminSharePath 'A34EQ01' '\\outro\ruta'} 'non válida'
        Assert ((ConvertTo-DawWslPath 'linux' '/home/ad/html') -ceq '\\wsl.localhost\linux\home\ad\html')
        $profileRoot=Join-Path $script:Temp 'profile'
        Assert ((Get-DawStateDirectory $profileRoot) -eq (Join-Path $profileRoot 'AppData\Local\DAW-Dev'))
    }
    Test 'Bash scripts get the image and the model marker from the module' {
        Assert ((Get-DawProjectOverlayScript) -notmatch '__DAW_') 'Unexpanded marker'
        Assert ((Get-DawProjectOverlayScript).Contains('web_image=ghcr.io/miguelfm/daw-php:8.6') -and (Get-DawProjectOverlayScript).Contains('previous_image=ghcr.io/miguelfm/dwcs-php:8.6-ad'))
        Assert ((Get-DawProjectOverlayScript) -notmatch 'PHP_VERSION=8\.5|env_tmp') 'The PHP 8.5 migration is gone'
        $setup=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/setup-model.sh'))
        foreach($s in 'project=${DAW_PROJECT:?','web_image=${DAW_WEB_IMAGE:?','marker_file=${DAW_MODEL_MARKER_FILE:?','printf ''%s\n'' "$marker" > "$marker_file"'){Assert ($setup.Contains($s)) "Missing in setup-model.sh: $s"}
        Assert (-not $setup.Contains('/home/ad/www')) 'The model must not link ~/www'
        foreach($s in 'mv -T "$project/www" "$home/html"','mv -T "$project/data" "$home/data"','mv -T "$project/angular" "$home/angular"','"$home/html/.vscode/settings.json"'){Assert ($setup.Contains($s)) "Missing in setup-model.sh: $s"}
        $build=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/build-package.ps1'))
        Assert ($build.Contains('"DAW_PROJECT=$project"') -and $build.Contains('"DAW_MODEL_MARKER=$($marker.Value)"') -and $build.Contains('LinuxProjectPath = $project'))
    }
    Test 'the project moves to ~/.daw and the student directories to the home wherever it is still there' {
        Assert ((@(Get-DawPreviousLinuxProjectPaths) -join ',') -ceq '/home/ad/daw,/home/ad/workspace')
        # A package whose model still has ~/daw or ~/workspace stays valid: the move happens in each account.
        foreach($previous in Get-DawPreviousLinuxProjectPaths){
            $m=[pscustomobject]@{Schema=2;Marker=(Get-DawModelMarker).Value;Image=(Get-DawModelArchive);Sha256=('a'*64);LinuxUser='ad';LinuxProjectPath=$previous}
            Assert-DawManifest $m
        }
        $m.LinuxProjectPath='/home/ad/other';Throws {Assert-DawManifest $m} 'non recoñecido'
        $install=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/install-user.ps1'))
        $config=$install.IndexOf("'--cd',`$project,'--exec','docker','compose','config'")
        Assert ($install.IndexOf('$status.Imported=$true') -lt $install.IndexOf('$status.ProjectMoved=Move-DawProjectDirectory $Distribution') -and $install.IndexOf('$status.ProjectMoved=Move-DawProjectDirectory $Distribution') -lt $install.IndexOf('/.vscode/settings.json')) 'An imported model moves before settings.json is edited'
        Assert ($install.Contains('if(-not $import){$status.ProjectMoved=Move-DawProjectDirectory $Distribution}') -and $install.LastIndexOf('Move-DawProjectDirectory') -lt $config) 'A kept distribution moves before the project is used'
        Assert ($install.Contains('Backup-DawWebRoot $Distribution (@($project)+@(Get-DawPreviousLinuxProjectPaths))')) 'A reinstall also saves www from the previous paths'
        Assert ($install.IndexOf('Remove-DawPreviousProjectLinks') -gt $install.IndexOf("'install-daw-commands.ps1'") -and $install.IndexOf('Remove-DawPreviousProjectLinks') -lt $install.IndexOf('New-DawShortcut')) 'The previous links go once the launchers point to ~/.daw'
        $update=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/update-project.ps1'))
        $move=$update.IndexOf('$status.ProjectMoved=Move-DawProjectDirectory $Distribution')
        Assert ($move -gt $update.IndexOf('Test-DawModelMarker $Distribution') -and $move -lt $update.IndexOf('Invoke-DawProjectOverlay')) 'UpdateProject moves the project before copying into it'
        & $script:M {$script:Calls=@();function script:Invoke-DawNative {param($File,$Arguments,$TimeoutSeconds) $script:Calls+=,@($Arguments);'moved'}}
        Assert (Move-DawProjectDirectory 'linux')
        $call=@(& $script:M {$script:Calls})[0]
        Assert (($call[0..6] -join ' ') -eq '-d linux -u root --exec bash -c' -and (($call[-6..-1]) -join ' ') -ceq '/home/ad/.daw /home/ad/html /home/ad/data /home/ad/angular /home/ad/daw /home/ad/workspace') ($call -join ' ')
        $script=Get-DawProjectMoveScript
        Assert (-not $script.Contains("`r") -and $script.Contains('docker stop') -and $script.Contains('ln -s -- "$new" "$old"'))
        & $script:M {$script:Calls=@();function script:Invoke-DawNative {param($File,$Arguments,$TimeoutSeconds) $script:Calls+=,@($Arguments);'removed /home/ad/daw';'outra liña'}}
        Assert ((@(Remove-DawPreviousProjectLinks 'linux') -join ',') -ceq '/home/ad/daw')
        $call=@(& $script:M {$script:Calls})[0]
        Assert ((($call[-3..-1]) -join ' ') -ceq '/home/ad/.daw /home/ad/daw /home/ad/workspace' -and $call[2] -ceq '-u' -and $call[3] -ceq 'root') ($call -join ' ')
    }
    Test 'deployment scripts take the names from the module' {
        $literal='/home/ad/(\.daw|daw|workspace|html|data|angular)\b|ProgramData\\DAW-(Dev|Aula)|Local\\DAW-(Dev|Aula)|DAW-Aula-Tools|daw-php:8\.6|dwcs-php:8\.6-ad|install\.lock|install-state\.json|project-state\.json|daw-dev-model|daw-dev-v2|daw-aula-v1|daw-aula-modelo|linux\.tar\.gz'
        # activate.ps1 non carga o módulo; o seu texto de axuda nomea o cartafol de estado.
        foreach($f in Get-ChildItem (Join-Path $script:Repo 'windows/classroom') -File -Include *.ps1,*.sh -Recurse|Where-Object {$_.Name -ne 'activate.ps1'}){
            $hits=@(Select-String -LiteralPath $f.FullName -Pattern $literal|Where-Object {$_.Line -notmatch '^\s*#'})
            Assert ($hits.Count -eq 0) ("$($f.Name): "+(($hits|ForEach-Object {$_.LineNumber}) -join ','))
        }
        $module=@([IO.File]::ReadAllLines($script:ModulePath)|Select-String -Pattern $literal|Where-Object {$_.Line -notmatch '^\s*#|^function Get-Daw|^\s+\[pscustomobject\]@\{Lock=|^\s+(PackageDirectory|Distribution|RunValue)='})
        Assert ($module.Count -eq 0) ('daw-classroom.psm1: '+(($module|ForEach-Object {$_.LineNumber}) -join ','))
    }
    Test 'manage.ps1 runs posts in parallel only for the bulk actions' {
        $f=Join-Path $script:Repo 'windows/classroom/manage.ps1'
        Throws {& $f -Action Status -Number 1 -ThrottleLimit 2} 'ThrottleLimit'
        Throws {& $f -Action UpdateProject -Number 1 -Reinstall} 'Reinstall só'
        Throws {& $f -Action InstallUser -Number 1 -Restart} 'Restart só'
        $t=[IO.File]::ReadAllText($f)
        foreach($s in 'Invoke-DawBoundedJobs $numbers $ThrottleLimit $worker $arguments','@($PSCommandPath,$Action'){Assert ($t.Contains($s)) "Missing: $s"}
        Assert (-not(Test-Path -LiteralPath (Join-Path $script:Repo 'windows/classroom/gestionar-aula-paralelo.ps1')))
    }
    Test 'model commands are links to scripts/daw.sh, which knows each name' {
        $setup=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/setup-model.sh'))
        Assert (-not $setup.Contains('daw-aula-command')) 'The model still writes daw-aula-command'
        Assert ($setup.Contains('ln -s "$project/scripts/daw.sh" "/usr/local/bin/$command"'))
        Assert ($setup.Contains('bash "$project/scripts/daw.sh" --list-commands --model')) 'setup-model.sh must read commands from daw.sh --list-commands --model'
        $daw=[IO.File]::ReadAllText((Join-Path $script:Repo 'scripts/daw.sh'))
        $modelNames=([regex]::Match($daw,"MODEL_COMMANDS='([^']+)'")).Groups[1].Value -split '\s+' | Where-Object { $_ }
        $linuxNames=([regex]::Match($daw,"LINUX_COMMANDS='([^']+)'")).Groups[1].Value -split '\s+' | Where-Object { $_ }
        Assert ($modelNames.Count -ge 9 -and $linuxNames.Count -ge 15) 'Missing command lists in daw.sh'
        foreach($n in @($modelNames)+@($linuxNames)|Sort-Object -Unique){
            Assert ($daw -match ('(?m)^\s+(\S+\|)*'+[regex]::Escape($n)+'(\|\S+)*\)')) "daw.sh does not handle $n"
        }
        $winInstall=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/install-daw-commands.ps1'))
        foreach($n in $linuxNames|Where-Object { $_ -like 'daw-*' -and $_ -ne 'daw-publicar' }){
            Assert ($winInstall.Contains("'$n' = ")) "Windows install-daw-commands.ps1 is missing $n"
        }
    }
    Test 'Windows Angular SSH config uses isolated known_hosts, updates ports and syncs host key' {
        $dawPath=Join-Path $script:Repo 'windows/daw.ps1'
        $ast=[Management.Automation.Language.Parser]::ParseFile($dawPath,[ref]$null,[ref]$null)
        foreach($fnName in 'Initialize-AngularKey','Sync-AngularHostKey'){
            $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fnName},$false)
            Assert ($null -ne $fn) "Missing $fnName"
            . ([scriptblock]::Create($fn.Extent.Text))
        }
        $saved=$env:DAW_SSH_DIR
        try{
            $sshDir=Join-Path $script:Temp 'win-angular-ssh'
            New-Item -ItemType Directory -Path $sshDir -Force|Out-Null
            $env:DAW_SSH_DIR=$sshDir
            # Pre-create dummy public key so the test does not depend on ssh-keygen.exe on Linux.
            $fakeKey='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA dwcc-angular'
            [IO.File]::WriteAllText((Join-Path $sshDir 'dwcc_angular.pub'),$fakeKey,(New-Object Text.UTF8Encoding($false)))
            $pub=Initialize-AngularKey -Port '2222'
            Assert ($pub -eq $fakeKey)
            $cfg=[IO.File]::ReadAllText((Join-Path $sshDir 'config'))
            Assert ($cfg.Contains('# >>> DAW DEV ANGULAR >>>') -and $cfg.Contains('Port 2222') -and $cfg.Contains('HostKeyAlias dwcc-angular') -and $cfg.Contains('UserKnownHostsFile')) $cfg
            # Port change updates the managed block without duplicating it.
            $null=Initialize-AngularKey -Port '2299'
            $cfg2=[IO.File]::ReadAllText((Join-Path $sshDir 'config'))
            Assert (([regex]::Matches($cfg2,'Host dwcc-angular')).Count -eq 1 -and $cfg2.Contains('Port 2299') -and -not $cfg2.Contains('Port 2222')) $cfg2
            # Legacy unmarked block is upgraded while preserving other hosts.
            $legacy="Host dwcc-angular`r`n    HostName 127.0.0.1`r`n    Port 2222`r`n    User node`r`n    IdentityFile ~/.ssh/dwcc_angular`r`n    IdentitiesOnly yes`r`n`r`nHost deb`r`n    HostName 192.168.56.200`r`n"
            [IO.File]::WriteAllText((Join-Path $sshDir 'config'),$legacy,(New-Object Text.UTF8Encoding($false)))
            $null=Initialize-AngularKey -Port '2244'
            $cfg3=[IO.File]::ReadAllText((Join-Path $sshDir 'config'))
            Assert (([regex]::Matches($cfg3,'Host dwcc-angular')).Count -eq 1 -and $cfg3.Contains('Port 2244') -and $cfg3.Contains('HostKeyAlias dwcc-angular') -and $cfg3.Contains('Host deb')) $cfg3
            # Custom Host dwcc-angular is preserved untouched.
            $custom="Host dwcc-angular`r`n    HostName 10.1.2.3`r`n    User someone`r`n"
            [IO.File]::WriteAllText((Join-Path $sshDir 'config'),$custom,(New-Object Text.UTF8Encoding($false)))
            $null=Initialize-AngularKey -Port '2255'
            Assert ([IO.File]::ReadAllText((Join-Path $sshDir 'config')) -ceq $custom)
            # Sync-AngularHostKey writes known_hosts.d/dwcc-angular and rejects malformed keys.
            $hk='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
            Sync-AngularHostKey $hk
            $khPath=Join-Path (Join-Path $sshDir 'known_hosts.d') 'dwcc-angular'
            Assert ([IO.File]::ReadAllText($khPath) -ceq "dwcc-angular $hk`n")
            Throws { Sync-AngularHostKey 'invalid-key' } 'Unexpected format'
        }finally{$env:DAW_SSH_DIR=$saved}
    }
    Test 'launchers use the DAW-Dev package and the classroom VS Code cache on any distribution' {
        $daw=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/daw.ps1'))
        Assert (-not $daw.Contains('Debian-DAW')) 'Distribution-specific VS Code cache'
        Assert (-not $daw.Contains('$env:ProgramData')) 'ProgramData is null outside Windows'
        Assert ($daw.Contains("'C:\ProgramData\DAW-Dev'") -and $daw.Contains("Join-Path `$package 'activate.ps1'"))
        Assert ($daw.Contains("'--exec', 'bash', 'scripts/keep-alive.sh'") -and -not $daw.Contains('wsl/keep-alive.sh'))
        Assert ($daw.Contains("EndsWith('/.daw')) { '../angular' } else { 'angular' }")) 'start-frontend must not create ~/.daw/angular in classroom layout'
        $shim=[IO.File]::ReadAllText((Join-Path $script:Repo 'wsl/daw.ps1'))
        Assert ($shim.Contains("'install-daw-commands.ps1') -Distribution `$Distribution") -and $shim.Contains("'daw.ps1') @PSBoundParameters"))
    }
    Test 'daw-code -Container builds a WSL Dev Container URI for any distribution and workspace' {
        $dawPath=Join-Path $script:Repo 'windows/daw.ps1'
        $ast=[Management.Automation.Language.Parser]::ParseFile($dawPath,[ref]$null,[ref]$null)
        $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-DawWslDevContainerUri'},$false)
        Assert ($null -ne $fn) 'Missing Get-DawWslDevContainerUri'
        . ([scriptblock]::Create($fn.Extent.Text))
        $uri=Get-DawWslDevContainerUri '\\wsl.localhost\linux\home\ad\html' '/home/ad/html/' '/home/ad/html/'
        Assert ($uri -match '^vscode-remote://dev-container\+([0-9a-f]+)(/home/ad/html)$') "Unexpected URI: $uri"
        $hex=$Matches[1]
        $bytes=for($i=0;$i -lt $hex.Length;$i+=2){[Convert]::ToByte($hex.Substring($i,2),16)}
        $payload=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
        Assert ($payload.hostPath -ceq '\\wsl.localhost\linux\home\ad\html' -and $payload.localDocker -eq $false) ($payload|ConvertTo-Json -Compress)
        Assert ($payload.configFile.'$mid' -eq 1 -and $payload.configFile.path -ceq '/home/ad/html/.devcontainer/devcontainer.json' -and $payload.configFile.scheme -ceq 'vscode-fileHost') ($payload|ConvertTo-Json -Compress)
        $custom=Get-DawWslDevContainerUri '\\wsl.localhost\Debian\home\ad\proxectos\daw-dev' '/home/ad/proxectos/daw-dev' '/home/ad/daw'
        Assert ($custom -match '^vscode-remote://dev-container\+[0-9a-f]+/home/ad/daw$') "Unexpected custom URI: $custom"
        $daw=[IO.File]::ReadAllText($dawPath)
        Assert (-not $daw.Contains("'DAW-Dev'") -and $daw.Contains('Get-DawWslDevContainerUri'))
    }
    Test 'Xdebug maps the Apache web root to the workspace, in the repository and in the classroom' {
        $repo=[IO.File]::ReadAllText((Join-Path $script:Repo '.vscode/launch.json'))
        Assert ($repo.Contains('"/var/www/html": "${workspaceFolder}/www"') -and -not $repo.Contains('/home/ad/html'))
        # In the classroom the workspace is ~/html itself, in WSL and in the Dev Container.
        $aula=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/overlay/html/.vscode/launch.json'))
        Assert ($aula.Contains('"/var/www/html": "${workspaceFolder}"'))
        $override=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/overlay/compose.override.yaml'))
        foreach($s in '- ../html:/var/www/html','- ../html:/home/ad/html','- ../data:/home/ad/data','- ../angular:/home/node/proxectos'){Assert ($override.Contains($s)) "Missing in the override: $s"}
        Assert (-not $override.Contains('- ./data:') -and -not $override.Contains('000-default.conf'))
    }
    Test 'project updater validates package and origin BEFORE copying' {
        $t=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/update-project.ps1'))
        $package=$t.IndexOf('Assert-DawProjectOverlay $PackageDirectory');$origin=$t.IndexOf('Test-DawModelMarker $Distribution');$copy=$t.IndexOf('Invoke-DawProjectOverlay')
        Assert ($package -gt 0 -and $package -lt $origin -and $origin -lt $copy)
        # A activación recrea web se cambiou a súa definición (A31EQ28: Dev Containers reutilizaba
        # o contedor creado co compose.override.yaml anterior, sen post_start).
        Assert ($t -match '\$webChanged=.*compose\.override\.yaml.*docker/\*.*\.devcontainer/\*' -and $t.Contains('if($Restart -or ($RestartIfChanged -and $webChanged.Count)){$status.Restarted=Restart-DawProjectWeb $Distribution}')) 'RestartIfChanged'
        $activate=[IO.File]::ReadAllText((Join-Path $script:Repo 'windows/classroom/activate.ps1'))
        Assert ($activate.Contains("'update-project.ps1') -PackageDirectory `$stage -RestartIfChanged")) 'The activation must recreate a stale web container'
        $bash=Get-DawProjectOverlayScript
        Assert (-not $bash.Contains("`r")) 'Bash must receive LF even from CRLF Windows source'
        Assert ($bash -notmatch 'rm -rf|rm -r |chown|down -v|prune|--unregister|wsl --terminate')
    }
    Test 'overlay copy passes path triples and must report every file' {
        $manifest=[pscustomobject]@{Files=@([pscustomobject]@{Path='compose.override.yaml';Sha256='A'*64;Mode='Replace'},[pscustomobject]@{Path='data/README.txt';Sha256='B'*64;Mode='CreateOnly'})}
        & $script:M {
            $script:Lines=@('substituido compose.override.yaml','conservado data/README.txt','copia /home/ad/.daw/.daw-backup/x','');$script:Passed=$null
            function script:Invoke-DawNative {param($File,$Arguments) $script:Passed=$Arguments;$script:Lines}
        }
        $r=Invoke-DawProjectOverlay 'linux' 'C:\ProgramData\DAW-Dev\project' $manifest
        Assert ((@($r.Replaced) -join ',') -eq 'compose.override.yaml' -and (@($r.Kept) -join ',') -eq 'data/README.txt' -and $r.Backup -like '*/.daw-backup/x')
        $passed=& $script:M {,$script:Passed}
        Assert (($passed[0..7] -join ' ') -eq '-d linux -u ad --cd /home/ad/.daw --exec bash')
        Assert ($passed[-6] -eq 'compose.override.yaml' -and $passed[-5] -eq ('a'*64) -and $passed[-4] -eq 'Replace' -and $passed[-1] -eq 'CreateOnly')
        & $script:M {$script:Lines=@('igual compose.override.yaml')}
        Throws {Invoke-DawProjectOverlay 'linux' 'C:\ProgramData\DAW-Dev\project' $manifest} 'non informou'
    }
    # The installer and the project updater share the task runner; both must keep its guarantees.
    foreach($kind in @('install','project','verify')){
    foreach($mode in @('success','stale','corrupt','failure','policy','silent')){
        Test "student task correlation and cleanup: $kind $mode" {
            $root=Join-Path $script:Temp ('task-'+$kind+'-'+$mode)
            New-Item -ItemType Directory -Path (Join-Path $root 'AppData/Local/DAW-Dev') -Force|Out-Null
            & $script:M {
                param($root,$mode,$kind)
                $script:Profile=$root;$script:Mode=$mode;$script:Trace=@();$script:Principal=$null;$script:Command=''
                $script:StateFile=@{install='install-state.json';project='project-state.json';verify='verify-state.json'}[$kind]
                function script:Get-DawStudent {[pscustomobject]@{SID='S-1-5-21-123';Profile=$script:Profile}}
                function script:Assert-DawProjectOverlay {param($Directory) if($Directory -ne 'C:\ProgramData\DAW-Dev\project'){throw 'Unexpected stage'};[pscustomobject]@{Revision='r'}}
                function script:Test-Path {param($LiteralPath) if($LiteralPath -in @('C:\ProgramData\DAW-Dev\daw-classroom.psm1','C:\ProgramData\DAW-Dev\verify-user.ps1')){return $true};Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath}
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
                    $path=Join-Path $script:Profile ('AppData/Local/DAW-Dev/'+$script:StateFile)
                    if($script:Mode -eq 'corrupt'){[IO.File]::WriteAllText($path,'{torn json')}else{Write-DawState $path $state}
                }
                function script:Get-ScheduledTaskInfo {param($TaskName) [pscustomobject]@{LastRunTime=if($script:Mode -in @('policy','silent')){Get-Date}else{[datetime]::MinValue};LastTaskResult=if($script:Mode -eq 'silent'){0}else{1}}}
                function script:Get-ScheduledTask {param($TaskName) [pscustomobject]@{State='Ready'}}
                function script:Stop-ScheduledTask {param($TaskName,$ErrorAction) $script:Trace+='stopped'}
                function script:Unregister-ScheduledTask {param($TaskName,$Confirm,$ErrorAction) $script:Trace+='removed'}
            } $root $mode $kind
            $call=@{install={Invoke-DawStudentInstall 1};project={Invoke-DawProjectUpdate 1 -Restart};verify={Invoke-DawStudentVerify 1}}[$kind]
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
                        $call=@{install={Invoke-DawStudentInstall 30};project={Invoke-DawProjectUpdate 30 -Restart};verify={Invoke-DawStudentVerify 30}}[$kind]
                        Throws $call 'rematou sen informar'
                    }
                }
            }finally{$env:SystemRoot=$old}
            Assert ((& $script:M {$script:Execute}) -match 'conhost\.exe$' -and (& $script:M {$script:Command}) -match '^--headless "') 'Task must run in headless conhost'
            $principal=& $script:M {$script:Principal}
            Assert ($principal.User -eq 'S-1-5-21-123' -and $principal.Logon -eq 'Interactive' -and $principal.Level -eq 'Limited')
            Assert (((& $script:M {$script:Trace}) -join ',') -eq 'registered,started,stopped,removed')
            $decoded=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(((& $script:M {$script:Command}) -split ' ')[-1]))
            $expected=if($kind -eq 'verify'){"^& 'C:\\ProgramData\\DAW-Dev\\verify-user\.ps1' -RequestId '[0-9a-f]{32}' -ExpectedUserSid 'S-1-5-21-123' -PackageDirectory 'C:\\ProgramData\\DAW-Dev'$"}elseif($kind -eq 'install'){"^& 'C:\\ProgramData\\DAW-Dev\\install-user\.ps1' -RequestId '[0-9a-f]{32}' -ExpectedUserSid 'S-1-5-21-123' -PackageDirectory 'C:\\ProgramData\\DAW-Dev'$"}else{"^& 'C:\\ProgramData\\DAW-Dev\\project\\update-project\.ps1' -RequestId '[0-9a-f]{32}' -ExpectedUserSid 'S-1-5-21-123' -PackageDirectory 'C:\\ProgramData\\DAW-Dev\\project' -Restart$"}
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
}finally{Remove-Module daw-classroom -Force -ErrorAction SilentlyContinue;Remove-Item -LiteralPath $script:Temp -Recurse -Force}
