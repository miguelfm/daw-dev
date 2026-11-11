#requires -Version 5.1
<#
.SYNOPSIS
Crea un modelo Debian limpo e un paquete para a aula, sen modificar Debian persoal.
.DESCRIPTION
Descarga a base Debian publicada no catálogo oficial de WSL, verifica SHA256,
importa DAW-Modelo, instala Docker e precarga as tres imaxes de Compose.
Require WSL2 xa preparado e git. Non require elevación Windows.
Non modifica distribucións persoais. -Resume só continúa un modelo co seu checkpoint verificado.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$BaseImagePath,
    [string]$DockerImagesArchive,
    [switch]$Resume,
    [ValidatePattern('^DAW-Modelo[a-zA-Z0-9._-]*$')][string]$Distribution = 'DAW-Modelo'
)
$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$output = [IO.Path]::GetFullPath($OutputDirectory)
$build = Join-Path $output 'build'
$checkpointPath = Join-Path $build 'model.json'
$distroDir = Join-Path $env:LOCALAPPDATA "wsl\$Distribution"
$sources = Join-Path $build 'sources.tar'
$installed = @(& wsl.exe --list --quiet) -replace "`0", ''
if ($LASTEXITCODE -ne 0) { throw 'WSL non está preparado.' }
if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'Este paquete está preparado para Windows x64.' }
function Invoke-Model([string[]]$CommandArgs) {
    # Windows PowerShell 5.1 pode tratar progreso en stderr como erro ao redirixir un log.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & wsl.exe -d $Distribution -u root --exec @CommandArgs 2>&1 | ForEach-Object { "$_" }
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) { throw "Fallou o paso do modelo: $($CommandArgs -join ' ')" }
}
if ($Resume) {
    $checkpoint = Get-Content -LiteralPath $checkpointPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $registered = Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' | Get-ItemProperty | Where-Object DistributionName -eq $Distribution
    if ($checkpoint.Distribution -ne $Distribution -or $checkpoint.InstallDirectory -ne $distroDir -or
        -not $registered -or $registered.BasePath.TrimEnd('\') -ne $distroDir.TrimEnd('\') -or
        (Get-FileHash -LiteralPath $sources -Algorithm SHA256).Hash -ne $checkpoint.SourcesSha256) {
        throw 'O punto de continuación non coincide co modelo creado por este script.'
    }
    if ((Test-Path -LiteralPath (Join-Path $output 'debian-daw.tar')) -or
        (Test-Path -LiteralPath (Join-Path $output 'debian-daw.tar.gz'))) { throw 'Xa hai unha exportación. Non se sobrescribe.' }
    $base = @{ Amd64Url = @{ Url = $checkpoint.BaseUrl; Sha256 = $checkpoint.BaseSha256 } }
    $sourceCommit = $checkpoint.SourceCommit
} else {
if (Test-Path -LiteralPath $output) { throw 'Escolle un directorio de saída novo.' }
if ($installed -contains $Distribution) { throw "$Distribution xa existe. Escolle outro nome para un modelo novo." }
New-Item -ItemType Directory -Path $output | Out-Null
New-Item -ItemType Directory -Path $build | Out-Null
$catalog = Invoke-RestMethod 'https://raw.githubusercontent.com/microsoft/WSL/master/distributions/DistributionInfo.json'
$base = $catalog.ModernDistributions.Debian | Where-Object Name -eq 'Debian' | Select-Object -First 1
if (-not $base.Amd64Url.Url -or $base.Amd64Url.Sha256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw 'O catálogo non contén unha imaxe Debian x64 con SHA256 válido.'
}
$baseTar = Join-Path $build 'debian-base.wsl'
$ProgressPreference = 'SilentlyContinue'
Write-Host 'Descargando a base oficial de Debian...'
$downloadUrl = $base.Amd64Url.Url
# A API pública de GitLab serve o mesmo artefacto e evita recibir HTML no endpoint web.
if ($downloadUrl -match '^https://salsa\.debian\.org/debian/WSL/-/jobs/(\d+)/artifacts/raw/([^/]+)$') {
    $downloadUrl = "https://salsa.debian.org/api/v4/projects/debian%2FWSL/jobs/$($Matches[1])/artifacts/$($Matches[2])"
}
if ($BaseImagePath) { Copy-Item -LiteralPath $BaseImagePath -Destination $baseTar }
else {
    & curl.exe --fail --location --silent --show-error --connect-timeout 20 --max-time 600 --output $baseTar $downloadUrl
    if ($LASTEXITCODE -ne 0) { throw 'Fallou a descarga da base Debian.' }
}
if ((Get-FileHash -LiteralPath $baseTar -Algorithm SHA256).Hash -ne $base.Amd64Url.Sha256) {
    throw 'O SHA256 da base Debian non coincide. Non se importou a imaxe.'
}
& git.exe -C $repo archive --format=tar --output=$sources HEAD
if ($LASTEXITCODE -ne 0) { throw 'Fallou git archive.' }
# Inclúe os lanzadores locais desta entrega, aínda que os cambios non estean publicados.
& tar.exe -rf $sources -C $repo wsl/daw.ps1 wsl/keep-alive.sh wsl/install-daw-commands.ps1 wsl/aula/configurar-modelo.sh
if ($LASTEXITCODE -ne 0) { throw 'Fallou a preparación dos scripts do modelo.' }
if (Test-Path -LiteralPath $distroDir) { throw "O directorio $distroDir xa existe." }
New-Item -ItemType Directory -Path $distroDir -Force | Out-Null
& wsl.exe --import $Distribution $distroDir $baseTar --version 2
if ($LASTEXITCODE -ne 0) { throw 'Fallou a importación da base Debian.' }
$linuxSources = (& wsl.exe -d $Distribution -u root --exec wslpath -a -u $sources) -join ''
if ($LASTEXITCODE -ne 0) { throw 'Non se puido converter a ruta do paquete.' }
$linuxSources = $linuxSources.Trim()
Invoke-Model @('tar','-xf',$linuxSources,'-C','/tmp','wsl/aula/configurar-modelo.sh')
Invoke-Model @('bash','/tmp/wsl/aula/configurar-modelo.sh','install',$linuxSources)
$sourceCommit = (& git.exe -C $repo rev-parse HEAD).Trim()
[ordered]@{
    Distribution = $Distribution; InstallDirectory = $distroDir; SourceCommit = $sourceCommit
    SourcesSha256 = (Get-FileHash -LiteralPath $sources -Algorithm SHA256).Hash
    BaseUrl = $base.Amd64Url.Url; BaseSha256 = $base.Amd64Url.Sha256
} | ConvertTo-Json | Set-Content -LiteralPath $checkpointPath -Encoding UTF8
}
# O configurador e os lanzadores poden recibir correccións antes de selar o modelo.
$linuxConfigurator = (& wsl.exe -d $Distribution -u root --exec wslpath -a -u (Join-Path $PSScriptRoot 'configurar-modelo.sh')) -join ''
if ($LASTEXITCODE -ne 0) { throw 'Non se puido localizar o configurador.' }
Invoke-Model @('cp',$linuxConfigurator.Trim(),'/home/alumno/proxectos/daw-dev/wsl/aula/configurar-modelo.sh')
$imageArgs = @('bash','/home/alumno/proxectos/daw-dev/wsl/aula/configurar-modelo.sh','images')
if ($DockerImagesArchive) {
    $linuxImages = (& wsl.exe -d $Distribution -u root --exec wslpath -a -u ([IO.Path]::GetFullPath($DockerImagesArchive))) -join ''
    if ($LASTEXITCODE -ne 0) { throw 'Non se puido localizar o arquivo de imaxes Docker.' }
    $imageArgs += $linuxImages.Trim()
}
& wsl.exe --terminate $Distribution
if ($LASTEXITCODE -ne 0) { throw 'Non se puido reiniciar o modelo para activar systemd.' }
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try { Invoke-Model $imageArgs; break }
    catch { if ($attempt -eq 3) { throw }; Write-Warning 'Repetindo a descarga das imaxes...'; Start-Sleep -Seconds 5 }
}
Invoke-Model @('bash','/home/alumno/proxectos/daw-dev/wsl/aula/configurar-modelo.sh','seal')
& wsl.exe --terminate $Distribution
if ($LASTEXITCODE -ne 0) { throw 'Non se puido parar o modelo.' }
$image = Join-Path $output 'debian-daw.tar.gz'
& wsl.exe --export $Distribution $image --format tar.gz
if ($LASTEXITCODE -ne 0) { throw 'Fallou a exportación do modelo.' }
foreach ($file in 'instalar-alumno.ps1','iniciar-usuario.ps1') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $output
}
foreach ($file in 'daw.ps1','install-daw-commands.ps1') {
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) $file) -Destination $output
}
$manifest = [ordered]@{
    Schema = 1; Marker = 'daw-aula-v1'; LinuxUser = 'alumno'
    LinuxProjectPath = '/home/alumno/proxectos/daw-dev'
    Image = 'debian-daw.tar.gz'; Sha256 = (Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash
    CreatedUtc = [DateTime]::UtcNow.ToString('o')
    SourceCommit = $sourceCommit; SourcesSha256 = (Get-FileHash -LiteralPath $sources -Algorithm SHA256).Hash
    BaseUrl = $base.Amd64Url.Url; BaseSha256 = $base.Amd64Url.Sha256
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'manifest.json') -Encoding UTF8
Write-Host "Paquete preparado en $output. A distribución $Distribution consérvase para inspección."
Write-Host 'O subdirectorio build non se distribúe. Non se arrancaron contedores nin se crearon datos de alumnos.'
