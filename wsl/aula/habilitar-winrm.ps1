#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
Activa WinRM nun equipo da aula. Executar unha vez como administrador, ou por GPO.
.DESCRIPTION
Restrinxe as regras HTTP de WinRM ao equipo do profesor. Non configura TrustedHosts,
autenticacion Basic, trafico sen cifrar nin LocalAccountTokenFilterPolicy.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][System.Net.IPAddress]$ProfesorIP
)
$ErrorActionPreference = 'Stop'
Enable-PSRemoting -Force -SkipNetworkProfileCheck
$rules = @(Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP*' -ErrorAction Stop)
if ($rules.Count -eq 0) { throw 'Non se atoparon as regras HTTP de WinRM.' }
$rules | Set-NetFirewallRule -RemoteAddress $ProfesorIP.IPAddressToString
Set-Service -Name WinRM -StartupType Automatic
Set-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\WinRM' -Name DelayedAutoStart -Value 0
Write-Output "WinRM preparado. Acceso HTTP permitido desde $ProfesorIP."
Write-Output 'Comproba desde o profesor con Test-WSMan e Invoke-Command usando o nome DNS do equipo.'
