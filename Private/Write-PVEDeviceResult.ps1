function Write-PVEDeviceResult {
  <#
  .SYNOPSIS
  After a device change: warns about pending changes if the guest is running, then writes the device
  as now configured (or nothing for -Device $null, after a removal).
  .DESCRIPTION
  The configuration PVE returns has pending changes applied, so the device written shows the requested
  state even when PVE will only apply it at the next start; the warning says so.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCmdlet]$Cmdlet,

    [Parameter(Mandatory)]
    [psobject]$Guest,

    [Parameter(Mandatory)]
    [string]$Kind,

    [AllowNull()]
    [string]$Device
  )

  try {
    $null = Update-PVEGuestStatus -Guest $Guest
    Write-PVEPendingWarning -Guest $Guest
    if ($Device) {
      Get-PVEGuestDevice -Guest $Guest -Kind $Kind | Where-Object { $_.Device -eq $Device }
    }
  }
  catch {
    $Cmdlet.WriteError($_)
  }
}
