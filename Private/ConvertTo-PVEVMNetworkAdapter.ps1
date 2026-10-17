function ConvertTo-PVEVMNetworkAdapter {
  <#
  .SYNOPSIS
  Converts one QEMU netN entry into a PVEPS.VMNetworkAdapter object.
  .DESCRIPTION
  PVE writes the model and MAC address as the first item, model=MAC ('virtio=BC:24:11:00:00:01'), and
  accepts model=<model>,macaddr=<MAC> or a bare model too. Options holds model and macaddr under those
  names whichever form was used, followed by the other options in their original order.
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

  $option = ConvertFrom-PVENetworkOption -Value $Value
  $tag = $option['tag']
  [pscustomobject]@{
    PSTypeName = 'PVEPS.VMNetworkAdapter'
    VMId       = $Guest.VMId
    VMName     = $Guest.Name
    Node       = $Guest.Node
    Device     = $Device
    Model      = $option['model']
    MacAddress = $option['macaddr']
    Bridge     = $option['bridge']
    VlanTag    = if ($null -ne $tag) { [int]$tag } else { $null }
    Connected  = $option['link_down'] -ne '1'
    Firewall   = $option['firewall'] -eq '1'
    Options    = $option
    Type       = 'qemu'
    Connection = $Guest.Connection
  }
}
