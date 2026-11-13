#requires -Version 5.1
<#
.SYNOPSIS
Desprega DAW Dev desde o equipo 100. Por defecto aula 34, equipos 1-35.
.DESCRIPTION
Comprobar: só diagnóstico. HabilitarWinRM: bootstrap con PsExec asinado de Microsoft.
PrepararWSL: características + MSI oficial (non reinicia). CopiarModelo: copia local
protexida e baixo demanda (AutoInicio opt-in). InstalarUsuario: tarefa sen
elevación na sesión activa. Estado: consulta logs por perfil. Non almacena contrasinais.
.EXAMPLE
.\gestionar-aula.ps1 -Action Comprobar -Aula 31 -Numero 1
.EXAMPLE
.\gestionar-aula.ps1 -Action HabilitarWinRM -Aula 31 -Numero 1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Comprobar','HabilitarWinRM','PrepararWSL','CopiarModelo','InstalarUsuario','Estado','Apagar')]
    [string]$Action,
    [ValidateRange(1,254)][int]$Aula = 34,
    [ValidateRange(1,35)][int[]]$Numero = (1..35),
    [string]$Dominio = 'iesrodolfoucha.es',
    [string]$PackageDirectory,
    [string]$WslMsi,
    [switch]$AutoInicio,
    [switch]$AdoptarExistente,
    [switch]$SenVSCode,
    [ValidateRange(5,7200)][int]$TimeoutSeconds=1800,
    [string]$PsExecPath = (Join-Path $env:LOCALAPPDATA 'DAW-Aula-Tools\PsExec64.exe')
)
$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'
Import-Module (Join-Path $PSScriptRoot 'daw-aula.psm1') -Force
if ($Action -eq 'Comprobar') {
    & (Join-Path $PSScriptRoot 'comprobar-remoto.ps1') -Aula $Aula -Numero $Numero -Dominio $Dominio
    return
}
if ($Action -eq 'Apagar') {
    & (Join-Path $PSScriptRoot 'apagar-aula.ps1') -Aula $Aula -Numero $Numero -Dominio $Dominio
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
}
foreach ($n in $Numero) {
    $computer = 'A{0}EQ{1:D2}.{2}' -f $Aula,$n,$Dominio
    $address = "172.21.$Aula.$n"
    $session = $null
    $details = $null
    try {
        switch ($Action) {
            'HabilitarWinRM' {
                Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'habilitar-winrm.ps1') -Destination "\\$computer\admin$\Temp\daw-habilitar-winrm.ps1" -Force
                $previousPreference = $ErrorActionPreference
                $ErrorActionPreference = 'Continue'
                try {
                    & $PsExecPath "\\$computer" -accepteula -nobanner -n 10 -r DAWAulaBootstrap -s powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\Windows\Temp\daw-habilitar-winrm.ps1 -ProfesorIP "172.21.$Aula.100" 2>&1 | ForEach-Object { "$_" }
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
                    'PrepararWSL' {
                        $remoteMsi = 'C:\Windows\Temp\daw-wsl.x64.msi'
                        Copy-Item -LiteralPath $WslMsi -Destination $remoteMsi -ToSession $session -Force
                        $script = Join-Path (Split-Path -Parent $PSScriptRoot) 'instalar-wsl-admin.ps1'
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
                                    catch { throw 'Hai unha instalación de alumno activa. Agardar antes de copiar o modelo.' }
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
                        } -ArgumentList $AutoInicio.IsPresent
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
