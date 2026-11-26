#requires -Version 5.1
<#
.SYNOPSIS
Desprega DAW Dev desde o equipo 100. Por defecto aula 34, equipos 1-35.
.DESCRIPTION
Comprobar: só diagnóstico. HabilitarWinRM: bootstrap con PsExec asinado de Microsoft.
PrepararWSL: características + MSI oficial (non reinicia). CopiarModelo: copia local
protexida e baixo demanda (AutoInicio opt-in). InstalarUsuario: tarefa sen
elevación na sesión activa. ActualizarProxecto: copia windows\classroom\overlay no
proxecto da Debian do alumno conectado, sen tocar www (Reiniciar recrea o contedor
web se está en marcha). Estado: consulta logs por perfil. Non almacena contrasinais.
ThrottleLimit atende ata ese número de postos á vez en PrepararWSL, CopiarModelo e
ActualizarProxecto; por defecto, un tras outro.
.EXAMPLE
.\manage.ps1 -Action Comprobar -Aula 31 -Numero 1
.EXAMPLE
.\manage.ps1 -Action HabilitarWinRM -Aula 31 -Numero 1
.EXAMPLE
.\manage.ps1 -Action ActualizarProxecto -Aula 34 -Numero 16
.EXAMPLE
.\manage.ps1 -Action CopiarModelo -Aula 34 -Numero (1..35) -ThrottleLimit 5 -PackageDirectory C:\DAW-Paquete-2026
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Comprobar','HabilitarWinRM','PrepararWSL','CopiarModelo','InstalarUsuario','ActualizarProxecto','Estado','Apagar')]
    [string]$Action,
    [ValidateRange(1,254)][int]$Aula = 34,
    [ValidateRange(1,35)][int[]]$Numero = (1..35),
    [string]$Dominio = 'iesrodolfoucha.es',
    [string]$PackageDirectory,
    [string]$WslMsi,
    [switch]$AutoInicio,
    [switch]$AdoptarExistente,
    [switch]$SenVSCode,
    [switch]$Reiniciar,
    [ValidateRange(5,7200)][int]$TimeoutSeconds=1800,
    [ValidateRange(1,10)][int]$ThrottleLimit = 1,
    [string]$PsExecPath = (Join-Path $env:LOCALAPPDATA 'DAW-Aula-Tools\PsExec64.exe')
)
$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'
Import-Module (Join-Path $PSScriptRoot 'daw-aula.psm1') -Force
if ($ThrottleLimit -gt 1 -and $Action -notin @('PrepararWSL','CopiarModelo','ActualizarProxecto')) {
    throw 'ThrottleLimit só se usa con PrepararWSL, CopiarModelo e ActualizarProxecto.'
}
if ($Action -eq 'Comprobar') {
    & (Join-Path $PSScriptRoot 'check-remote.ps1') -Aula $Aula -Numero $Numero -Dominio $Dominio
    return
}
if ($Action -eq 'Apagar') {
    & (Join-Path $PSScriptRoot 'power-off.ps1') -Aula $Aula -Numero $Numero -Dominio $Dominio
    return
}
function Assert-MicrosoftSignature([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw "Sinatura Microsoft non válida: $Path"
    }
}
if ($Action -eq 'HabilitarWinRM') {
    if (-not (Test-Path -LiteralPath $PsExecPath)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $PsExecPath) -Force | Out-Null
        Invoke-WebRequest -UseBasicParsing -Uri 'https://live.sysinternals.com/PsExec64.exe' -OutFile $PsExecPath
    }
    Assert-MicrosoftSignature $PsExecPath
}
if ($Action -eq 'PrepararWSL') {
    if (-not $WslMsi) {
        $release = Invoke-RestMethod 'https://api.github.com/repos/microsoft/WSL/releases/latest'
        $asset = $release.assets | Where-Object name -like '*.x64.msi' | Select-Object -First 1
        if (-not $asset) { throw 'Non se atopou o MSI x64 oficial de WSL.' }
        $cache = Join-Path $env:LOCALAPPDATA 'DAW-Aula-Tools'
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
if ($Action -eq 'CopiarModelo') {
    if (-not $PackageDirectory) { throw 'Indica -PackageDirectory.' }
    foreach ($file in $files) {
        if (-not (Test-Path -LiteralPath (Join-Path $PackageDirectory $file) -PathType Leaf)) { throw "Falta $file no paquete." }
    }
    $manifest = Assert-DawPackage $PackageDirectory
    $files += $manifest.Image
    $files += @(Get-DawPackageImages $manifest | ForEach-Object { $_.File })
}
$numbers = @($Numero | Sort-Object -Unique)
if ($ThrottleLimit -gt 1 -and $numbers.Count -gt 1) {
    # Cada posto nunha execución propia deste script, con ThrottleLimit execucións á vez.
    $worker = {
        param($n,$script,$action,$aula,$domain,$package,$msi,$auto,$restart,$seconds)
        $ErrorActionPreference = 'Stop'
        try {
            $data = @(& $script -Action $action -Aula $aula -Numero @($n) -Dominio $domain -PackageDirectory $package -WslMsi $msi -AutoInicio:$auto -Reiniciar:$restart -TimeoutSeconds $seconds)
            $records = @($data | Where-Object { $_ -and $_.PSObject.Properties['Success'] -and $_.PSObject.Properties['Equipo'] })
            if ($records.Count -ne 1) { throw 'Resposta ausente ou ambigua do xestor.' }
            $records[0]
        } catch { [pscustomobject]@{ Equipo = ('A{0}EQ{1:D2}.{2}' -f $aula,$n,$domain); Action = $action; Success = $false; Error = $_.Exception.Message; Data = $null } }
    }
    $arguments = @($PSCommandPath,$Action,$Aula,$Dominio,$PackageDirectory,$WslMsi,$AutoInicio.IsPresent,$Reiniciar.IsPresent,$TimeoutSeconds)
    $result = @(Invoke-DawBoundedJobs $numbers $ThrottleLimit $worker $arguments)
    if ($result.Count -ne $numbers.Count) { throw 'Faltan resultados dalgúns postos. Non se declara éxito.' }
    return $result
}
$projectStage = $null
if ($Action -in @('ActualizarProxecto','CopiarModelo')) {
    # Preparado unha vez no profesor: ficheiros do proxecto, actualizador e módulo, con SHA256.
    # CopiarModelo tamén os deixa no equipo para a activación manual (activar-dawdev.ps1).
    $projectStage = Join-Path ([IO.Path]::GetTempPath()) ('daw-proxecto-' + [guid]::NewGuid().ToString('N'))
    $projectManifest = New-DawProjectStage $PSScriptRoot $projectStage
    $moduleSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'daw-aula.psm1'))
}
foreach ($n in $Numero) {
    $computer = 'A{0}EQ{1:D2}.{2}' -f $Aula,$n,$Dominio
    $address = "172.21.$Aula.$n"
    $session = $null
    $details = $null
    try {
        switch ($Action) {
            'HabilitarWinRM' {
                Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'enable-winrm.ps1') -Destination "\\$computer\admin$\Temp\daw-enable-winrm.ps1" -Force
                $previousPreference = $ErrorActionPreference
                $ErrorActionPreference = 'Continue'
                try {
                    & $PsExecPath "\\$computer" -accepteula -nobanner -n 10 -r DAWAulaBootstrap -s powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\Windows\Temp\daw-enable-winrm.ps1 -ProfesorIP "172.21.$Aula.100" 2>&1 | ForEach-Object { "$_" }
                    $bootstrapExit = $LASTEXITCODE
                } finally { $ErrorActionPreference = $previousPreference }
                if ($bootstrapExit -ne 0) { throw "PsExec rematou con $bootstrapExit." }
                $null = Test-WSMan -ComputerName $computer -ErrorAction Stop
            }
            default {
                $session = New-PSSession -ComputerName $computer -Authentication Kerberos
                switch ($Action) {
                    'InstalarUsuario' {
                        $details = Invoke-Command -Session $session -ScriptBlock {
                            param($seconds,$adopt,$withoutCode)
                            Import-Module 'C:\ProgramData\DAW-Aula\daw-aula.psm1' -Force
                            Invoke-DawStudentInstall -TimeoutSeconds $seconds -AdoptExisting:$adopt -WithoutCode:$withoutCode
                        } -ArgumentList $TimeoutSeconds,$AdoptarExistente.IsPresent,$SenVSCode.IsPresent
                        if (-not $details -or -not $details.Success) { throw 'Non se confirmou a instalación da solicitude actual.' }
                    }
                    'ActualizarProxecto' {
                        # O módulo cárgase desde un ficheiro temporal do administrador. Con New-Module,
                        # todos os postos da aula 34 rexeitaron o bloque (ParameterBindingException,
                        # 18-11-2026); a causa non se aclarou.
                        Invoke-Command -Session $session -ScriptBlock {
                            param($source)
                            $file = Join-Path $env:TEMP ('daw-aula-' + [guid]::NewGuid().ToString('N') + '.psm1')
                            try { [IO.File]::WriteAllText($file, $source, (New-Object Text.UTF8Encoding($true))); Import-Module $file -Force }
                            finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
                            Initialize-DawProjectDirectory
                        } -ArgumentList $moduleSource
                        # SMB como en CopiarModelo; o paquete do proxecto ocupa poucos KB.
                        Copy-Item -Path (Join-Path $projectStage '*') -Destination "\\$computer\c$\ProgramData\DAW-Aula\proxecto\" -Recurse -Force
                        $details = Invoke-Command -Session $session -ScriptBlock {
                            param($seconds,$restart)
                            # O módulo segue cargado na mesma sesión desde a primeira chamada.
                            Reset-DawProjectAcl
                            Invoke-DawProjectUpdate -TimeoutSeconds $seconds -Restart:$restart
                        } -ArgumentList $TimeoutSeconds,$Reiniciar.IsPresent
                        if (-not $details -or -not $details.Success -or $details.Revision -ne $projectManifest.Revision) { throw 'Non se confirmou a actualización do proxecto da solicitude actual.' }
                    }
                    'PrepararWSL' {
                        $remoteMsi = 'C:\Windows\Temp\daw-wsl.x64.msi'
                        Copy-Item -LiteralPath $WslMsi -Destination $remoteMsi -ToSession $session -Force
                        $script = Join-Path (Split-Path -Parent $PSScriptRoot) 'install-wsl.ps1'
                        $details = Invoke-Command -Session $session -FilePath $script -ArgumentList $remoteMsi
                        Write-Host "[$computer] Non se reiniciou automaticamente. Revisa RestartRequired."
                    }
                    'CopiarModelo' {
                        $moduleSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'daw-aula.psm1'))
                        Invoke-Command -Session $session -ScriptBlock {
                            param($source)
                            New-Module -ScriptBlock ([scriptblock]::Create($source)) | Import-Module -Force
                            # Prevent a new logon from starting the old installer during package replacement.
                            Set-DawAutoStart
                            foreach ($profile in Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special }) {
                                $lockPath = Join-Path $profile.LocalPath 'AppData\Local\DAW-Aula\instalacion.lock'
                                if (Test-Path -LiteralPath $lockPath) {
                                    try { $handle=[IO.File]::Open($lockPath,'Open','ReadWrite','None'); $handle.Dispose() }
                                    catch { throw ("Bloqueo de instalación non dispoñible ({0}): {1}. Revisar antes de copiar." -f $lockPath,$_.Exception.Message) }
                                }
                            }
                            $target = 'C:\ProgramData\DAW-Aula'
                            if (Test-Path -LiteralPath $target) {
                                $items = @((Get-Item -LiteralPath $target -Force)) + @(Get-ChildItem -LiteralPath $target -Recurse -Force)
                                if ($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw 'O destino contén ligazóns ou junctions.' }
                            }
                            New-Item -ItemType Directory -Path $target -Force | Out-Null
                            $acl = New-Object Security.AccessControl.DirectorySecurity
                            $acl.SetAccessRuleProtection($true,$false)
                            $admins = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
                            $acl.SetOwner($admins)
                            foreach ($sid in 'S-1-5-18','S-1-5-32-544','S-1-5-32-545') {
                                $rights = if ($sid -eq 'S-1-5-32-545') { 'ReadAndExecute' } else { 'FullControl' }
                                $identity = New-Object Security.Principal.SecurityIdentifier($sid)
                                $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity,$rights,'ContainerInherit,ObjectInherit','None','Allow')
                                $acl.AddAccessRule($rule)
                            }
                            Set-Acl -LiteralPath $target -AclObject $acl
                            Get-ChildItem -LiteralPath $target -File | ForEach-Object {
                                $fileAcl = New-Object Security.AccessControl.FileSecurity
                                $fileAcl.SetAccessRuleProtection($false,$false)
                                $fileAcl.SetOwner($admins)
                                Set-Acl -LiteralPath $_.FullName -AclObject $fileAcl
                            }
                        } -ArgumentList $moduleSource
                        foreach ($file in $files) {
                            # SMB desde o profesor evita o custo de serializar un tar grande por WinRM.
                            Copy-Item -LiteralPath (Join-Path $PackageDirectory $file) -Destination "\\$computer\c$\ProgramData\DAW-Aula\$file" -Force
                        }
                        Invoke-Command -Session $session -ScriptBlock {
                            param($enableAuto)
                            $target = 'C:\ProgramData\DAW-Aula'
                            # Elimina ACL explícitas herdadas dunha copia anterior en cada ficheiro.
                            Get-ChildItem -LiteralPath $target -File | ForEach-Object {
                                $acl = New-Object Security.AccessControl.FileSecurity
                                $acl.SetAccessRuleProtection($false,$false)
                                $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
                                Set-Acl -LiteralPath $_.FullName -AclObject $acl
                            }
                            Import-Module (Join-Path $target 'daw-aula.psm1') -Force
                            Assert-DawPackage $target | Out-Null
                            Set-DawAutoStart -Enabled:$enableAuto
                            Initialize-DawProjectDirectory
                        } -ArgumentList $AutoInicio.IsPresent
                        # Ficheiros do proxecto e entrada do menú Inicio: cada usuario activa DAW Dev
                        # cando o necesita, sen que o docente teña que estar conectado.
                        Copy-Item -Path (Join-Path $projectStage '*') -Destination "\\$computer\c$\ProgramData\DAW-Aula\proxecto\" -Recurse -Force
                        $details = Invoke-Command -Session $session -ScriptBlock {
                            param($revision)
                            Reset-DawProjectAcl
                            $stage = Assert-DawProjectOverlay (Get-DawProjectDirectory)
                            if ($stage.Revision -ne $revision) { throw 'A revisión do proxecto copiado non coincide.' }
                            [pscustomobject]@{ Revision = $stage.Revision; Shortcut = Set-DawStartMenuShortcut }
                        } -ArgumentList $projectManifest.Revision
                    }
                    'Estado' {
                        $details = Invoke-Command -Session $session -ScriptBlock {
                            Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special } | ForEach-Object {
                                $path = Join-Path $_.LocalPath 'AppData\Local\DAW-Aula\estado.json'
                                if (Test-Path -LiteralPath $path) {
                                    $state = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
                                    [pscustomobject]@{ Profile = $_.LocalPath; User = $state.User; Success = $state.Success; Error = $state.Error; CheckedUtc = $state.CheckedUtc; RequestId = $state.RequestId; Phase = $state.Phase }
                                }
                            }
                        }
                    }
                }
            }
        }
        [pscustomobject]@{ Equipo = $computer; Action = $Action; Success = $true; Error = $null; Data = $details }
    } catch {
        [pscustomobject]@{ Equipo = $computer; Action = $Action; Success = $false; Error = $_.Exception.Message; Data = $null }
    } finally {
        if ($session) { Remove-PSSession $session }
    }
}
if ($projectStage) { Remove-Item -LiteralPath $projectStage -Recurse -Force -ErrorAction SilentlyContinue }
