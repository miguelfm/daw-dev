#requires -Version 5.1
<#
.SYNOPSIS
Executa o xestor común con concorrencia limitada de verdade (5 postos por defecto).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('PrepararWSL','CopiarModelo')][string]$Action,
    [Parameter(Mandatory)][ValidateRange(1,35)][int[]]$Numero,
    [ValidateRange(1,254)][int]$Aula=34,
    [string]$Dominio='iesrodolfoucha.es',
    [string]$PackageDirectory="$HOME\Projects\daw-aula-paquete-20261111-final",
    [string]$WslMsi=(Join-Path $env:LOCALAPPDATA 'DAW-Aula-Tools\wsl.3.0.5.0.x64.msi'),
    [ValidateRange(1,10)][int]$ThrottleLimit=5,
    [switch]$AutoInicio
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'daw-aula.psm1') -Force
if($Action -eq 'PrepararWSL'){
    $signature=Get-AuthenticodeSignature -LiteralPath $WslMsi
    if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation'){throw 'O MSI debe estar dispoñible e asinado por Microsoft.'}
}else{Assert-DawPackage $PackageDirectory|Out-Null}
$worker={
    param($n,$script,$action,$aula,$domain,$package,$msi,$auto)
    $ErrorActionPreference='Stop'
    try{
        $data=@(& $script -Action $action -Aula $aula -Numero @($n) -Dominio $domain -PackageDirectory $package -WslMsi $msi -AutoInicio:$auto)
        $records=@($data|Where-Object {$_ -and $_.PSObject.Properties['Success'] -and $_.PSObject.Properties['Equipo']})
        if($records.Count -ne 1){throw 'Resposta ausente ou ambigua do xestor.'}
        $records[0]
    }catch{[pscustomobject]@{Equipo=('A{0}EQ{1:D2}.{2}' -f $aula,$n,$domain);Action=$action;Success=$false;Error=$_.Exception.Message;Data=$null}}
}
$arguments=@((Join-Path $PSScriptRoot 'gestionar-aula.ps1'),$Action,$Aula,$Dominio,$PackageDirectory,$WslMsi,$AutoInicio.IsPresent)
$result=@(Invoke-DawBoundedJobs @($Numero|Sort-Object -Unique) $ThrottleLimit $worker $arguments)
$expected=@($Numero|Sort-Object -Unique).Count
if($result.Count -ne $expected){throw 'Faltan resultados dalgúns postos. Non se declara éxito.'}
return $result
