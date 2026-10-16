function Resolve-PVEConnection {
  <#
  .SYNOPSIS
  Turns a -Server argument (connection objects, server names, or nothing) into open connection objects.
  .DESCRIPTION
  With no -Server, returns the default connection. Strings are matched against the Server name of open
  connections (wildcards allowed). Throws if nothing usable is found.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [AllowNull()]
    [object[]]$Server
  )

  if (-not $Server) {
    if ($null -eq $script:DefaultPVEConnection) {
      throw 'Not connected to a Proxmox VE server. Run Connect-PVE first, or pass -Server.'
    }
    return $script:DefaultPVEConnection
  }

  foreach ($item in $Server) {
    if ($item -is [psobject] -and $item.PSObject.TypeNames -contains 'PVEPS.Connection') {
      if (-not $script:PVEAuthState.ContainsKey($item.Id)) {
        throw "The connection to $($item.Server) has been disconnected. Run Connect-PVE again."
      }
      $item
      continue
    }

    $name = [string]$item
    $found = @($script:PVEConnections | Where-Object { $_.Server -like $name })
    if ($found.Count -eq 0) {
      throw "No open connection matches server '$name'. Run Connect-PVE first."
    }
    foreach ($match in $found) {
      $match
    }
  }
}
