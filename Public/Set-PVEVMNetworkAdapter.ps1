function Set-PVEVMNetworkAdapter {
  <#
  .SYNOPSIS
  Changes QEMU network adapters: bridge, VLAN, link state, model, MAC and other options.
  .DESCRIPTION
  Rewrites each adapter's netN entry with POST /nodes/{node}/qemu/{vmid}/config, keeping every option not
  named (changing -Model keeps the MAC address). Writes each adapter as now configured. On a running VM
  some changes are pending until the next start, and a warning says so.
  .PARAMETER VMId
  VM ID. Binds from piped PVEPS.VMNetworkAdapter or PVEPS.VM objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER Device
  Adapter(s) to change, for example net0. Binds from piped PVEPS.VMNetworkAdapter objects.
  .PARAMETER Bridge
  Bridge to connect the adapter to.
  .PARAMETER Model
  Adapter model.
  .PARAMETER MacAddress
  MAC address.
  .PARAMETER VlanTag
  VLAN tag (1 to 4094); 0 removes the tag.
  .PARAMETER Connected
  $false takes the link down (unplugs the adapter); $true brings it up.
  .PARAMETER Firewall
  Whether the PVE firewall applies to this adapter.
  .PARAMETER Mtu
  MTU (VirtIO only); 0 removes the setting.
  .PARAMETER Queues
  Number of packet queues; 0 removes the setting.
  .PARAMETER RateLimitMBps
  Rate limit in megabytes per second; 0 removes the limit.
  .PARAMETER Parameter
  Further adapter options by their API names; a $null value removes the option.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Set-PVEVMNetworkAdapter -VMId 100 -Device net0 -VlanTag 30
  .EXAMPLE
  Get-PVEVM lab* | Get-PVEVMNetworkAdapter -Device net1 | Set-PVEVMNetworkAdapter -Connected $false
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestChange.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.VMNetworkAdapter')]
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

    [ValidateSet('e1000', 'e1000-82540em', 'e1000-82544gc', 'e1000-82545em', 'e1000e', 'i82551', 'i82557b', 'i82559er', 'ne2k_isa', 'ne2k_pci', 'pcnet', 'rtl8139', 'virtio', 'vmxnet3')]
    [string]$Model,

    [ValidatePattern('^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$')]
    [string]$MacAddress,

    [ValidateRange(0, 4094)]
    [int]$VlanTag,

    [bool]$Connected,

    [bool]$Firewall,

    [ValidateRange(0, 65520)]
    [int]$Mtu,

    [ValidateRange(0, 64)]
    [int]$Queues,

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
    if ($Model) { $changes.model = $Model }
    if ($MacAddress) { $changes.macaddr = $MacAddress.ToUpperInvariant() }
    if ($PSBoundParameters.ContainsKey('VlanTag')) { $changes.tag = if ($VlanTag -gt 0) { $VlanTag } else { $null } }
    if ($PSBoundParameters.ContainsKey('Connected')) { $changes.link_down = if ($Connected) { $null } else { 1 } }
    if ($PSBoundParameters.ContainsKey('Firewall')) { $changes.firewall = [int]$Firewall }
    if ($PSBoundParameters.ContainsKey('Mtu')) { $changes.mtu = if ($Mtu -gt 0) { $Mtu } else { $null } }
    if ($PSBoundParameters.ContainsKey('Queues')) { $changes.queues = if ($Queues -gt 0) { $Queues } else { $null } }
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
    foreach ($selection in @(Resolve-PVEDeviceTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets -Kind VMNetworkAdapter -Noun 'network adapter')) {
      foreach ($adapter in $selection.Devices) {
        $action = 'Set network adapter {0}: {1}' -f $adapter.Device, (@($changes.Keys) -join ', ')
        if (Set-PVEGuestDeviceOption -Cmdlet $PSCmdlet -Guest $selection.Guest -Device $adapter.Device -Kind VMNetworkAdapter -Change $changes -Description $action) {
          Write-PVEDeviceResult -Cmdlet $PSCmdlet -Guest $selection.Guest -Kind VMNetworkAdapter -Device $adapter.Device
        }
      }
    }
  }
}
