function Test-PVEWildcardMatch {
  <#
  .SYNOPSIS
  True if -Value matches any of -Pattern (wildcards allowed), or if no pattern is given.
  #>
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [AllowNull()]
    [AllowEmptyString()]
    [string]$Value,

    [AllowNull()]
    [string[]]$Pattern
  )

  if (-not $Pattern) {
    return $true
  }
  foreach ($item in $Pattern) {
    if ($Value -like $item) {
      return $true
    }
  }
  $false
}
