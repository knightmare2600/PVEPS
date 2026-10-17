function Get-PVEConsoleUrl {
  <#
  .SYNOPSIS
  Returns the PVE web interface URL of a guest's noVNC console.
  .DESCRIPTION
  The query string is the one pve-manager's openVNCViewer (www/manager6/Utils.js) builds: console (kvm or
  lxc), novnc=1, vmid, vmname, node, resize (the interface's default is off) and cmd (empty).
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)]
    [psobject]$Guest,

    [Parameter(Mandatory)]
    [ValidateSet('kvm', 'lxc')]
    [string]$Console
  )

  $query = [ordered]@{
    console = $Console
    novnc   = 1
    vmid    = $Guest.VMId
    vmname  = $Guest.Name
    node    = $Guest.Node
    resize  = 'off'
    cmd     = ''
  }
  $pairs = foreach ($key in $query.Keys) {
    '{0}={1}' -f $key, [uri]::EscapeDataString([string]$query[$key])
  }
  '{0}/?{1}' -f $Guest.Connection.BaseUri, ($pairs -join '&')
}
