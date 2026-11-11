#requires -Version 5.1
<#
.SYNOPSIS
Apaga de forma remota e segura os equipos da aula, excluíndo sempre o equipo do profesor (.100).
.DESCRIPTION
1. Exclúe estritamente o equipo 100 para protexer o posto docente.
2. Tenta o apagado en paralelo mediante WinRM (Invoke-Command con Kerberos polo porto 5985).
3. Para os equipos que non teñan WinRM habilitado ou fallen na resolución DNS (ex. EQ14),
   aplica automaticamente o apagado por rede mediante RPC/SMB directo (shutdown.exe /m) e PsExec sobre a súa IP.
4. Realiza unha comprobación de rede final para confirmar o apagado completo.
.EXAMPLE
.\apagar-aula.ps1 -Aula 34
.EXAMPLE
.\apagar-aula.ps1 -Aula 34 -Numero (1..15)
#>
[CmdletBinding()]
param(
    [ValidateRange(1,254)][int]$Aula = 34,
    [ValidateRange(1,35)][int[]]$Numero = (1..35),
    [string]$Dominio = 'iesrodolfoucha.es',
    [int]$TempoEsperaSegundos = 0,
    [switch]$Forzar = $true
)

$ErrorActionPreference = 'Continue'

# Exclusión estrita do posto do profesor (100)
$Numero = $Numero | Where-Object { $_ -ne 100 }
if (-not $Numero) {
    Write-Warning "Non se especificaron equipos válidos (o equipo 100 está sempre excluído)."
    return
}

$forceFlag = if ($Forzar) { '/f' } else { '' }
$psExec = (Join-Path $env:LOCALAPPDATA 'DAW-Aula-Tools\PsExec64.exe')

Write-Host "Iniciando proceso de apagado remoto da Aula $Aula (equipos $($Numero.Count), excluíndo o 100)..." -ForegroundColor Cyan

# 1. Fase WinRM en paralelo (máxima velocidade para equipos con WinRM activo)
$nomes = $Numero | ForEach-Object { 'A{0}EQ{1:D2}.{2}' -f $Aula, $_, $Dominio }

Write-Host "Fase 1: Enviando orde por WinRM en paralelo..." -ForegroundColor Yellow
$winrmErros = @()
$winrmOk = Invoke-Command -ComputerName $nomes -Authentication Kerberos -ThrottleLimit 35 -ErrorVariable winrmErros -ErrorAction SilentlyContinue -ScriptBlock {
    param($t, $f)
    & shutdown.exe /s /t $t $f /d p:2:4
    return $env:COMPUTERNAME
} -ArgumentList $TempoEsperaSegundos, $forceFlag

if ($winrmOk) {
    Write-Host "Equipos que responderon por WinRM ($($winrmOk.Count)):" -ForegroundColor Green
    $winrmOk | Sort-Object | ForEach-Object { Write-Host " - $_" }
}

# 2. Fase de rescate (para equipos sen WinRM ou con anomalías de DNS)
$pendentesNomes = $winrmErros | ForEach-Object { $_.TargetObject } | Select-Object -Unique
$pendentesNumeros = foreach ($nom in $pendentesNomes) {
    if ($nom -match 'EQ(\d+)') { [int]$matches[1] }
}
$pendentesNumeros = $pendentesNumeros | Select-Object -Unique

if ($pendentesNumeros) {
    Write-Host "`nFase 2: Aplicando apagado por IP/SMB/PsExec nos equipos pendentes ($($pendentesNumeros.Count))..." -ForegroundColor Yellow
    foreach ($n in $pendentesNumeros) {
        $ip = "172.21.$Aula.$n"
        $nomeNetBios = 'A{0}EQ{1:D2}' -f $Aula, $n
        
        # Comprobar se está aceso por ping antes de tentar
        if (Test-Connection -ComputerName $ip -Count 1 -Quiet) {
            Write-Host "Tentando apagar equipo $n ($ip)..." -ForegroundColor Cyan
            
            # Intento A: shutdown directo por SMB á IP
            & shutdown.exe /m "\\$ip" /s /t $TempoEsperaSegundos $forceFlag /d p:2:4 2>$null
            if ($LASTEXITCODE -ne 0) {
                # Intento B: shutdown por nome NetBIOS
                & shutdown.exe /m "\\$nomeNetBios" /s /t $TempoEsperaSegundos $forceFlag /d p:2:4 2>$null
            }
            if ($LASTEXITCODE -ne 0 -and (Test-Path -LiteralPath $psExec)) {
                # Intento C: PsExec directo sobre a IP
                & $psExec "\\$ip" -s -accepteula -nobanner shutdown.exe /s /t $TempoEsperaSegundos $forceFlag 2>$null
            }
        }
    }
}

# 3. Comprobación final
Write-Host "`nFase 3: Comprobando estado final da aula..." -ForegroundColor Cyan
Start-Sleep -Seconds 3
$acesos = $Numero | ForEach-Object { "172.21.$Aula.$_" } | Where-Object { Test-Connection -ComputerName $_ -Count 1 -Quiet }

if ($acesos) {
    Write-Warning "Equipos que aínda responden a ping (poden estar pechando servizos): $($acesos -join ', ')"
} else {
    Write-Host "CONFIRMADO: Todos os equipos de alumnos da Aula $Aula están completamente apagados." -ForegroundColor Green
    Write-Host "O posto do profesor (.100) permanece aceso e protexido." -ForegroundColor Green
}
