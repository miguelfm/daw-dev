#requires -Version 5.1
<#
.SYNOPSIS
Instala o paquete DAW Dev en todos os equipos dunha aula e comproba o resultado.
.DESCRIPTION
1. Valida o paquete local e avisa do que lle falta para traballar sen Internet.
2. Diagnostica os postos (WinRM) e só continúa cos que responden.
3. CopyPackage nos postos que responden, en paralelo: retira o paquete anterior, copia o
   novo e comproba o SHA256 de cada ficheiro no posto.
Non activa as contas: cada alumno activa DAW Dev na súa conta co menú Inicio (DAW Dev >
Activar DAW Dev) ou con daw-activate. Con Verify, comproba despois as contas conectadas
(web, MariaDB, documentación e VS Code Server) sen instalar nada.
Garda o informe en CSV en Get-DawToolsDirectory e indica como repetir os postos con erro.
.EXAMPLE
.\deploy.ps1 -Classroom 34 -PackageDirectory C:\DAW-Paquete-2026
.EXAMPLE
.\deploy.ps1 -Classroom 34 -Number 16 -PackageDirectory C:\DAW-Paquete-2026
.EXAMPLE
.\deploy.ps1 -Classroom 34 -PackageDirectory C:\DAW-Paquete-2026 -Verify -SkipCopy
#>
[CmdletBinding()]
param(
    [ValidateRange(1,254)][int]$Classroom = 34,
    [ValidateRange(1,35)][int[]]$Number = (1..35),
    [string]$Domain = 'iesrodolfoucha.es',
    [Parameter(Mandatory)][string]$PackageDirectory,
    [ValidateRange(1,10)][int]$ThrottleLimit = 5,
    [ValidateRange(60,7200)][int]$TimeoutSeconds = 1800,
    # Comproba tamén as contas conectadas que xa activaron DAW Dev.
    [switch]$Verify,
    # Só a verificación, sobre un paquete xa copiado.
    [switch]$SkipCopy
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'daw-classroom.psm1') -Force
if ($SkipCopy -and -not $Verify) { throw 'SkipCopy só ten sentido con Verify.' }
$manage = Join-Path $PSScriptRoot 'manage.ps1'
$numbers = @($Number | Sort-Object -Unique)

Write-Host "1. Paquete $PackageDirectory" -ForegroundColor Cyan
$manifest = Assert-DawPackage $PackageDirectory
$images = @(Get-DawPackageImages $manifest | ForEach-Object { $_.Name })
foreach ($name in Get-DawPackageImageNames) {
    if ($name -notin $images) { Write-Warning "O paquete non ten ${name}: sen Internet, a orde que a usa non funcionará." }
}
if (-not @(Get-DawPackageCodeServers $manifest).Count) { Write-Warning 'O paquete non ten VS Code Server: VS Code descargarao en cada conta (add-vscode-server.ps1).' }

Write-Host "2. Diagnóstico da aula $Classroom" -ForegroundColor Cyan
$rows = [ordered]@{}
foreach ($check in @(& (Join-Path $PSScriptRoot 'check-remote.ps1') -Classroom $Classroom -Number $numbers -Domain $Domain)) {
    $n = [int]($check.IP -split '\.')[-1]
    $rows[$n] = [pscustomobject]@{
        Number = $n; Computer = $check.Computer; WinRM = $check.Diagnostico -eq 'WSMan responde'
        Package = if ($SkipCopy) { 'Sen copiar' } else { '-' }; Verify = '-'; Detail = if ($check.Diagnostico -eq 'WSMan responde') { '' } else { $check.Diagnostico }
    }
}
$reachable = @($rows.Values | Where-Object WinRM | ForEach-Object Number)
Write-Host "   Responden $($reachable.Count) de $($numbers.Count)."

function Merge-DawResults($Results, [string]$Field) {
    foreach ($result in @($Results)) {
        $row = $rows.Values | Where-Object Computer -eq $result.Computer | Select-Object -First 1
        if (-not $row) { continue }
        $row.$Field = ConvertTo-DawDeployStatus $result
        if (-not $result.Success) { $row.Detail = [string]$result.Error }
    }
}
$common = @{ Classroom = $Classroom; Domain = $Domain; ThrottleLimit = $ThrottleLimit; TimeoutSeconds = $TimeoutSeconds }

if (-not $SkipCopy -and $reachable.Count) {
    Write-Host '3. Copia do paquete (CopyPackage)' -ForegroundColor Cyan
    Merge-DawResults (& $manage -Action CopyPackage -Number $reachable -PackageDirectory $PackageDirectory @common) 'Package'
}

if ($Verify) {
    $targets = @($rows.Values | Where-Object { $_.WinRM -and $_.Package -in @('OK','Sen copiar') } | ForEach-Object Number)
    if ($targets.Count) {
        Write-Host '4. Verificación das contas conectadas (Verify)' -ForegroundColor Cyan
        Merge-DawResults (& $manage -Action Verify -Number $targets @common) 'Verify'
    }
}

$report = @($rows.Values)
$report | Format-Table Computer, WinRM, Package, Verify, Detail -AutoSize -Wrap | Out-Host
$directory = Get-DawToolsDirectory
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$csv = Join-Path $directory ('deploy-{0}-{1}.csv' -f $Classroom, (Get-Date -Format 'yyyyMMdd-HHmmss'))
$report | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
Write-Host "Informe: $csv"
$failed = @($report | Where-Object { -not $_.WinRM -or $_.Package -eq 'Erro' -or $_.Verify -eq 'Erro' } | ForEach-Object Number)
if ($failed.Count) {
    Write-Warning ("Postos por revisar: {0}. Para repetilos: .\deploy.ps1 -Classroom {1} -Number {2} -PackageDirectory '{3}'" -f ($failed -join ', '), $Classroom, ($failed -join ','), $PackageDirectory)
}
$pending = @($report | Where-Object { $_.Verify -in @('Sen alumno','Sen activar') } | ForEach-Object Number)
if ($pending.Count) {
    Write-Host ("Sen verificar (sen alumno ou sen activar): {0}. O alumno activa DAW Dev no menú Inicio ou con daw-activate; despois, -Verify -SkipCopy." -f ($pending -join ', '))
}
return $report
