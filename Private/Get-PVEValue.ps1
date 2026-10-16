function Get-PVEValue {
  <#
  .SYNOPSIS
  Reads a member from an API response object, returning $null if the object or member is absent.
  .DESCRIPTION
  The module runs under Set-StrictMode -Version 3.0, where reading a property that does not exist throws.
  The PVE API omits optional fields entirely rather than sending null, so every read of API data goes
  through this function. Array values are returned intact (not unrolled).
  #>
  [CmdletBinding()]
  [OutputType([object], [object[]], [array])]
  param(
    [Parameter(Position = 0)]
    [AllowNull()]
    [object]$InputObject,

    [Parameter(Mandatory, Position = 1)]
    [string]$Name
  )

  if ($null -eq $InputObject) {
    return $null
  }
  if ($InputObject -is [System.Collections.IDictionary]) {
    return , $InputObject[$Name]
  }
  $property = $InputObject.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  , $property.Value
}
