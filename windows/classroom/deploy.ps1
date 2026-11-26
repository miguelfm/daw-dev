#requires -Version 5.1
<#
.SYNOPSIS
Prepara o paquete DAW Dev, instálao en todos os equipos dunha aula e comproba o resultado.
.DESCRIPTION
1. Paquete: se non existe, constrúeo con build-package.ps1 (con Internet, tarda un bo anaco);
   se a construción quedou a medias, continúaa.
2. Diagnostica os postos (WinRM) e só continúa cos que responden.
3. Completa o paquete co que lle falte para traballar sen Internet: o VS Code Server dos
   commits de VS Code instalados nos postos, as imaxes da documentación (da release de
   daw-doc) e a de Angular (de ghcr.io, gardada co Docker da distribución modelo). Só
   descarga o que falta: repetilo co mesmo paquete non descarga nada.
4. CopyPackage nos postos que responden, en paralelo: retira o paquete anterior, copia o
   novo e comproba o SHA256 de cada ficheiro no posto.
Non activa as contas: cada alumno activa DAW Dev na súa conta co menú Inicio (DAW Dev >
Activar DAW Dev) ou con daw-activate. Con Verify, comproba despois as contas conectadas
(web, MariaDB, documentación e VS Code Server) sen instalar nada.
Garda o informe en CSV en Get-DawToolsDirectory e indica como repetir os postos con erro.
.EXAMPLE
.\deploy.ps1 -Classroom 34 -PackageDirectory C:\DAW-Paquete-2026
.EXAMPLE
.\deploy.ps1 -Classroom 31 -Number 1 -PackageDirectory C:\DAW-Paquete-2026
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
    # Usa o paquete tal como está: nin o constrúe nin o completa.
    [switch]$SkipPrepare,
    # Comproba tamén as contas conectadas que xa activaron DAW Dev.
    [switch]$Verify,
    # Só a verificación, sobre un paquete xa copiado.
    [switch]$SkipCopy
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'daw-classroom.psm1') -Force
if ($SkipCopy -and -not $Verify) { throw 'SkipCopy só ten sentido con Verify.' }
$prepare = -not ($SkipPrepare -or $SkipCopy)
$manage = Join-Path $PSScriptRoot 'manage.ps1'
$numbers = @($Number | Sort-Object -Unique)
$PackageDirectory = [IO.Path]::GetFullPath($PackageDirectory)
$checkpoint = Join-Path $PackageDirectory 'build\model.json'

