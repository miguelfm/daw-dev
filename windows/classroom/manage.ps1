#requires -Version 5.1
<#
.SYNOPSIS
Desprega DAW Dev desde o equipo 100. Por defecto aula 34, equipos 1-35.
.DESCRIPTION
Check: só diagnóstico. EnableWinRM: bootstrap con PsExec asinado de Microsoft.
InstallWSL: características + MSI oficial (non reinicia). CopyPackage: copia local
protexida e baixo demanda (AutoStart opt-in); retira o paquete DAW-Aula anterior.
InstallUser: tarefa sen elevación na sesión activa (Reinstall substitúe e borra
unha distribución doutro paquete). UpdateProject: copia windows\classroom\overlay no
proxecto da conta conectada, sen tocar www (Restart recrea o contedor web se está en
marcha). Verify: comproba a contorna na conta conectada (web, MariaDB, documentación e VS Code
Server). Status: consulta logs por perfil. PowerOff: apaga a aula. Non almacena contrasinais.
deploy.ps1 encadea estas accións para toda a aula.
ThrottleLimit atende ata ese número de postos á vez en InstallWSL, CopyPackage, InstallUser,
Verify e UpdateProject; por defecto, un tras outro.
.EXAMPLE
.\manage.ps1 -Action Check -Classroom 31 -Number 1
.EXAMPLE
.\manage.ps1 -Action EnableWinRM -Classroom 31 -Number 1
.EXAMPLE
.\manage.ps1 -Action UpdateProject -Classroom 34 -Number 16
.EXAMPLE
.\manage.ps1 -Action CopyPackage -Classroom 34 -Number (1..35) -ThrottleLimit 5 -PackageDirectory C:\DAW-Paquete-2026
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Check','EnableWinRM','InstallWSL','CopyPackage','InstallUser','Verify','UpdateProject','Status','PowerOff')]
    [string]$Action,
    [ValidateRange(1,254)][int]$Classroom = 34,
    [ValidateRange(1,35)][int[]]$Number = (1..35),
    [string]$Domain = 'iesrodolfoucha.es',
    [string]$PackageDirectory,
    [string]$WslMsi,
    [switch]$AutoStart,
    [switch]$Reinstall,
    [switch]$SkipVSCode,
    [switch]$Restart,
    [ValidateRange(5,7200)][int]$TimeoutSeconds=1800,
    [ValidateRange(1,10)][int]$ThrottleLimit = 1,
    # Por defecto, PsExec64.exe en Get-DawToolsDirectory.
    [string]$PsExecPath
)
$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'
Import-Module (Join-Path $PSScriptRoot 'daw-classroom.psm1') -Force
if ($ThrottleLimit -gt 1 -and $Action -notin @('InstallWSL','CopyPackage','InstallUser','Verify','UpdateProject')) {
    throw 'ThrottleLimit só se usa con InstallWSL, CopyPackage, InstallUser, Verify e UpdateProject.'
}
# Reinstall borra a distribución da conta e Restart só recrea o contedor web: non se confunden.
if ($Reinstall -and $Action -ne 'InstallUser') { throw 'Reinstall só se usa con InstallUser.' }
if ($Restart -and $Action -ne 'UpdateProject') { throw 'Restart só se usa con UpdateProject.' }
if ($Action -eq 'Check') {
    & (Join-Path $PSScriptRoot 'check-remote.ps1') -Classroom $Classroom -Number $Number -Domain $Domain
    return
}
if ($Action -eq 'PowerOff') {
    & (Join-Path $PSScriptRoot 'power-off.ps1') -Classroom $Classroom -Number $Number -Domain $Domain
    return
}
function Assert-MicrosoftSignature([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw "Sinatura Microsoft non válida: $Path"
    }
}
if ($Action -eq 'EnableWinRM') {
    if (-not $PsExecPath) { $PsExecPath = Join-Path (Get-DawToolsDirectory) 'PsExec64.exe' }
    if (-not (Test-Path -LiteralPath $PsExecPath)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $PsExecPath) -Force | Out-Null
        Invoke-WebRequest -UseBasicParsing -Uri 'https://live.sysinternals.com/PsExec64.exe' -OutFile $PsExecPath
    }
    Assert-MicrosoftSignature $PsExecPath
}
if ($Action -eq 'InstallWSL') {
    if (-not $WslMsi) {
        $release = Invoke-RestMethod 'https://api.github.com/repos/microsoft/WSL/releases/latest'
        $asset = $release.assets | Where-Object name -like '*.x64.msi' | Select-Object -First 1
        if (-not $asset) { throw 'Non se atopou o MSI x64 oficial de WSL.' }
        $cache = Get-DawToolsDirectory
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        $WslMsi = Join-Path $cache $asset.name
        if (-not (Test-Path -LiteralPath $WslMsi)) {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $WslMsi
        }
    }
    Assert-MicrosoftSignature $WslMsi
}
$files = @('manifest.json') + @(Get-DawSetupFiles)
if ($Action -eq 'CopyPackage') {
    if (-not $PackageDirectory) { throw 'Indica -PackageDirectory.' }
    foreach ($file in $files) {
        if (-not (Test-Path -LiteralPath (Join-Path $PackageDirectory $file) -PathType Leaf)) { throw "Falta $file no paquete." }
    }
    $manifest = Assert-DawPackage $PackageDirectory
    $files = Get-DawPackageFiles $manifest
}
$numbers = @($Number | Sort-Object -Unique)
if ($ThrottleLimit -gt 1 -and $numbers.Count -gt 1) {
    # Cada posto nunha execución propia deste script, con ThrottleLimit execucións á vez.
    $worker = {
        param($n,$script,$action,$classroom,$domain,$package,$msi,$auto,$restart,$seconds,$reinstall,$skipCode)
        $ErrorActionPreference = 'Stop'
        try {
            $data = @(& $script -Action $action -Classroom $classroom -Number @($n) -Domain $domain -PackageDirectory $package -WslMsi $msi -AutoStart:$auto -Restart:$restart -TimeoutSeconds $seconds -Reinstall:$reinstall -SkipVSCode:$skipCode)
            $records = @($data | Where-Object { $_ -and $_.PSObject.Properties['Success'] -and $_.PSObject.Properties['Computer'] })
            if ($records.Count -ne 1) { throw 'Resposta ausente ou ambigua do xestor.' }
            $records[0]
        } catch { [pscustomobject]@{ Computer = ('A{0}EQ{1:D2}.{2}' -f $classroom,$n,$domain); Action = $action; Success = $false; Error = $_.Exception.Message; Data = $null } }
    }
    $arguments = @($PSCommandPath,$Action,$Classroom,$Domain,$PackageDirectory,$WslMsi,$AutoStart.IsPresent,$Restart.IsPresent,$TimeoutSeconds,$Reinstall.IsPresent,$SkipVSCode.IsPresent)
    $result = @(Invoke-DawBoundedJobs $numbers $ThrottleLimit $worker $arguments)
    if ($result.Count -ne $numbers.Count) { throw 'Faltan resultados dalgúns postos. Non se declara éxito.' }
    return $result
}
$projectStage = $null
if ($Action -in @('UpdateProject','CopyPackage')) {
    # Preparado unha vez no profesor: ficheiros do proxecto, actualizador e módulo, con SHA256.
    # CopyPackage tamén os deixa no equipo para a activación manual (activate.ps1).
    $projectStage = Join-Path ([IO.Path]::GetTempPath()) ('daw-project-' + [guid]::NewGuid().ToString('N'))
    $projectManifest = New-DawProjectStage $PSScriptRoot $projectStage
    $moduleSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'daw-classroom.psm1'))
}
# Rutas nos postos e o seu equivalente desde o profesor por SMB (c$).
$packageDir = Get-DawPackageDirectory
$stageDir = Get-DawProjectDirectory
$installStateFile = Join-Path (Get-DawStateRelativePath) (Get-DawStateFiles).Install
foreach ($n in $Number) {
    $computer = 'A{0}EQ{1:D2}.{2}' -f $Classroom,$n,$Domain
    $remotePackage = ConvertTo-DawAdminSharePath $computer $packageDir
    $remoteStage = ConvertTo-DawAdminSharePath $computer $stageDir
    $address = "172.21.$Classroom.$n"
    $session = $null
    $details = $null
    try {
        switch ($Action) {
            'EnableWinRM' {
                Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'enable-winrm.ps1') -Destination "\\$computer\admin$\Temp\daw-enable-winrm.ps1" -Force
                $previousPreference = $ErrorActionPreference
                $ErrorActionPreference = 'Continue'
                try {
                    & $PsExecPath "\\$computer" -accepteula -nobanner -n 10 -r DAWAulaBootstrap -s powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\Windows\Temp\daw-enable-winrm.ps1 -TeacherIP "172.21.$Classroom.100" 2>&1 | ForEach-Object { "$_" }
                    $bootstrapExit = $LASTEXITCODE
                } finally { $ErrorActionPreference = $previousPreference }
                if ($bootstrapExit -ne 0) { throw "PsExec rematou con $bootstrapExit." }
                $null = Test-WSMan -ComputerName $computer -ErrorAction Stop
            }
            default {
                $session = New-PSSession -ComputerName $computer -Authentication Kerberos
                switch ($Action) {
                    'InstallUser' {
                        $details = Invoke-Command -Session $session -ScriptBlock {
                            param($seconds,$reinstall,$withoutCode,$package)
                            Import-Module (Join-Path $package 'daw-classroom.psm1') -Force
                            Invoke-DawStudentInstall -TimeoutSeconds $seconds -Reinstall:$reinstall -WithoutCode:$withoutCode
                        } -ArgumentList $TimeoutSeconds,$Reinstall.IsPresent,$SkipVSCode.IsPresent,$packageDir
                        if (-not $details -or -not $details.Success) { throw 'Non se confirmou a instalación da solicitude actual.' }
                    }
                    'Verify' {
                        $details = Invoke-Command -Session $session -ScriptBlock {
                            param($seconds,$package)
                            Import-Module (Join-Path $package 'daw-classroom.psm1') -Force
                            Invoke-DawStudentVerify -TimeoutSeconds $seconds
                        } -ArgumentList $TimeoutSeconds,$packageDir
                        if (-not $details -or -not $details.Success) { throw 'Non se confirmou a verificación da solicitude actual.' }
                    }
                    'UpdateProject' {
                        # O módulo cárgase desde un ficheiro temporal do administrador. Con New-Module,
                        # todos os postos da aula 34 rexeitaron o bloque (ParameterBindingException,
                        # 18-11-2026); a causa non se aclarou.
                        Invoke-Command -Session $session -ScriptBlock {
                            param($source)
                            $file = Join-Path $env:TEMP ('daw-classroom-' + [guid]::NewGuid().ToString('N') + '.psm1')
                            try { [IO.File]::WriteAllText($file, $source, (New-Object Text.UTF8Encoding($true))); Import-Module $file -Force }
                            finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
                            Initialize-DawProjectDirectory
                        } -ArgumentList $moduleSource
                        # SMB como en CopyPackage; o paquete do proxecto ocupa poucos KB.
                        Copy-Item -Path (Join-Path $projectStage '*') -Destination "$remoteStage\" -Recurse -Force
                        $details = Invoke-Command -Session $session -ScriptBlock {
                            param($seconds,$restart)
                            # O módulo segue cargado na mesma sesión desde a primeira chamada.
                            Reset-DawProjectAcl
                            Invoke-DawProjectUpdate -TimeoutSeconds $seconds -Restart:$restart
                        } -ArgumentList $TimeoutSeconds,$Restart.IsPresent
                        if (-not $details -or -not $details.Success -or $details.Revision -ne $projectManifest.Revision) { throw 'Non se confirmou a actualización do proxecto da solicitude actual.' }
                    }
                    'InstallWSL' {
                        $remoteMsi = 'C:\Windows\Temp\daw-wsl.x64.msi'
                        Copy-Item -LiteralPath $WslMsi -Destination $remoteMsi -ToSession $session -Force
                        $script = Join-Path (Split-Path -Parent $PSScriptRoot) 'install-wsl.ps1'
                        $details = Invoke-Command -Session $session -FilePath $script -ArgumentList $remoteMsi
                        Write-Host "[$computer] Non se reiniciou automaticamente. Revisa RestartRequired."
                    }
                    'CopyPackage' {
                        $moduleSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'daw-classroom.psm1'))
                        $removed = Invoke-Command -Session $session -ScriptBlock {
                            param($source)
                            New-Module -ScriptBlock ([scriptblock]::Create($source)) | Import-Module -Force
                            Initialize-DawPackageDirectory
                        } -ArgumentList $moduleSource
                        # SMB desde o profesor evita o custo de serializar un tar grande por WinRM.
                        $null = Copy-DawPackageFiles $PackageDirectory $remotePackage $files
                        Invoke-Command -Session $session -ScriptBlock {
                            param($enableAuto)
                            # O módulo do paquete copiado, coas mesmas funcións ca o do profesor.
                            Import-Module (Join-Path (Get-DawPackageDirectory) 'daw-classroom.psm1') -Force
                            Complete-DawPackage -AutoStart:$enableAuto
                        } -ArgumentList $AutoStart.IsPresent
                        # Ficheiros do proxecto e entrada do menú Inicio: cada usuario activa DAW Dev
                        # cando o necesita, sen que o docente teña que estar conectado.
                        Copy-Item -Path (Join-Path $projectStage '*') -Destination "$remoteStage\" -Recurse -Force
                        $details = Invoke-Command -Session $session -ScriptBlock {
                            param($revision)
                            Complete-DawProjectStage $revision
                        } -ArgumentList $projectManifest.Revision
                        $details | Add-Member NoteProperty Removed @($removed)
                    }
                    'Status' {
                        $details = Invoke-Command -Session $session -ScriptBlock {
                            param($stateFile)
                            Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special } | ForEach-Object {
                                $path = Join-Path $_.LocalPath $stateFile
                                if (Test-Path -LiteralPath $path) {
                                    $state = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
                                    [pscustomobject]@{ Profile = $_.LocalPath; User = $state.User; Success = $state.Success; Error = $state.Error; CheckedUtc = $state.CheckedUtc; RequestId = $state.RequestId; Phase = $state.Phase; CodeServer = $state.CodeServer }
                                }
                            }
                        } -ArgumentList $installStateFile
                    }
                }
            }
        }
        [pscustomobject]@{ Computer = $computer; Action = $Action; Success = $true; Error = $null; Data = $details }
    } catch {
        [pscustomobject]@{ Computer = $computer; Action = $Action; Success = $false; Error = $_.Exception.Message; Data = $null }
    } finally {
        if ($session) { Remove-PSSession $session }
    }
}
if ($projectStage) { Remove-Item -LiteralPath $projectStage -Recurse -Force -ErrorAction SilentlyContinue }
