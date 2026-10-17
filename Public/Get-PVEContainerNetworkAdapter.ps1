function Get-PVEContainerNetworkAdapter {
  <#
  .SYNOPSIS
  Gets the network adapters of LXC containers.
  .DESCRIPTION
  Reads each container's configuration and writes one PVEPS.ContainerNetworkAdapter object per netN
  entry, with the interface name, bridge, MAC and IP settings. The configuration PVE returns has pending
  changes applied.
  .PARAMETER VMId
  Container ID(s). Binds from piped PVEPS.Container objects.
  .PARAMETER VMName
  Container name(s). Wildcards allowed. Templates are included.
  .PARAMETER Device
  Adapter(s) to return, for example net0. All adapters if omitted.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Get-PVEContainer dns01 | Get-PVEContainerNetworkAdapter
  .EXAMPLE
  Get-PVEContainerNetworkAdapter -VMName '*' | Select-Object VMName, InterfaceName, IPAddress
  #>
  [CmdletBinding(DefaultParameterSetName = 'Id')]
  [OutputType('PVEPS.ContainerNetworkAdapter')]
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
    foreach ($selection in @(Resolve-PVEDeviceTarget -Cmdlet $PSCmdlet -Type lxc -Target $targets -Kind ContainerNetworkAdapter -Noun 'network adapter' -IncludeTemplate)) {
      $selection.Devices
    }
  }
}
