function Add-PVEGuestDevice {
  <#
  .SYNOPSIS
  Adds one device entry (<Prefix><index> = -Value) to a guest configuration, at -Index or, if -Index is
  negative, the lowest free index, then writes the new device object.
  .DESCRIPTION
  Reads the configuration for the used keys and the digest. '{index}' in -Value is replaced with the
  index chosen (for example name=eth{index} for a container adapter). An index already in use is an error
  (PVEDeviceInUse); PVE would otherwise replace that device. -Count bounds the index search for buses
  with a fixed number of slots.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on the calling cmdlet by Invoke-PVEGuestChange.')]
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCmdlet]$Cmdlet,

    [Parameter(Mandatory)]
    [psobject]$Guest,

    [Parameter(Mandatory)]
    [string]$Prefix,

    [int]$Index = -1,

    [int]$Count = [int]::MaxValue,

    [Parameter(Mandatory)]
    [string]$Value,

    [Parameter(Mandatory)]
    [string]$Kind,

    # ShouldProcess text, with {key} where the device key goes, for example
    # 'Add network adapter {key} on vmbr0'.
    [Parameter(Mandatory)]
    [string]$Description
  )

  try {
    $config = Get-PVEGuestConfig -Guest $Guest
    $used = @(Get-PVEConfigKey -Config $config)
    $slot = if ($Index -ge 0) { $Index } else { Get-PVEFreeDeviceIndex -Prefix $Prefix -Used $used -Count $Count }
  }
  catch {
    $Cmdlet.WriteError($_)
    return
  }
  $key = '{0}{1}' -f $Prefix, $slot
  if ($key -in $used) {
    $Cmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new("$(Get-PVEGuestLabel -Guest $Guest) already has $key."),
        'PVEDeviceInUse',
        [System.Management.Automation.ErrorCategory]::ResourceExists,
        $key))
    return
  }
  $body = @{ $key = $Value.Replace('{index}', [string]$slot); digest = Get-PVEValue $config 'digest' }
  if (Invoke-PVEGuestChange -Cmdlet $Cmdlet -Guest $Guest -Description $Description.Replace('{key}', $key) -Body $body) {
    Write-PVEDeviceResult -Cmdlet $Cmdlet -Guest $Guest -Kind $Kind -Device $key
  }
}
