function Set-PVEContainerNetworkAdapter {
  <#
  .SYNOPSIS
  Changes LXC container network adapters: bridge, addresses, VLAN, link state and other options.
  .DESCRIPTION
  Rewrites each adapter's netN entry with PUT /nodes/{node}/lxc/{vmid}/config, keeping every option not
  named, and writes the adapter as now configured. An empty string removes an address or gateway.
  .PARAMETER VMId
  Container ID. Binds from piped PVEPS.ContainerNetworkAdapter or PVEPS.Container objects.
  .PARAMETER VMName
  Container name(s). Wildcards allowed.
  .PARAMETER Device
  Adapter(s) to change, for example net0. Binds from piped PVEPS.ContainerNetworkAdapter objects.
  .PARAMETER Bridge
  Bridge to connect the adapter to.
  .PARAMETER InterfaceName
  Interface name inside the container.
  .PARAMETER IPAddress
  IPv4 address in CIDR notation, dhcp, or manual.
  .PARAMETER Gateway
  IPv4 gateway.
  .PARAMETER IPv6Address
  IPv6 address in CIDR notation, auto, dhcp, or manual.
  .PARAMETER Gateway6
  IPv6 gateway.
  .PARAMETER VlanTag
  VLAN tag (1 to 4094); 0 removes the tag.
  .PARAMETER Connected
  $false takes the link down; $true brings it up.
  .PARAMETER Firewall
  Whether the PVE firewall applies to this adapter.
  .PARAMETER MacAddress
  MAC address.
  .PARAMETER Mtu
  MTU; 0 removes the setting.
  .PARAMETER RateLimitMBps
  Rate limit in megabytes per second; 0 removes the limit.
  .PARAMETER Parameter
  Further adapter options by their API names; a $null value removes the option.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Set-PVEContainerNetworkAdapter -VMId 200 -Device net0 -IPAddress 192.0.2.20/24 -Gateway 192.0.2.1
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

    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Device,

    [ValidateNotNullOrEmpty()]
    [string]$Bridge,

    [ValidatePattern('^[-_.\w\d]+$')]
    [string]$InterfaceName,

    [AllowEmptyString()]
    [string]$IPAddress,

    [AllowEmptyString()]
    [string]$Gateway,

    [AllowEmptyString()]
    [string]$IPv6Address,

    [AllowEmptyString()]
    [string]$Gateway6,

    [ValidateRange(0, 4094)]
    [int]$VlanTag,

    [bool]$Connected,

    [bool]$Firewall,

    [ValidatePattern('^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$')]
    [string]$MacAddress,

    [ValidateRange(0, 65535)]
    [int]$Mtu,

    [ValidateRange(0, [double]::MaxValue)]
    [double]$RateLimitMBps,

    [hashtable]$Parameter,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $changes = [ordered]@{}
    if ($Bridge) { $changes.bridge = $Bridge }
    if ($InterfaceName) { $changes.name = $InterfaceName }
    foreach ($pair in @(@('IPAddress', 'ip'), @('Gateway', 'gw'), @('IPv6Address', 'ip6'), @('Gateway6', 'gw6'))) {
      if ($PSBoundParameters.ContainsKey($pair[0])) {
        $value = $PSBoundParameters[$pair[0]]
        $changes[$pair[1]] = if ($value) { $value } else { $null }
      }
    }
    if ($PSBoundParameters.ContainsKey('VlanTag')) { $changes.tag = if ($VlanTag -gt 0) { $VlanTag } else { $null } }
    if ($PSBoundParameters.ContainsKey('Connected')) { $changes.link_down = if ($Connected) { $null } else { 1 } }
    if ($PSBoundParameters.ContainsKey('Firewall')) { $changes.firewall = [int]$Firewall }
    if ($MacAddress) { $changes.hwaddr = $MacAddress.ToUpperInvariant() }
    if ($PSBoundParameters.ContainsKey('Mtu')) { $changes.mtu = if ($Mtu -gt 0) { $Mtu } else { $null } }
    if ($PSBoundParameters.ContainsKey('RateLimitMBps')) { $changes.rate = if ($RateLimitMBps -gt 0) { $RateLimitMBps.ToString([cultureinfo]::InvariantCulture) } else { $null } }
    if ($Parameter) {
      foreach ($key in $Parameter.Keys) {
        $changes[$key] = $Parameter[$key]
      }
    }
    if ($changes.Count -eq 0) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message 'No change given; specify at least one setting.' -Target $null))
    }
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName -Device $Device
  }

  end {
    foreach ($selection in @(Resolve-PVEDeviceTarget -Cmdlet $PSCmdlet -Type lxc -Target $targets -Kind ContainerNetworkAdapter -Noun 'network adapter')) {
      foreach ($adapter in $selection.Devices) {
        $action = 'Set network adapter {0}: {1}' -f $adapter.Device, (@($changes.Keys) -join ', ')
        if (Set-PVEGuestDeviceOption -Cmdlet $PSCmdlet -Guest $selection.Guest -Device $adapter.Device -Kind ContainerNetworkAdapter -Change $changes -Description $action) {
          Write-PVEDeviceResult -Cmdlet $PSCmdlet -Guest $selection.Guest -Kind ContainerNetworkAdapter -Device $adapter.Device
        }
      }
    }
  }
}
