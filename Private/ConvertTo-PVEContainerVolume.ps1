function ConvertTo-PVEContainerVolume {
  <#
  .SYNOPSIS
  Converts an LXC rootfs or mpN entry into a PVEPS.ContainerVolume object.
  .DESCRIPTION
  Path is the mount path inside the container ('/' for rootfs). IsBindMount is true for mount points
  whose source is a host path rather than a storage volume; those have no Storage or SizeGB.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [psobject]$Guest,

    [Parameter(Mandatory)]
    [string]$Device,

    [Parameter(Mandatory)]
    [string]$Value
  )

  $option = ConvertFrom-PVEPropertyString -Value $Value -DefaultKey volume
  $volume = [string]$option['volume']
  $isBind = $volume.StartsWith('/')
  [pscustomobject]@{
    PSTypeName  = 'PVEPS.ContainerVolume'
    VMId        = $Guest.VMId
    VMName      = $Guest.Name
    Node        = $Guest.Node
    Device      = $Device
    Path        = if ($Device -eq 'rootfs') { '/' } else { $option['mp'] }
    Volume      = $volume
    Storage     = if (-not $isBind -and $volume -match '^([^:/]+):') { $Matches[1] } else { $null }
    SizeGB      = ConvertTo-PVEGB (ConvertFrom-PVESize ([string]$option['size']))
    ReadOnly    = $option['ro'] -eq '1'
    IsBindMount = $isBind
    Options     = $option
    Type        = 'lxc'
    Connection  = $Guest.Connection
  }
}
