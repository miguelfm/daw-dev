#requires -Version 5.1
# Só para aulas que optaron expresamente polo autoarranque.
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'daw-aula.psm1') -Force
$statusPath=Join-Path $env:LOCALAPPDATA 'DAW-Aula\estado.json'
$manifest=Assert-DawPackage $PSScriptRoot
if(Test-Path -LiteralPath $statusPath){
    try{
        $status=Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8|ConvertFrom-Json
        if($status.PSObject.Properties['SetupRevision'] -and $status.SetupRevision -eq 2 -and $status.Success -and $status.ModelSha256 -eq $manifest.Sha256){
            $env:WSL_UTF8='1'
            $installed=@(Invoke-DawNative 'wsl.exe' @('--list','--quiet')) -replace "`0",''|ForEach-Object {$_.Trim()}
            if($status.Distribution -in $installed){return}
        }
    }catch{Write-Warning $_.Exception.Message}
}
& (Join-Path $PSScriptRoot 'instalar-alumno.ps1') -PackageDirectory $PSScriptRoot
