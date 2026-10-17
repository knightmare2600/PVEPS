function ConvertTo-PVENetworkOptionString {
  <#
  .SYNOPSIS
  Builds a QEMU netN value from a table made by ConvertFrom-PVENetworkOption: model=MAC first (or the
  bare model if there is no MAC yet, so PVE generates one), then the other options.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)]
    [System.Collections.IDictionary]$Option
  )

  $head = if ($Option['macaddr']) { '{0}={1}' -f $Option['model'], $Option['macaddr'] } else { [string]$Option['model'] }
  $others = [ordered]@{}
  foreach ($key in $Option.Keys) {
    if ($key -notin 'model', 'macaddr') {
      $others[$key] = $Option[$key]
    }
  }
  $tail = ConvertTo-PVEPropertyString -Option $others
  if ($tail) { '{0},{1}' -f $head, $tail } else { $head }
}
