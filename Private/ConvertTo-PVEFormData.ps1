function ConvertTo-PVEFormData {
  <#
  .SYNOPSIS
  Encodes a parameter hashtable as application/x-www-form-urlencoded text for the PVE API.
  .DESCRIPTION
  Used for both query strings (GET/DELETE) and request bodies (POST/PUT). Booleans and switches are sent
  as 1/0, which is what the PVE API expects for its boolean type. $null values are omitted. Array values
  are sent as repeated keys.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [hashtable]$Parameters
  )

  if (-not $Parameters -or $Parameters.Count -eq 0) {
    return ''
  }

  $pairs = foreach ($key in ($Parameters.Keys | Sort-Object)) {
    $value = $Parameters[$key]
    if ($null -eq $value) {
      continue
    }
    $items = if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) { $value } else { , $value }
    foreach ($item in $items) {
      if ($item -is [bool] -or $item -is [System.Management.Automation.SwitchParameter]) {
        $item = if ([bool]$item) { 1 } else { 0 }
      }
      '{0}={1}' -f [uri]::EscapeDataString([string]$key), [uri]::EscapeDataString([string]$item)
    }
  }
  $pairs -join '&'
}
