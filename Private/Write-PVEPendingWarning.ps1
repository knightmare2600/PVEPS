function Write-PVEPendingWarning {
  <#
  .SYNOPSIS
  Warns when a running guest has configuration changes that PVE has not applied yet.
  .DESCRIPTION
  Some changes to a running guest (for example memory without hotplug) are stored as pending and only
  take effect when the guest is next started. Reads GET /nodes/{node}/{type}/{vmid}/pending and writes
  one warning listing every option with a pending value or a pending delete. Does nothing for a guest
  that is not running.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [psobject]$Guest
  )

  if ($Guest.Status -ne 'running') {
    return
  }
  $path = Format-PVEPath '/nodes/{node}/{type}/{vmid}/pending' @{ node = $Guest.Node; type = $Guest.Type; vmid = $Guest.VMId }
  $keys = @(
    Invoke-PVERequest -Connection $Guest.Connection -Path $path |
      Where-Object { $null -ne (Get-PVEValue $_ 'pending') -or [int](Get-PVEValue $_ 'delete') -gt 0 } |
      ForEach-Object { [string](Get-PVEValue $_ 'key') }
  )
  if ($keys.Count -gt 0) {
    $restart = if ($Guest.Type -eq 'lxc') { 'Restart-PVEContainer' } else { 'Restart-PVEVMGuest, or Stop then Start' }
    Write-Warning ('{0} is running; these changes are pending until it is next started ({1}): {2}' -f (Get-PVEGuestLabel -Guest $Guest), $restart, ($keys -join ', '))
  }
}
