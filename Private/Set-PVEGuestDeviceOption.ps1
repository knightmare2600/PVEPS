function Set-PVEGuestDeviceOption {
  <#
  .SYNOPSIS
  Rewrites one device entry with changed options, keeping every option not named, and sends it with the
  current digest. Returns $true if the change went through.
  .DESCRIPTION
  Reads the configuration, parses the entry the way its kind is written (drives: file first; container
  volumes: volume first; QEMU network adapters: model=MAC first; container network adapters: plain
  key=value), sets each -Change (a $null value removes the option), and writes the entry back.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on the calling cmdlet by Invoke-PVEGuestChange.')]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'ShouldProcess is called on the calling cmdlet by Invoke-PVEGuestChange.')]
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCmdlet]$Cmdlet,

    [Parameter(Mandatory)]
    [psobject]$Guest,

    [Parameter(Mandatory)]
    [string]$Device,

    [Parameter(Mandatory)]
    [ValidateSet('HardDisk', 'CDDrive', 'CloudInitDrive', 'VMNetworkAdapter', 'ContainerVolume', 'ContainerNetworkAdapter')]
    [string]$Kind,

    [Parameter(Mandatory)]
    [System.Collections.IDictionary]$Change,

    [Parameter(Mandatory)]
    [string]$Description
  )

  try {
    $config = Get-PVEGuestConfig -Guest $Guest
  }
  catch {
    $Cmdlet.WriteError($_)
    return $false
  }
  $current = [string](Get-PVEValue $config $Device)
  $defaultKey = switch ($Kind) {
    { $_ -in 'HardDisk', 'CDDrive', 'CloudInitDrive' } { 'file' }
    'ContainerVolume' { 'volume' }
    default { $null }
  }
  $option = if ($Kind -eq 'VMNetworkAdapter') { ConvertFrom-PVENetworkOption -Value $current } else { ConvertFrom-PVEPropertyString -Value $current -DefaultKey $defaultKey }
  foreach ($key in $Change.Keys) {
    $option[$key] = $Change[$key]
  }
  $value = if ($Kind -eq 'VMNetworkAdapter') { ConvertTo-PVENetworkOptionString -Option $option } else { ConvertTo-PVEPropertyString -Option $option -DefaultKey $defaultKey }

  $body = @{ $Device = $value; digest = Get-PVEValue $config 'digest' }
  Invoke-PVEGuestChange -Cmdlet $Cmdlet -Guest $Guest -Description $Description -Body $body
}
