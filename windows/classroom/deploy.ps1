#requires -Version 5.1
<#
.SYNOPSIS
Prepara o paquete DAW Dev, instálao en todos os equipos dunha aula e comproba o resultado.
.DESCRIPTION
1. Paquete: se non existe, constrúeo con build-package.ps1 (con Internet, tarda un bo anaco);
   se a construción quedou a medias, continúaa.
2. Diagnostica os postos (WinRM) e só continúa cos que responden. Con PrepareWindows, activa
   WinRM nos que non responden (PsExec), instala WSL nos que o precisan e, con RestartComputers,
   reinicia os que o necesitan e non teñen ninguén con sesión iniciada.
3. Completa o paquete co que lle falte para traballar sen Internet: o VS Code Server dos
   commits de VS Code instalados nos postos, as extensións de VS Code para PHP (do
   Marketplace), as imaxes da documentación (da release de daw-doc) e a de Angular (de
   ghcr.io, gardada co Docker da distribución modelo). Só
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
.\deploy.ps1 -Classroom 31 -Number (1..30) -PackageDirectory C:\DAW-Paquete-2026 -PrepareWindows -RestartComputers
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
    # Activa WinRM e instala WSL nos postos que o precisan.
    [switch]$PrepareWindows,
    # Con PrepareWindows: reinicia os postos que o necesitan e non teñen ninguén con sesión iniciada.
    [switch]$RestartComputers,
    # MSI de WSL xa descargado; sen el, InstallWSL descarga o último.
    [string]$WslMsi,
    # Comproba tamén as contas conectadas que xa activaron DAW Dev.
    [switch]$Verify,
    # Só a verificación, sobre un paquete xa copiado.
    [switch]$SkipCopy
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'daw-classroom.psm1') -Force
if ($SkipCopy -and -not $Verify) { throw 'SkipCopy só ten sentido con Verify.' }
if ($RestartComputers -and -not $PrepareWindows) { throw 'RestartComputers só se usa con PrepareWindows.' }
if ($PrepareWindows -and $SkipCopy) { throw 'PrepareWindows non se usa con SkipCopy.' }
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
function Get-DawComputerName([int]$N) { 'A{0}EQ{1:D2}.{2}' -f $Classroom, $N, $Domain }
function Invoke-DawOnComputers([int[]]$Numbers, [string]$Function, [string]$What) {
    # Unha función do módulo en varios postos á vez, por WinRM. O módulo cárgase desde un ficheiro
    # temporal, como en UpdateProject: con New-Module, a aula 34 rexeitou o bloque (18-11-2026).
    $computers = @($Numbers | ForEach-Object { Get-DawComputerName $_ })
    $source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'daw-classroom.psm1'))
    $failed = @()
    $results = Invoke-Command -ComputerName $computers -Authentication Kerberos -ErrorAction SilentlyContinue -ErrorVariable failed -ScriptBlock {
        param($source, $function)
        $file = Join-Path $env:TEMP ('daw-classroom-' + [guid]::NewGuid().ToString('N') + '.psm1')
        try { [IO.File]::WriteAllText($file, $source, (New-Object Text.UTF8Encoding($true))); Import-Module $file -Force }
        finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
        & $function
    } -ArgumentList $source, $Function
    foreach ($e in @($failed)) { Write-Warning "Non se leu $What en $($e.TargetObject): $($e.Exception.Message)" }
    @($results)
}
function Get-DawPostCodeCommits([int[]]$Numbers) {
    # O VS Code de cada posto, lido por WinRM.
    @(Invoke-DawOnComputers $Numbers 'Get-DawInstalledCodeCommits' 'o VS Code' | ForEach-Object { [string]$_ } | Sort-Object -Unique)
}
function Update-DawWindowsRows([int[]]$Numbers) {
    # Estado de Windows de cada posto na columna Windows; devolve os estados por número.
    $states = @{}
    foreach ($state in Invoke-DawOnComputers $Numbers 'Get-DawWindowsState' 'o estado de Windows') {
        $row = $rows.Values | Where-Object { $_.Computer -ieq $state.PSComputerName } | Select-Object -First 1
        if (-not $row) { continue }
        $states[$row.Number] = $state
        $row.Windows = ConvertTo-DawWindowsStatus $state
        $row.Detail = switch ($row.Windows) {
            'Erro' { 'A virtualización está desactivada na BIOS/UEFI.' }
            'Reiniciar' { if ($state.Sessions) { 'Precisa reiniciar; hai unha sesión iniciada.' } else { 'Precisa reiniciar.' } }
            default { $row.Detail }
        }
    }
    foreach ($n in $Numbers) { if (-not $states.ContainsKey($n)) { ($rows[$n]).Windows = 'Erro' } }
    $states
}
function Wait-DawWinRM([int[]]$Numbers, [int]$Seconds = 900) {
    # Despois dun reinicio: agarda a que cada posto volva responder por WinRM.
    $deadline = (Get-Date).AddSeconds($Seconds)
    $pending = [Collections.Generic.List[int]]::new([int[]]$Numbers)
    Start-Sleep -Seconds 30
    while ($pending.Count -and (Get-Date) -lt $deadline) {
        foreach ($n in @($pending)) {
            try { $null = Test-WSMan -ComputerName (Get-DawComputerName $n) -ErrorAction Stop; $null = $pending.Remove($n) } catch { }
        }
        if ($pending.Count) { Start-Sleep -Seconds 10 }
    }
    @($pending)
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
# Hashtable e non [ordered]: nun [ordered], $rows[3] é a posición 3, non o posto 3.
$rows = @{}
foreach ($check in @(& (Join-Path $PSScriptRoot 'check-remote.ps1') -Classroom $Classroom -Number $numbers -Domain $Domain)) {
    $n = [int]($check.IP -split '\.')[-1]
    $rows[$n] = [pscustomobject]@{
        Number = $n; Computer = $check.Computer; WinRM = $check.Diagnostico -eq 'WSMan responde'; Windows = '-'
        Package = if ($SkipCopy) { 'Sen copiar' } else { '-' }; Verify = '-'; Detail = if ($check.Diagnostico -eq 'WSMan responde') { '' } else { $check.Diagnostico }
    }
}
$reachable = @($rows.Values | Where-Object WinRM | Sort-Object Number | ForEach-Object Number)
Write-Host "   Responden $($reachable.Count) de $($numbers.Count)."

if ($PrepareWindows) {
    Write-Host '   Windows: WinRM, WSL e reinicios' -ForegroundColor Cyan
    $silent = @($rows.Values | Where-Object { -not $_.WinRM } | Sort-Object Number | ForEach-Object Number)
    if ($silent.Count) {
        Write-Host "   Activando WinRM con PsExec en: $($silent -join ', ')"
        foreach ($result in @(& $manage -Action EnableWinRM -Number $silent -Classroom $Classroom -Domain $Domain)) {
            $row = $rows.Values | Where-Object Computer -eq $result.Computer | Select-Object -First 1
            if (-not $row) { continue }
            $row.WinRM = [bool]$result.Success
            $row.Detail = if ($result.Success) { '' } else { "WinRM: $($result.Error)" }
        }
        $reachable = @($rows.Values | Where-Object WinRM | Sort-Object Number | ForEach-Object Number)
    }
    if ($reachable.Count) {
        $states = Update-DawWindowsRows $reachable
        $install = @($rows.Values | Where-Object { $_.Windows -eq 'Preparar' } | Sort-Object Number | ForEach-Object Number)
        if ($install.Count) {
            Write-Host "   Instalando WSL en: $($install -join ', ')"
            $wslArgs = @{ Classroom = $Classroom; Domain = $Domain; ThrottleLimit = $ThrottleLimit; TimeoutSeconds = $TimeoutSeconds }
            if ($WslMsi) { $wslArgs.WslMsi = $WslMsi }
            foreach ($result in @(& $manage -Action InstallWSL -Number $install @wslArgs)) {
                $row = $rows.Values | Where-Object Computer -eq $result.Computer | Select-Object -First 1
                if ($row -and -not $result.Success) { $row.Windows = 'Erro'; $row.Detail = "WSL: $($result.Error)" }
            }
            $states = Update-DawWindowsRows $reachable
        }
        $restart = @($rows.Values | Where-Object { $_.Windows -eq 'Reiniciar' } | Sort-Object Number | ForEach-Object Number)
        if ($restart.Count -and $RestartComputers) {
            # Só os postos de estado coñecido e sen ninguén con sesión iniciada.
            $idle = @($restart | Where-Object { $states.ContainsKey($_) -and -not $states[$_].Sessions })
            if ($idle.Count) {
                Write-Host "   Reiniciando (sen sesión iniciada): $($idle -join ', ')"
                $computers = @($idle | ForEach-Object { Get-DawComputerName $_ })
                # Por WinRM e non Restart-Computer, que usa RPC/135, pechado polo cortalumes.
                Invoke-Command -ComputerName $computers -Authentication Kerberos -ErrorAction SilentlyContinue -ScriptBlock { shutdown.exe /r /t 5 /f /d p:2:4 } | Out-Null
                $late = @(Wait-DawWinRM $idle)
                foreach ($n in $late) { ($rows[$n]).Windows = 'Erro'; ($rows[$n]).WinRM = $false; ($rows[$n]).Detail = 'Non volveu responder por WinRM despois de reiniciar.' }
                $back = @($idle | Where-Object { $_ -notin $late })
                if ($back.Count) { $null = Update-DawWindowsRows $back }
            }
        }
        $reachable = @($rows.Values | Where-Object WinRM | Sort-Object Number | ForEach-Object Number)
    }
}

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
    # Extensións de VS Code que acepte o VS Code máis vello: o dos postos (non se actualiza) e o deste equipo.
    $codeVersions = @()
    if ($reachable.Count) { $codeVersions += @(Invoke-DawOnComputers $reachable 'Get-DawInstalledCodeVersions' 'a versión de VS Code' | ForEach-Object { [string]$_ }) }
    try { $codeVersions += @(Get-DawInstalledCodeVersions) } catch { Write-Warning "Non se leu a versión de VS Code deste equipo: $($_.Exception.Message)" }
    $oldestCode = @($codeVersions | Where-Object { $_ -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_ }) | Select-Object -First 1
    $packageExtensions = @(Get-DawPackageCodeExtensions (Assert-DawPackage $PackageDirectory))
    $neededExtensions = @(foreach ($id in Get-DawPackageCodeExtensionIds) {
        $entry = $packageExtensions | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if (-not $entry) { $id; continue }
        if ($oldestCode) {
            try { $engine = (Get-DawVsixInfo (Join-Path $PackageDirectory $entry.File)).Engine } catch { $id; continue }
            if (-not (Test-DawCodeEngine $engine $oldestCode)) { $id }
        }
    })
    if ($neededExtensions.Count) {
        $addArgs = @{ PackageDirectory = $PackageDirectory; Id = $neededExtensions }
        $forCode = ''
        if ($oldestCode) { $addArgs.CodeVersion = $oldestCode; $forCode = " para VS Code $oldestCode" }
        Write-Host "   Extensións de VS Code${forCode}: descargando $($neededExtensions -join ', ')..."
        try { & (Join-Path $PSScriptRoot 'add-vscode-extensions.ps1') @addArgs | Out-Null }
        catch { Write-Warning "Non se engadiron as extensións de VS Code: $($_.Exception.Message)" }
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
$extensions = @(Get-DawPackageCodeExtensions $manifest | ForEach-Object Id)
foreach ($id in Get-DawPackageCodeExtensionIds) {
    if ($id -notin $extensions) {
        $where = if ($id -in @(Get-DawWindowsCodeExtensionIds)) { 'VS Code' } else { 'o Dev Container' }
        Write-Warning "O paquete non ten a extensión ${id}: sen Internet, $where quedará sen ela (add-vscode-extensions.ps1)."
    }
}

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
    $targets = @($rows.Values | Where-Object { $_.WinRM -and $_.Package -in @('OK','Sen copiar') } | Sort-Object Number | ForEach-Object Number)
    if ($targets.Count) {
        Write-Host '5. Verificación das contas conectadas (Verify)' -ForegroundColor Cyan
        Merge-DawResults (& $manage -Action Verify -Number $targets @common) 'Verify'
    }
}

$report = @($rows.Values | Sort-Object Number)
$report | Format-Table Computer, WinRM, Windows, Package, Verify, Detail -AutoSize -Wrap | Out-Host
$directory = Get-DawToolsDirectory
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$csv = Join-Path $directory ('deploy-{0}-{1}.csv' -f $Classroom, (Get-Date -Format 'yyyyMMdd-HHmmss'))
$report | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
Write-Host "Informe: $csv"
$failed = @($report | Where-Object { -not $_.WinRM -or $_.Windows -eq 'Erro' -or $_.Package -eq 'Erro' -or $_.Verify -eq 'Erro' } | ForEach-Object Number)
if ($failed.Count) {
    Write-Warning ("Postos por revisar: {0}. Para repetilos: .\deploy.ps1 -Classroom {1} -Number {2} -PackageDirectory '{3}'" -f ($failed -join ', '), $Classroom, ($failed -join ','), $PackageDirectory)
}
$restartLater = @($report | Where-Object Windows -eq 'Reiniciar' | ForEach-Object Number)
if ($restartLater.Count) {
    Write-Warning ("Postos por reiniciar antes de activar DAW Dev: {0}. Sen sesións abertas, -PrepareWindows -RestartComputers reiníciaos." -f ($restartLater -join ', '))
}
$pending = @($report | Where-Object { $_.Verify -in @('Sen alumno','Sen activar') } | ForEach-Object Number)
if ($pending.Count) {
    Write-Host ("Sen verificar (sen alumno ou sen activar): {0}. O alumno activa DAW Dev no menú Inicio ou con daw-activate; despois, -Verify -SkipCopy." -f ($pending -join ', '))
}
return $report
