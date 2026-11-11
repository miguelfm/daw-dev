#requires -Version 5.1
<#
.SYNOPSIS
Desprega DAW Dev desde o equipo 100. Por defecto aula 34, equipos 1-35.
.DESCRIPTION
Comprobar: só diagnóstico. HabilitarWinRM: bootstrap con PsExec asinado de Microsoft.
PrepararWSL: características + MSI oficial (non reinicia). CopiarModelo: copia local
protexida e importación automática ao iniciar sesión. InstalarUsuario: tarefa sen
elevación na sesión activa. Estado: consulta logs por perfil. Non almacena contrasinais.
.EXAMPLE
.\gestionar-aula.ps1 -Action Comprobar -Aula 31 -Numero 1
.EXAMPLE
.\gestionar-aula.ps1 -Action HabilitarWinRM -Aula 31 -Numero 1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Comprobar','HabilitarWinRM','PrepararWSL','CopiarModelo','InstalarUsuario','Estado')]
    [string]$Action,
    [ValidateRange(1,254)][int]$Aula = 34,
    [ValidateRange(1,35)][int[]]$Numero = (1..35),
    [string]$Dominio = 'iesrodolfoucha.es',
    [string]$PackageDirectory,
    [string]$WslMsi,
    [string]$PsExecPath = (Join-Path $env:LOCALAPPDATA 'DAW-Aula-Tools\PsExec64.exe')
)
$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'
if ($Action -eq 'Comprobar') {
    & (Join-Path $PSScriptRoot 'comprobar-remoto.ps1') -Aula $Aula -Numero $Numero -Dominio $Dominio
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
$files = @('manifest.json','daw.ps1','install-daw-commands.ps1','instalar-alumno.ps1','iniciar-usuario.ps1')
if ($Action -eq 'CopiarModelo') {
    if (-not $PackageDirectory) { throw 'Indica -PackageDirectory.' }
    foreach ($file in $files) {
        if (-not (Test-Path -LiteralPath (Join-Path $PackageDirectory $file) -PathType Leaf)) { throw "Falta $file no paquete." }
    }
    $manifest = Get-Content -LiteralPath (Join-Path $PackageDirectory 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.Image -notin @('debian-daw.tar','debian-daw.tar.gz') -or $manifest.Schema -ne 1 -or
        (Get-FileHash -LiteralPath (Join-Path $PackageDirectory $manifest.Image) -Algorithm SHA256).Hash -ne $manifest.Sha256) {
        throw 'O manifesto e o SHA256 do modelo non coinciden.'
    }
    $files += $manifest.Image
}
foreach ($n in $Numero) {
    $computer = 'A{0}EQ{1:D2}.{2}' -f $Aula,$n,$Dominio
    $address = "172.21.$Aula.$n"
    $session = $null
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
                        Invoke-Command -Session $session -ScriptBlock {
                            $user = (Get-CimInstance Win32_ComputerSystem).UserName
                            if (-not $user) { throw 'Non hai usuario na consola. A importación farase no seguinte inicio de sesión.' }
                            $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
                            $command = "& 'C:\ProgramData\DAW-Aula\instalar-alumno.ps1' -PackageDirectory 'C:\ProgramData\DAW-Aula'"
                            $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
                            $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encoded"
                            $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
                            Register-ScheduledTask -TaskName 'DAW-InstalarUsuario' -Principal $principal -Action $action -Settings $settings -Force | Out-Null
                            Start-ScheduledTask -TaskName 'DAW-InstalarUsuario'
                            Write-Output "Importación solicitada na sesión de $user sen elevación. Consulta Estado para verificar o resultado."
                        }
                    }
                    'PrepararWSL' {
                        $remoteMsi = 'C:\Windows\Temp\daw-wsl.x64.msi'
                        Copy-Item -LiteralPath $WslMsi -Destination $remoteMsi -ToSession $session -Force
                        $script = Join-Path (Split-Path -Parent $PSScriptRoot) 'instalar-wsl-admin.ps1'
                        Invoke-Command -Session $session -FilePath $script -ArgumentList $remoteMsi
                        Write-Host "[$computer] Non se reiniciou automaticamente. Revisa RestartRequired."
                    }
                    'CopiarModelo' {
                        Invoke-Command -Session $session -ScriptBlock {
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
                        }
                        foreach ($file in $files) {
                            # SMB desde o profesor evita o custo de serializar un tar grande por WinRM.
                            Copy-Item -LiteralPath (Join-Path $PackageDirectory $file) -Destination "\\$computer\c$\ProgramData\DAW-Aula\$file" -Force
                        }
                        Invoke-Command -Session $session -ScriptBlock {
                            $target = 'C:\ProgramData\DAW-Aula'
                            # Elimina ACL explícitas herdadas dunha copia anterior en cada ficheiro.
                            Get-ChildItem -LiteralPath $target -File | ForEach-Object {
                                $acl = New-Object Security.AccessControl.FileSecurity
                                $acl.SetAccessRuleProtection($false,$false)
                                $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
                                Set-Acl -LiteralPath $_.FullName -AclObject $acl
                            }
                            $manifest = Get-Content -LiteralPath "$target\manifest.json" -Raw -Encoding UTF8 | ConvertFrom-Json
                            if ($manifest.Image -notin @('debian-daw.tar','debian-daw.tar.gz') -or
                                (Get-FileHash -LiteralPath (Join-Path $target $manifest.Image) -Algorithm SHA256).Hash -ne $manifest.Sha256) { throw 'Fallou a verificación despois da copia.' }
                            # Run execútase coa conta que inicia sesión, sen elevación nin contrasinais.
                            $command = "& 'C:\ProgramData\DAW-Aula\iniciar-usuario.ps1'"
                            $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
                            $run = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
                            New-ItemProperty -Path $run -Name 'DAWAula' -Value "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encoded" -PropertyType String -Force | Out-Null
                        }
                    }
                    'Estado' {
                        Invoke-Command -Session $session -ScriptBlock {
                            Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special } | ForEach-Object {
                                $path = Join-Path $_.LocalPath 'AppData\Local\DAW-Aula\estado.json'
                                if (Test-Path -LiteralPath $path) {
                                    $state = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
                                    [pscustomobject]@{ Profile = $_.LocalPath; User = $state.User; Success = $state.Success; Error = $state.Error; CheckedUtc = $state.CheckedUtc }
                                }
                            }
                        }
                    }
                }
            }
        }
        [pscustomobject]@{ Equipo = $computer; Action = $Action; Success = $true; Error = $null }
    } catch {
        [pscustomobject]@{ Equipo = $computer; Action = $Action; Success = $false; Error = $_.Exception.Message }
    } finally {
        if ($session) { Remove-PSSession $session }
    }
}
