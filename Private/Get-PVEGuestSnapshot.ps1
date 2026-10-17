function Get-PVEGuestSnapshot {
  <#
  .SYNOPSIS
  Lists a guest's snapshots as PVEPS.Snapshot objects, oldest first.
  .DESCRIPTION
  GET /nodes/{node}/{type}/{vmid}/snapshot also returns an entry named 'current' (the API documentation:
  "identifies the current VM"); it is not a snapshot and is left out. Its parent is the snapshot the
  guest is running from, which is marked IsCurrent, as in PowerCLI.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [psobject]$Guest
  )

  $path = Format-PVEPath '/nodes/{node}/{type}/{vmid}/snapshot' @{ node = $Guest.Node; type = $Guest.Type; vmid = $Guest.VMId }
  $items = @(Invoke-PVERequest -Connection $Guest.Connection -Path $path)
  $current = $items | Where-Object { (Get-PVEValue $_ 'name') -eq 'current' } | Select-Object -First 1
  $currentParent = [string](Get-PVEValue $current 'parent')

  $snapshots = foreach ($item in $items) {
    $name = [string](Get-PVEValue $item 'name')
    if ($name -eq 'current') {
      continue
    }
    $parent = Get-PVEValue $item 'parent'
    $snaptime = Get-PVEValue $item 'snaptime'
    [pscustomobject]@{
      PSTypeName     = 'PVEPS.Snapshot'
      VMId           = $Guest.VMId
      VMName         = $Guest.Name
      Node           = $Guest.Node
      Snapshot       = $name
      Description    = ([string](Get-PVEValue $item 'description')).TrimEnd()
      Created        = if ($null -ne $snaptime) { ConvertFrom-PVEUnixTime $snaptime } else { $null }
      Parent         = if ($parent) { [string]$parent } else { $null }
      IncludesMemory = [bool][int](Get-PVEValue $item 'vmstate')
      IsCurrent      = $name -eq $currentParent
      Type           = $Guest.Type
      Connection     = $Guest.Connection
    }
  }
  @($snapshots) | Sort-Object -Property { if ($_.Created) { $_.Created } else { [datetime]::MaxValue } }, Snapshot
}
