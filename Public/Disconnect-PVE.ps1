function Disconnect-PVE {
  <#
  .SYNOPSIS
  Closes one or more Proxmox VE connections.
  .DESCRIPTION
  Discards the ticket, CSRF token, stored credential or token secret held for the connection. The PVE API
  has no logout endpoint, so an issued ticket stays valid on the server until it expires (two hours after
  it was issued or last renewed).

  If the default connection is closed, the most recently opened remaining connection becomes the default.
  .PARAMETER Server
  Connection objects, or server names (wildcards allowed; '*' closes every connection). Defaults to the
  default connection.
  .EXAMPLE
  Disconnect-PVE
  .EXAMPLE
  Disconnect-PVE -Server *
  #>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
  param(
    [Parameter(ValueFromPipeline, Position = 0)]
    [object[]]$Server
  )

  process {
    try {
      $connections = @(Resolve-PVEConnection -Server $Server)
    }
    catch {
      $PSCmdlet.WriteError($_)
      return
    }

    foreach ($connection in $connections) {
      if (-not $PSCmdlet.ShouldProcess("$($connection.User) on $($connection.Server)", 'Disconnect')) {
        continue
      }
      $script:PVEAuthState.Remove($connection.Id)
      $connection.IsConnected = $false
      $index = $script:PVEConnections.FindIndex({ param($c) $c.Id -eq $connection.Id })
      if ($index -ge 0) {
        $script:PVEConnections.RemoveAt($index)
      }
      if ($script:DefaultPVEConnection -and $script:DefaultPVEConnection.Id -eq $connection.Id) {
        $script:DefaultPVEConnection = if ($script:PVEConnections.Count) { $script:PVEConnections[-1] } else { $null }
      }
      Write-Verbose "Disconnected $($connection.User) from $($connection.Server)"
    }
  }
}
