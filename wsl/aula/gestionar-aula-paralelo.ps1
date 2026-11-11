#requires -Version 5.1
<#
.SYNOPSIS
Executa PrepararWSL e CopiarModelo en paralelo mediante Start-Job en lotes configurables.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('PrepararWSL','CopiarModelo')]
    [string]$Action,
    [Parameter(Mandatory)]
    [ValidateRange(1,35)][int[]]$Numero,
    [ValidateRange(1,254)][int]$Aula = 34,
    [string]$Dominio = 'iesrodolfoucha.es',
    [string]$PackageDirectory = "$HOME\Projects\daw-aula-paquete-20261111-final",
    [string]$WslMsi = (Join-Path $env:LOCALAPPDATA 'DAW-Aula-Tools\wsl.3.0.5.0.x64.msi')
)

$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'

if ($Action -eq 'PrepararWSL') {
    if (-not (Test-Path -LiteralPath $WslMsi)) { throw "Non se atopou $WslMsi" }
}

$files = @('manifest.json','daw.ps1','install-daw-commands.ps1','instalar-alumno.ps1','iniciar-usuario.ps1')
if ($Action -eq 'CopiarModelo') {
    $manifest = Get-Content -LiteralPath (Join-Path $PackageDirectory 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $files += $manifest.Image
}

$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'instalar-wsl-admin.ps1'

Write-Host "Lanzando $Action en paralelo para os equipos: $($Numero -join ', ')..."

$jobs = foreach ($n in $Numero) {
    Start-Job -ScriptBlock {
        param($Action, $n, $Aula, $Dominio, $WslMsi, $scriptPath, $PackageDirectory, $files)
        $computer = 'A{0}EQ{1:D2}.{2}' -f $Aula, $n, $Dominio
        $session = $null
        try {
            $session = New-PSSession -ComputerName $computer -Authentication Kerberos -ErrorAction Stop
            switch ($Action) {
                'PrepararWSL' {
                    $remoteMsi = 'C:\Windows\Temp\daw-wsl.x64.msi'
                    Copy-Item -LiteralPath $WslMsi -Destination $remoteMsi -ToSession $session -Force
                    $output = Invoke-Command -Session $session -FilePath $scriptPath -ArgumentList $remoteMsi
                    $restartRequired = $output -match 'REINICIO REQUIRIDO|RestartRequired'
                    [pscustomobject]@{
                        Equipo = $computer; Action = $Action; Success = $true; RestartRequired = [bool]$restartRequired; Error = $null
                    }
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
                        Copy-Item -LiteralPath (Join-Path $PackageDirectory $file) -Destination "\\$computer\c$\ProgramData\DAW-Aula\$file" -Force
                    }
                    Invoke-Command -Session $session -ScriptBlock {
                        $target = 'C:\ProgramData\DAW-Aula'
                        Get-ChildItem -LiteralPath $target -File | ForEach-Object {
                            $acl = New-Object Security.AccessControl.FileSecurity
                            $acl.SetAccessRuleProtection($false,$false)
                            $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
                            Set-Acl -LiteralPath $_.FullName -AclObject $acl
                        }
                        $manifest = Get-Content -LiteralPath "$target\manifest.json" -Raw -Encoding UTF8 | ConvertFrom-Json
                        if ($manifest.Image -notin @('debian-daw.tar','debian-daw.tar.gz') -or
                            (Get-FileHash -LiteralPath (Join-Path $target $manifest.Image) -Algorithm SHA256).Hash -ne $manifest.Sha256) {
                            throw 'Fallou a verificación despois da copia.'
                        }
                        $command = "& 'C:\ProgramData\DAW-Aula\iniciar-usuario.ps1'"
                        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
                        $run = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
                        New-ItemProperty -Path $run -Name 'DAWAula' -Value "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encoded" -PropertyType String -Force | Out-Null
                    }
                    [pscustomobject]@{ Equipo = $computer; Action = $Action; Success = $true; RestartRequired = $null; Error = $null }
                }
            }
        } catch {
            [pscustomobject]@{ Equipo = $computer; Action = $Action; Success = $false; RestartRequired = $null; Error = $_.Exception.Message }
        } finally {
            if ($session) { Remove-PSSession $session }
        }
    } -ArgumentList $Action, $n, $Aula, $Dominio, $WslMsi, $scriptPath, $PackageDirectory, $files
}

$results = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job
return $results
