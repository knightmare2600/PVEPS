function Get-PVEVMNetworkAdapter {
  <#
  .SYNOPSIS
  Gets the network adapters of QEMU virtual machines.
  .DESCRIPTION
  Reads each VM's configuration and writes one PVEPS.VMNetworkAdapter object per netN entry. The
  configuration PVE returns has pending changes applied.

  Device is the configuration key (for example net0); Options holds every option of the entry.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed. Templates are included.
  .PARAMETER Device
  Adapter(s) to return, for example net0. All adapters if omitted.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Get-PVEVM web01 | Get-PVEVMNetworkAdapter
  .EXAMPLE
  Get-PVEVMNetworkAdapter -VMName '*' | Where-Object Bridge -EQ 'vmbr1'
  #>
  [CmdletBinding(DefaultParameterSetName = 'Id')]
  [OutputType('PVEPS.VMNetworkAdapter')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [Parameter(ValueFromPipelineByPropertyName)]
    [SupportsWildcards()]
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
    foreach ($selection in @(Resolve-PVEDeviceTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets -Kind VMNetworkAdapter -Noun 'network adapter' -IncludeTemplate)) {
      $selection.Devices
    }
  }
}
