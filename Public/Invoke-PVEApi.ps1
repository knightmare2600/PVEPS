function Invoke-PVEApi {
  <#
  .SYNOPSIS
  Calls any Proxmox VE API endpoint directly, using an open connection's authentication.
  .DESCRIPTION
  An escape hatch for endpoints PVEPS does not yet wrap. Paths are as shown in the PVE API viewer
  (https://<node>:8006/pve-docs/api-viewer/), without the /api2/json prefix. Returns the response's "data"
  member as-is. Non-GET calls honour -WhatIf and -Confirm.
  .PARAMETER Path
  API path, for example '/nodes/pve01/qemu'. Values in the path must already be URL-escaped.
  .PARAMETER Method
  HTTP method. Defaults to GET.
  .PARAMETER Parameters
  API parameters. Sent as a query string for GET/DELETE and as a form body for POST/PUT. Booleans are
  sent as 1/0.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection.
  .EXAMPLE
  Invoke-PVEApi -Path /cluster/resources -Parameters @{ type = 'vm' }
  .EXAMPLE
  Invoke-PVEApi -Method POST -Path /nodes/pve01/qemu/9001/status/start -WhatIf
  #>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
  param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Path,

    [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
    [string]$Method = 'GET',

    [hashtable]$Parameters,

    [object[]]$Server
  )

  try {
    $connections = @(Resolve-PVEConnection -Server $Server)
  }
  catch {
    $PSCmdlet.ThrowTerminatingError($_)
  }

  foreach ($connection in $connections) {
    if ($Method -ne 'GET' -and -not $PSCmdlet.ShouldProcess("$($connection.Server) $Path", $Method)) {
      continue
    }
    try {
      Invoke-PVERequest -Connection $connection -Method $Method -Path $Path -Parameters $Parameters
    }
    catch {
      $PSCmdlet.WriteError($_)
    }
  }
}
