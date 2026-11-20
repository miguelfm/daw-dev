#requires -Version 5.1
<#
.SYNOPSIS
Acende de forma remota mediante Wake-on-LAN (WoL) os equipos da aula.
.DESCRIPTION
Envía o paquete máxico Wake-on-LAN (por difusión UDP e mediante a ferramenta Veyon CLI se está presente)
aos postos solicitados a partir do ficheiro de enderezos MAC rexistrados da aula.
Permite tamén monitorizar o arranque ata que os equipos respondan ao ping.
.EXAMPLE
.\encender-aula.ps1 -Aula 31
.EXAMPLE
.\encender-aula.ps1 -Aula 31 -Numero 1 -MonitorizarArranque
#>
[CmdletBinding()]
param(
    [ValidateRange(1,254)][int]$Aula = 31,
    [ValidateRange(1,35)][int[]]$Numero = (1..30),
    [switch]$MonitorizarArranque = $true,
    [int]$TempoEsperaSegundos = 45
)

$ErrorActionPreference = 'Continue'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Cargar táboa de MACs da aula
$csvPath = Join-Path $scriptDir ("a{0}-macs.csv" -f $Aula)
$macMap = @{}

if (Test-Path -LiteralPath $csvPath) {
    Import-Csv -Path $csvPath -Delimiter ';' | ForEach-Object {
        $num = [int]$_.Equipo
        if ($_.MAC -and $_.MAC.Trim()) {
            $macMap[$num] = $_.MAC.Trim()
        }
    }
}

$veyonCli = "C:\Program Files\Veyon\veyon-cli.exe"
$hasVeyon = Test-Path -LiteralPath $veyonCli

Write-Host "Iniciando acendido remoto Wake-on-LAN para a Aula $Aula..." -ForegroundColor Cyan

$enviados = 0
foreach ($num in $Numero) {
    if (-not $macMap.ContainsKey($num)) {
        Write-Warning "Equipo ${num}: Non hai enderezo MAC dispoñible (ex. equipo en reparación)."
        continue
    }

    $macStr = $macMap[$num]
    $ip = "172.21.$Aula.$num"
    Write-Host "Enviando Magic Packet ao Equipo $('{0:D2}' -f $num) ($ip, MAC: $macStr)..." -ForegroundColor Yellow

    # 1. Enviar mediante Veyon CLI se está dispoñible
    if ($hasVeyon) {
        & $veyonCli power on $macStr 2>$null
    }

    # 2. Enviar paquete UDP broadcast nativo (portos 7 e 9 á subrede e broadcast global)
    try {
        $cleanMac = $macStr -replace '[:-]', ''
        $macBytes = for ($i = 0; $i -lt 12; $i += 2) { [Convert]::ToByte($cleanMac.Substring($i, 2), 16) }
        $packet = [byte[]](@(0xFF) * 6 + ($macBytes * 16))

        $endpoints = @(
            [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse("172.21.$Aula.255"), 9),
            [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse("172.21.$Aula.255"), 7),
            [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Broadcast, 9)
        )

        $udp = New-Object System.Net.Sockets.UdpClient
        $udp.EnableBroadcast = $true
        foreach ($ep in $endpoints) {
            [void]$udp.Send($packet, $packet.Length, $ep)
        }
        $udp.Close()
        $enviados++
    } catch {
        Write-Warning "Fallo no envío UDP para equipo ${num}: $_"
    }
}

Write-Host "`nTotal de paquetes Wake-on-LAN transmitidos: $enviados" -ForegroundColor Green

# Monitorización opcional do arranque
if ($MonitorizarArranque -and $enviados -gt 0) {
    Write-Host "`nMonitorizando o arranque da rede (máx. $TempoEsperaSegundos segundos)..." -ForegroundColor Cyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # Unha canalización non pode ser argumento dun método: vai entre @( ). Co tipo [int[]],
    # PowerShell escolle o construtor da colección e non o da capacidade inicial.
    $pendentes = [System.Collections.Generic.List[int]]::new([int[]]@($Numero | Where-Object { $macMap.ContainsKey($_) }))
    $acesos = [System.Collections.Generic.List[int]]::new()

    while ($sw.Elapsed.TotalSeconds -lt $TempoEsperaSegundos -and $pendentes.Count -gt 0) {
        Start-Sleep -Seconds 3
        $comprobados = @($pendentes)
        foreach ($n in $comprobados) {
            $ip = "172.21.$Aula.$n"
            if (Test-Connection -ComputerName $ip -Count 1 -Quiet) {
                Write-Host "[+$([int]$sw.Elapsed.TotalSeconds)s] Equipo $('{0:D2}' -f $n) ($ip) -> ONLINE" -ForegroundColor Green
                $acesos.Add($n)
                [void]$pendentes.Remove($n)
            }
        }
    }
    $sw.Stop()

    Write-Host "`nResumo do arranque:" -ForegroundColor Cyan
    Write-Host " - Equipos que responderon ($($acesos.Count)): $($acesos -join ', ')" -ForegroundColor Green
    if ($pendentes.Count -gt 0) {
        Write-Host " - Equipos aínda sen resposta ($($pendentes.Count)): $($pendentes -join ', ')" -ForegroundColor Yellow
    }
}
