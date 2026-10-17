function Get-PVEConfigKey {
  <#
  .SYNOPSIS
  Returns the option names in a guest configuration as returned by the API (a PSCustomObject from JSON,
  or a hashtable in tests).
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [AllowNull()]
    [object]$Config
  )

  if ($null -eq $Config) {
    return
  }
  if ($Config -is [System.Collections.IDictionary]) {
    $Config.Keys | ForEach-Object { [string]$_ }
    return
  }
  $Config.PSObject.Properties.Name
}
