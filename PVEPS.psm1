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
#v2.0.0  2026-10-16  RM  Phase 1 inventory: Get-PVENode, Get-PVEVM, Get-PVEContainer, Get-PVEStorage,
#        Get-PVEPool. Connect-PVE takes -User/-Password by default, with -Token for API tokens.
#v2.0.0  2026-10-16  RM  Phase 2 power: Start/Stop/Restart/Suspend/Resume-PVEVM, Stop/Restart-PVEVMGuest,
#        Start/Stop/Restart-PVEContainer, Stop-PVEContainerGuest. Decisions use live guest status.
#v2.0.0  2026-10-17  RM  Phase 3 lifecycle: New/Set/Copy/Move/Remove-PVEVM and -PVEContainer,
#        ConvertTo-PVEVMTemplate, ConvertTo-PVEContainerTemplate. Output objects now take name, tags,
#        CPU and memory from the live status endpoint.
#v2.0.0  2026-10-17  RM  Phase 4 hardware: Get/New/Set/Remove-PVEVMHardDisk, -PVEVMNetworkAdapter, -PVEVMCDDrive,
#        Get/Set-PVEVMCloudInit, Get/New/Set/Remove-PVEContainerVolume and -PVEContainerNetworkAdapter.
#        Configuration changes send the digest of the configuration they were built from.
#v2.0.0  2026-10-17  RM  Phase 5 snapshots: Get/New/Set/Remove/Restore-PVEVMSnapshot and -PVEContainerSnapshot.
#v2.0.0  2026-10-17  RM  Phase 6 guest agent and console: Get-PVEVMGuest, Invoke-PVEVMScript, Copy-PVEVMGuestFile,
#        Open-PVEVMConsole, Open-PVEContainerConsole.
#v2.0.0  2026-10-17  RM  Phase 7 storage and backups: Get/Set/Remove/Import-PVEStorageContent,
#        Get/Save-PVEApplianceTemplate, Backup-PVEVM, Backup-PVEContainer, Get-PVEBackup, Restore-PVEBackup.
#        Invoke-PVERequest can send multipart uploads.
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
