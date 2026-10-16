function Add-PVEGuestTarget {
  <#
  .SYNOPSIS
  Collects -VMId / -Name targets from a power cmdlet's process block into a list, one entry per
  connection and value, for Invoke-PVEPowerAction to resolve in the end block.
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
    [string[]]$Name
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
      $Target.Add([pscustomobject]@{ Connection = $connection; VMId = $id; Name = $null })
    }
    foreach ($item in $Name) {
      $Target.Add([pscustomobject]@{ Connection = $connection; VMId = $null; Name = $item })
    }
  }
}
