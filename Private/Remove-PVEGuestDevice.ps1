function Remove-PVEGuestDevice {
  <#
  .SYNOPSIS
  Removes one device entry from a guest configuration (delete=<device>), with the current digest, and
  warns if the removal is pending on a running guest.
  .DESCRIPTION
  The configuration is read again for each removal, so several removals on one guest each send a current
  digest. -Force adds force=1 (QEMU only: physical removal of a disk's volume).
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on the calling cmdlet by Invoke-PVEGuestChange.')]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'ShouldProcess is called on the calling cmdlet by Invoke-PVEGuestChange.')]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCmdlet]$Cmdlet,

    [Parameter(Mandatory)]
    [psobject]$Guest,

    [Parameter(Mandatory)]
    [string]$Device,

    [Parameter(Mandatory)]
    [string]$Kind,

    [Parameter(Mandatory)]
    [string]$Description,

    [switch]$Force
  )

  try {
    $config = Get-PVEGuestConfig -Guest $Guest
  }
  catch {
    $Cmdlet.WriteError($_)
    return
  }
  $body = @{ delete = $Device; digest = Get-PVEValue $config 'digest' }
  if ($Force) {
    $body.force = 1
  }
  if (Invoke-PVEGuestChange -Cmdlet $Cmdlet -Guest $Guest -Description $Description -Body $body) {
    Write-PVEDeviceResult -Cmdlet $Cmdlet -Guest $Guest -Kind $Kind -Device $null
  }
}
