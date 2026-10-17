function ConvertTo-PVEPropertyString {
  <#
  .SYNOPSIS
  Builds a PVE property string from an ordered table, the reverse of ConvertFrom-PVEPropertyString.
  .DESCRIPTION
  The -DefaultKey value is written first, without its key (as PVE itself writes it). The other options
  follow as key=value in their order in the table. Options whose value is $null are left out, which is
  how callers remove an option. Booleans are written as 1/0.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)]
    [System.Collections.IDictionary]$Option,

    [string]$DefaultKey
  )

  $items = [System.Collections.Generic.List[string]]::new()
  if ($DefaultKey -and $null -ne $Option[$DefaultKey]) {
    $items.Add([string]$Option[$DefaultKey])
  }
  foreach ($key in $Option.Keys) {
    if ($key -eq $DefaultKey) {
      continue
    }
    $value = $Option[$key]
    if ($null -eq $value) {
      continue
    }
    if ($value -is [bool]) {
      $value = [int]$value
    }
    $items.Add(('{0}={1}' -f $key, $value))
  }
  $items -join ','
}
