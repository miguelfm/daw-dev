#requires -Version 5.1
<#
.SYNOPSIS
Comproba WinRM e Veyon sen modificar os equipos. Por defecto, aula 34, equipos 1-35.
.EXAMPLE
.\comprobar-remoto.ps1 -Aula 31 -Numero 1 | Format-Table -AutoSize
#>
[CmdletBinding()]
param(
    [ValidateRange(1,254)][int]$Aula = 34,
    [ValidateRange(1,35)][int[]]$Numero = (1..35),
    [string]$Dominio = 'iesrodolfoucha.es',
    [ValidateRange(200,10000)][int]$TimeoutMs = 2500
)
$ErrorActionPreference = 'Stop'
$pending = foreach ($n in $Numero) {
    foreach ($port in 5985,5986,11100) {
        $client = New-Object System.Net.Sockets.TcpClient
        [pscustomobject]@{
            Numero = $n; Address = "172.21.$Aula.$n"; Port = $port
            Client = $client; Async = $client.BeginConnect("172.21.$Aula.$n", $port, $null, $null)
        }
    }
}
Start-Sleep -Milliseconds $TimeoutMs
$ports = @{}
foreach ($request in $pending) {
    $open = $false
    try {
        if ($request.Async.IsCompleted) { $request.Client.EndConnect($request.Async); $open = $true }
    } catch { } finally { $request.Client.Dispose() }
    $ports["$($request.Numero):$($request.Port)"] = $open
}
foreach ($n in $Numero) {
    $computer = 'A{0}EQ{1:D2}.{2}' -f $Aula,$n,$Dominio
    $wsman = 'Sen resposta TCP'
    if ($ports["${n}:5985"]) {
        try { $null = Test-WSMan -ComputerName $computer -ErrorAction Stop; $wsman = 'WSMan responde' }
        catch { $wsman = $_.Exception.Message }
    }
    [pscustomobject]@{
        Equipo = $computer; IP = "172.21.$Aula.$n"
        WinRM_HTTP = $ports["${n}:5985"]; WinRM_HTTPS = $ports["${n}:5986"]
        Veyon = $ports["${n}:11100"]; Diagnostico = $wsman
    }
}
