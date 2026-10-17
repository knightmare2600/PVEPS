function Get-PVEContainerVolume {
  <#
  .SYNOPSIS
  Gets the root file system and mount points of LXC containers.
  .DESCRIPTION
  Reads each container's configuration and writes one PVEPS.ContainerVolume object for rootfs and one
  per mpN mount point, including bind mounts (IsBindMount). The configuration PVE returns has pending
  changes applied.
  .PARAMETER VMId
  Container ID(s). Binds from piped PVEPS.Container objects.
  .PARAMETER VMName
  Container name(s). Wildcards allowed. Templates are included.
  .PARAMETER Device
  Volume(s) to return: rootfs, mp0, 'mp*' and so on. All if omitted.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Get-PVEContainer dns01 | Get-PVEContainerVolume
  .EXAMPLE
  Get-PVEContainerVolume -VMName '*' -Device rootfs | Sort-Object SizeGB
  #>
  [CmdletBinding(DefaultParameterSetName = 'Id')]
  [OutputType('PVEPS.ContainerVolume')]
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
    foreach ($selection in @(Resolve-PVEDeviceTarget -Cmdlet $PSCmdlet -Type lxc -Target $targets -Kind ContainerVolume -Noun 'volume' -IncludeTemplate)) {
      $selection.Devices
    }
  }
}
