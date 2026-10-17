function Add-PVEGuestTarget {
  <#
  .SYNOPSIS
  Collects -VMId / -Name targets from a cmdlet's process block into a list, one entry per connection
  and value, for Resolve-PVEGuestTarget to resolve in the end block. Device cmdlets also pass -Device,
  the device names (or patterns) given with that ID or name, which each entry carries.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCmdlet]$Cmdlet,

    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [System.Collections.Generic.List[psobject]]$Target,

    [AllowNull()]
    [object[]]$Server,

    [AllowNull()]
    [int[]]$VMId,

    [AllowNull()]
    [string[]]$Name,

    [AllowNull()]
    [string[]]$Device
  )

  try {
    $connections = @(Resolve-PVEConnection -Server $Server)
  }
  catch {
    $Cmdlet.WriteError($_)
    return
  }

  foreach ($connection in $connections) {
    foreach ($id in $VMId) {
      $Target.Add([pscustomobject]@{ Connection = $connection; VMId = $id; Name = $null; Device = $Device })
    }
    foreach ($item in $Name) {
      $Target.Add([pscustomobject]@{ Connection = $connection; VMId = $null; Name = $item; Device = $Device })
    }
  }
}
