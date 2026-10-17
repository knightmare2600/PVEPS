@{
  RootModule           = 'PVEPS.psm1'
  ModuleVersion        = '2.0.0'
  GUID                 = 'cba37351-781d-47f8-a322-03cd19ea9834'
  Author               = 'Einar Stenberg, Robert McLay'
  Copyright            = '(c) 2018 Einar Stenberg, (c) 2026 Robert McLay. Licensed under GPLv3.'
  Description          = 'PowerShell module for managing Proxmox VE through its REST API, in the style of VMware PowerCLI.'
  PowerShellVersion    = '7.4'
  CompatiblePSEditions = @('Core')
  FormatsToProcess     = @('PVEPS.Format.ps1xml')
  FunctionsToExport    = @(
    'Connect-PVE'
    'ConvertTo-PVEContainerTemplate'
    'ConvertTo-PVEVMTemplate'
    'Copy-PVEContainer'
    'Copy-PVEVM'
    'Disconnect-PVE'
    'Get-PVEConnection'
    'Get-PVEContainer'
    'Get-PVENode'
    'Get-PVEPool'
    'Get-PVEStorage'
    'Get-PVETask'
    'Get-PVEVM'
    'Invoke-PVEApi'
    'Move-PVEContainer'
    'Move-PVEVM'
    'New-PVEContainer'
    'New-PVEVM'
    'Remove-PVEContainer'
    'Remove-PVEVM'
    'Restart-PVEContainer'
    'Restart-PVEVM'
    'Restart-PVEVMGuest'
    'Resume-PVEVM'
    'Set-PVEContainer'
    'Set-PVEVM'
    'Start-PVEContainer'
    'Start-PVEVM'
    'Stop-PVEContainer'
    'Stop-PVEContainerGuest'
    'Stop-PVEVM'
    'Stop-PVEVMGuest'
    'Suspend-PVEVM'
    'Wait-PVETask'
  )
  CmdletsToExport      = @()
  VariablesToExport    = @()
  AliasesToExport      = @()
  PrivateData          = @{
    PSData = @{
      Tags       = @('Proxmox', 'PVE', 'Virtualisation', 'Linux', 'MacOS', 'Windows', 'PSEdition_Core')
      LicenseUri = 'https://www.gnu.org/licenses/gpl-3.0.html'
      ProjectUri = 'https://github.com/knightmare2600/PVEPS'
    }
  }
}
