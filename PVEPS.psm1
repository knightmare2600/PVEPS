#-----Script Info---------------------------------------------------------------------------------------------
# Name:PVEPS.psm1
# Author: Einar Stenberg
# mail:einar@stenberg.im
# Date: 09.03.15
# Version: 1
# Job/Tasks: Powershell module for interfacing with Proxmox VE
#--------------------------------------------------------------------------------------------------------------


#-----Changelog------------------------------------------------------------------------------------------------
#v1.  Script created ES
#v2.0.0  2026-10-16  RM  Rewrite for PowerShell 7 and Proxmox VE 9.x. Module split into Public/ and Private/,
#        manifest added. Connections now use the /api2/json formatter, PSCredential or API token auth,
#        automatic ticket renewal and per-connection certificate handling. Task cmdlets added. The v1
#        cmdlets (Get-PVEVM, Get-PVECT, Get-PVENode, Set-PVEVM) are removed and will be re-implemented
#        PowerCLI-style in later phases; see git history for the v1 code.
#
#--------------------------------------------------------------------------------------------------------------


Set-StrictMode -Version 3.0

# Connections opened in this session, and the one cmdlets use when -Server is not given.
$script:PVEConnections = [System.Collections.Generic.List[psobject]]::new()
$script:DefaultPVEConnection = $null

# Secrets (tickets, CSRF tokens, credentials, token headers) keyed by connection Id. Kept out of the
# connection object itself so that displaying or exporting a connection can never leak them.
$script:PVEAuthState = @{}

# PVE tickets are valid for two hours; renew well inside that window.
$script:PVETicketRenewAfter = [timespan]::FromMinutes(60)

foreach ($folder in 'Private', 'Public') {
  $path = Join-Path -Path $PSScriptRoot -ChildPath $folder
  foreach ($file in Get-ChildItem -Path $path -Filter '*.ps1' -File) {
    . $file.FullName
  }
}

Export-ModuleMember -Function (Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -File).BaseName
