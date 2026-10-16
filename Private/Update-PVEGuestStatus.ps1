function Update-PVEGuestStatus {
  <#
  .SYNOPSIS
  Refreshes Status, Uptime and Lock on a PVEPS.VM / PVEPS.Container object from the live
  /nodes/{node}/{type}/{vmid}/status/current endpoint, and returns the object.
  .DESCRIPTION
  /cluster/resources is a cached summary, so a guest started or stopped a moment ago can still show
  its old status there. Power decisions and power cmdlet output use this live endpoint instead.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private helper; only updates a local object from a GET request.')]
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [psobject]$Guest
  )

  $path = Format-PVEPath '/nodes/{node}/{type}/{vmid}/status/current' @{
    node = $Guest.Node
    type = $Guest.Type
    vmid = $Guest.VMId
  }
  $current = Invoke-PVERequest -Connection $Guest.Connection -Path $path

  $status = Get-PVEValue $current 'status'
  if ($status) {
    $Guest.Status = [string]$status
  }
  $uptime = Get-PVEValue $current 'uptime'
  $Guest.Uptime = if ($null -ne $uptime) { [timespan]::FromSeconds([double]$uptime) } else { $null }
  $Guest.Lock = Get-PVEValue $current 'lock'
  $Guest
}
