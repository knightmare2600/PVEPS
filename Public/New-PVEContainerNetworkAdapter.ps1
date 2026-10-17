function New-PVEContainerNetworkAdapter {
  <#
  .SYNOPSIS
  Adds a network adapter to LXC containers.
  .DESCRIPTION
  Adds a netN entry at the lowest free index (or -Index) with PUT /nodes/{node}/lxc/{vmid}/config, and
  writes the new PVEPS.ContainerNetworkAdapter object. The interface inside the container is named
  eth<index> unless -InterfaceName is given; it gets its IPv4 address by DHCP unless -IPAddress is given.
  PVE generates the MAC address unless -MacAddress is given.
  .PARAMETER VMId
  Container ID(s). Binds from piped PVEPS.Container objects.
  .PARAMETER VMName
  Container name(s). Wildcards allowed.
  .PARAMETER Bridge
  Bridge to connect the adapter to, for example vmbr0.
  .PARAMETER InterfaceName
  Interface name inside the container. Defaults to eth<index>.
  .PARAMETER IPAddress
  IPv4 address in CIDR notation (192.0.2.10/24), dhcp, or manual. Defaults to dhcp.
  .PARAMETER Gateway
  IPv4 gateway.
  .PARAMETER IPv6Address
  IPv6 address in CIDR notation, auto, dhcp, or manual.
  .PARAMETER Gateway6
  IPv6 gateway.
  .PARAMETER VlanTag
  VLAN tag (1 to 4094).
  .PARAMETER Firewall
  Enable the PVE firewall on this adapter.
  .PARAMETER MacAddress
  MAC address, for example BC:24:11:12:34:56.
  .PARAMETER Mtu
  MTU of the interface.
  .PARAMETER RateLimitMBps
  Rate limit in megabytes per second.
  .PARAMETER Disconnected
  Add the adapter with its link down.
  .PARAMETER Index
  Index of the adapter, for example 1 for net1. Defaults to the lowest free index.
  .PARAMETER Parameter
  Further adapter options by their API names.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  New-PVEContainerNetworkAdapter -VMId 200 -Bridge vmbr1 -IPAddress 198.51.100.5/24
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestChange.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.ContainerNetworkAdapter')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Bridge,

    [ValidatePattern('^[-_.\w\d]+$')]
    [string]$InterfaceName,

    [ValidateNotNullOrEmpty()]
    [string]$IPAddress = 'dhcp',

    [ValidateNotNullOrEmpty()]
    [string]$Gateway,

    [ValidateNotNullOrEmpty()]
    [string]$IPv6Address,

    [ValidateNotNullOrEmpty()]
    [string]$Gateway6,

    [ValidateRange(1, 4094)]
    [int]$VlanTag,

    [switch]$Firewall,

    [ValidatePattern('^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$')]
    [string]$MacAddress,

    [ValidateRange(1, 65535)]
    [int]$Mtu,

    [ValidateRange(0, [double]::MaxValue)]
    [double]$RateLimitMBps,

    [switch]$Disconnected,

    [ValidateRange(0, [int]::MaxValue)]
    [int]$Index,

    [hashtable]$Parameter,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $option = [ordered]@{ name = if ($InterfaceName) { $InterfaceName } else { 'eth{index}' }; bridge = $Bridge }
    if ($MacAddress) { $option.hwaddr = $MacAddress.ToUpperInvariant() }
    $option.ip = $IPAddress
    if ($Gateway) { $option.gw = $Gateway }
    if ($IPv6Address) { $option.ip6 = $IPv6Address }
    if ($Gateway6) { $option.gw6 = $Gateway6 }
    if ($PSBoundParameters.ContainsKey('VlanTag')) { $option.tag = $VlanTag }
    if ($Firewall) { $option.firewall = 1 }
    if ($PSBoundParameters.ContainsKey('Mtu')) { $option.mtu = $Mtu }
    if ($PSBoundParameters.ContainsKey('RateLimitMBps')) { $option.rate = $RateLimitMBps.ToString([cultureinfo]::InvariantCulture) }
    if ($Disconnected) { $option.link_down = 1 }
    if ($Parameter) {
      foreach ($key in $Parameter.Keys) {
        $option[$key] = $Parameter[$key]
      }
    }
    $value = ConvertTo-PVEPropertyString -Option $option
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName
  }

  end {
    foreach ($guest in @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type lxc -Target $targets)) {
      $slot = if ($PSBoundParameters.ContainsKey('Index')) { $Index } else { -1 }
      Add-PVEGuestDevice -Cmdlet $PSCmdlet -Guest $guest -Prefix net -Index $slot -Value $value -Kind ContainerNetworkAdapter -Description "Add network adapter {key} on $Bridge"
    }
  }
}
