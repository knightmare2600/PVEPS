function Remove-PVEVMNetworkAdapter {
  <#
  .SYNOPSIS
  Removes network adapters from QEMU virtual machines.
  .DESCRIPTION
  Removes each netN entry with POST /nodes/{node}/qemu/{vmid}/config (delete=netN). Its MAC address is
  lost with it. Prompts for confirmation by default (ConfirmImpact High). On a running VM, PVE hot-unplugs
  the adapter if it can; otherwise the removal is pending until the next start, and a warning says so.
  Writes nothing.
  .PARAMETER VMId
  VM ID. Binds from piped PVEPS.VMNetworkAdapter objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER Device
  Adapter(s) to remove, for example net1. Binds from piped PVEPS.VMNetworkAdapter objects.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Remove-PVEVMNetworkAdapter -VMId 100 -Device net1
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestChange.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'High')]
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
    foreach ($selection in @(Resolve-PVEDeviceTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets -Kind VMNetworkAdapter -Noun 'network adapter')) {
      foreach ($adapter in $selection.Devices) {
        Remove-PVEGuestDevice -Cmdlet $PSCmdlet -Guest $selection.Guest -Device $adapter.Device -Kind VMNetworkAdapter -Description "Remove network adapter $($adapter.Device) ($($adapter.MacAddress) on $($adapter.Bridge))"
      }
    }
  }
}
