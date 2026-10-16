function Get-PVEConnection {
  <#
  .SYNOPSIS
  Lists the open Proxmox VE connections in this session.
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
