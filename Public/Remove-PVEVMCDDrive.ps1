function Remove-PVEVMCDDrive {
  <#
  .SYNOPSIS
  Removes CD drives from QEMU virtual machines.
  .DESCRIPTION
  Removes each drive entry with POST /nodes/{node}/qemu/{vmid}/config (delete=<drive>). The ISO itself is
  not touched. To keep the drive and only take the ISO out, use Set-PVEVMCDDrive -NoMedia. On a running
  VM the removal can be pending until the next start, and a warning says so. Writes nothing.
  .PARAMETER VMId
  VM ID. Binds from piped PVEPS.CDDrive objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER Device
  Drive(s) to remove, for example ide2. Binds from piped PVEPS.CDDrive objects.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Remove-PVEVMCDDrive -VMId 100 -Device ide2
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestChange.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType([void])]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Device,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName -Device $Device
  }

  end {
    foreach ($selection in @(Resolve-PVEDeviceTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets -Kind CDDrive -Noun 'CD drive')) {
      foreach ($drive in $selection.Devices) {
        Remove-PVEGuestDevice -Cmdlet $PSCmdlet -Guest $selection.Guest -Device $drive.Device -Kind CDDrive -Description "Remove CD drive $($drive.Device)"
      }
    }
  }
}
