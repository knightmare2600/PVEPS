function Get-PVEConnection {
  <#
  .SYNOPSIS
  Lists the open Proxmox VE connections in this session.
  .DESCRIPTION
  Writes the PVEPS.Connection objects that Connect-PVE created and Disconnect-PVE has not closed, in the
  order they were opened. -Default writes only the default connection: the one cmdlets use when -Server
  is not given (the newest connection, unless it was opened with -NotDefault). The objects hold no
  secrets; tickets, CSRF tokens and token secrets are kept inside the module.
  .PARAMETER Server
  Server name filter; wildcards allowed.
  .PARAMETER Default
  Return only the default connection.
  .EXAMPLE
  Get-PVEConnection
  .EXAMPLE
  Get-PVEConnection -Default
  #>
  [CmdletBinding(DefaultParameterSetName = 'All')]
  [OutputType('PVEPS.Connection')]
  param(
    [Parameter(Position = 0, ParameterSetName = 'All')]
    [string]$Server = '*',

    [Parameter(Mandatory, ParameterSetName = 'Default')]
    [switch]$Default
  )

  if ($Default) {
    return $script:DefaultPVEConnection
  }
  $script:PVEConnections | Where-Object { $_.Server -like $Server }
}
