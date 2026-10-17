function Get-PVEGuestLabel {
  <#
  .SYNOPSIS
  Returns the text used for a guest in ShouldProcess prompts, warnings and errors, for example
  'VM 100 (web01) on pve'.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)]
    [psobject]$Guest
  )

  $kind = if ($Guest.Type -eq 'lxc') { 'Container' } else { 'VM' }
  '{0} {1} ({2}) on {3}' -f $kind, $Guest.VMId, $Guest.Name, $Guest.Node
}