function Get-DawModelDistribution {
    # A distribución modelo que deixou build-package.ps1 para este paquete, se aínda existe.
    if (-not (Test-Path -LiteralPath $checkpoint -PathType Leaf)) { return $null }
    $model = (Get-Content -LiteralPath $checkpoint -Raw -Encoding UTF8 | ConvertFrom-Json).Distribution
    if ($model -in @(Get-DawDistributions)) { return $model }
    return $null
}
function Add-DawAngularImage([string]$Name) {
    # Imaxe pública en ghcr.io, descargada e gardada co Docker da distribución modelo.
    $model = Get-DawModelDistribution
    if (-not $model) { throw 'Non está a distribución modelo deste paquete: engade a imaxe con add-package-image.ps1.' }
    $directory = Join-Path ([IO.Path]::GetTempPath()) ('daw-angular-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $directory | Out-Null
    try {
        $archive = Join-Path $directory ((($Name -split '/')[-1] -split ':')[0] + '.tar.gz')
        $linux = (@(Invoke-DawNative 'wsl.exe' @('-d', $model, '-u', 'root', '--exec', 'wslpath', '-u', $archive)) -join '').Trim()
        $script = 'for i in $(seq 60); do docker info >/dev/null 2>&1 && break; sleep 1; done; docker pull "$1" >&2 && docker save "$1" | gzip > "$2"'
        Invoke-DawNative 'wsl.exe' @('-d', $model, '-u', 'root', '--exec', 'sh', '-c', $script, 'sh', $Name, $linux) 1800 | Out-Null
        Add-DawPackageImage $PackageDirectory $archive $Name | Out-Null
    } finally {
        Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
function Get-DawPostCodeCommits([int[]]$Numbers) {
    # O VS Code de cada posto, lido por WinRM. O módulo cárgase desde un ficheiro temporal,
    # como en UpdateProject: con New-Module, a aula 34 rexeitou o bloque (18-11-2026).
    $computers = @($Numbers | ForEach-Object { 'A{0}EQ{1:D2}.{2}' -f $Classroom, $_, $Domain })
    $source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'daw-classroom.psm1'))
    $failed = @()
    $commits = Invoke-Command -ComputerName $computers -Authentication Kerberos -ErrorAction SilentlyContinue -ErrorVariable failed -ScriptBlock {
        param($source)
        $file = Join-Path $env:TEMP ('daw-classroom-' + [guid]::NewGuid().ToString('N') + '.psm1')
        try { [IO.File]::WriteAllText($file, $source, (New-Object Text.UTF8Encoding($true))); Import-Module $file -Force }
        finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
        Get-DawInstalledCodeCommits
    } -ArgumentList $source
    foreach ($e in @($failed)) { Write-Warning "Non se leu o VS Code de $($e.TargetObject): $($e.Exception.Message)" }
    @($commits | ForEach-Object { [string]$_ } | Sort-Object -Unique)
}

Write-Host "1. Paquete $PackageDirectory" -ForegroundColor Cyan
if ($prepare -and -not (Test-Path -LiteralPath (Join-Path $PackageDirectory 'manifest.json') -PathType Leaf)) {
    $build = Join-Path $PSScriptRoot 'build-package.ps1'
    if (Test-Path -LiteralPath $checkpoint -PathType Leaf) {
        $model = (Get-Content -LiteralPath $checkpoint -Raw -Encoding UTF8 | ConvertFrom-Json).Distribution
        Write-Host "   Continuando a construción co modelo $model..."
        & $build -OutputDirectory $PackageDirectory -Resume -Distribution $model
    } elseif (Test-Path -LiteralPath $PackageDirectory) {
        throw "$PackageDirectory existe pero non ten paquete nin construción que continuar: indica un directorio novo."
    } else {
        # Unha distribución modelo anterior consérvase para inspección: o novo leva outro nome.
        $model = if ('DAW-Model' -in @(Get-DawDistributions)) { 'DAW-Model-' + (Get-Date -Format 'yyyyMMdd-HHmm') } else { 'DAW-Model' }
        Write-Host "   Construíndo o paquete co modelo $model (con Internet, tarda un bo anaco)..."
        & $build -OutputDirectory $PackageDirectory -Distribution $model
    }
}
$manifest = Assert-DawPackage $PackageDirectory

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

if ($prepare) {
    Write-Host '3. O que lle falta ao paquete para traballar sen Internet' -ForegroundColor Cyan
    $images = @(Get-DawPackageImages $manifest | ForEach-Object { $_.Name })
    $docs = @(Get-DawPackageImageNames | Where-Object { $_ -match '/daw-doc-[a-z]+:' })
    if (@($docs | Where-Object { $_ -notin $images }).Count) {
        Write-Host '   Documentación: descargando a release de daw-doc...'
        try { & (Join-Path $PSScriptRoot 'add-doc-images.ps1') -PackageDirectory $PackageDirectory | Out-Null }
        catch { Write-Warning "Non se engadiu a documentación: $($_.Exception.Message)" }
    }
    foreach ($name in @(Get-DawPackageImageNames | Where-Object { $_ -notin $docs -and $_ -notin $images })) {
        Write-Host "   ${name}: descargando con Docker na distribución modelo..."
        try { Add-DawAngularImage $name } catch { Write-Warning "Non se engadiu ${name}: $($_.Exception.Message)" }
    }
    if ($reachable.Count) {
        $servers = @(Get-DawPackageCodeServers (Assert-DawPackage $PackageDirectory) | ForEach-Object Commit)
        foreach ($commit in @(Get-DawPostCodeCommits $reachable | Where-Object { $_ -notin $servers })) {
            Write-Host "   VS Code Server ${commit}: descargando..."
            try { & (Join-Path $PSScriptRoot 'add-vscode-server.ps1') -PackageDirectory $PackageDirectory -Commit $commit | Out-Null }
            catch { Write-Warning "Non se engadiu VS Code Server ${commit}: $($_.Exception.Message)" }
        }
    }
    $manifest = Assert-DawPackage $PackageDirectory
}
$images = @(Get-DawPackageImages $manifest | ForEach-Object { $_.Name })
foreach ($name in Get-DawPackageImageNames) {
    if ($name -notin $images) { Write-Warning "O paquete non ten ${name}: sen Internet, a orde que a usa non funcionará." }
}
if (-not @(Get-DawPackageCodeServers $manifest).Count) { Write-Warning 'O paquete non ten VS Code Server: VS Code descargarao en cada conta (add-vscode-server.ps1).' }

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
    Write-Host '4. Copia do paquete (CopyPackage)' -ForegroundColor Cyan
    Merge-DawResults (& $manage -Action CopyPackage -Number $reachable -PackageDirectory $PackageDirectory @common) 'Package'
}

if ($Verify) {
    $targets = @($rows.Values | Where-Object { $_.WinRM -and $_.Package -in @('OK','Sen copiar') } | ForEach-Object Number)
    if ($targets.Count) {
        Write-Host '5. Verificación das contas conectadas (Verify)' -ForegroundColor Cyan
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
