function ConvertTo-PVEContainerNetworkAdapter {
  <#
  .SYNOPSIS
  Converts one LXC netN entry into a PVEPS.ContainerNetworkAdapter object.
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

  $option = ConvertFrom-PVEPropertyString -Value $Value
  $tag = $option['tag']
  [pscustomobject]@{
    PSTypeName    = 'PVEPS.ContainerNetworkAdapter'
    VMId          = $Guest.VMId
    VMName        = $Guest.Name
    Node          = $Guest.Node
    Device        = $Device
    InterfaceName = $option['name']
    Bridge        = $option['bridge']
    MacAddress    = $option['hwaddr']
    IPAddress     = $option['ip']
    Gateway       = $option['gw']
    IPv6Address   = $option['ip6']
    Gateway6      = $option['gw6']
    VlanTag       = if ($null -ne $tag) { [int]$tag } else { $null }
    Connected     = $option['link_down'] -ne '1'
    Firewall      = $option['firewall'] -eq '1'
    Options       = $option
    Type          = 'lxc'
    Connection    = $Guest.Connection
  }
}
