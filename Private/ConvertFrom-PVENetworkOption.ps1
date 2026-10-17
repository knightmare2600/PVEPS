function ConvertFrom-PVENetworkOption {
  <#
  .SYNOPSIS
  Parses a QEMU netN value into an ordered table that starts with model and macaddr.
  .DESCRIPTION
  The first item is model=MAC as PVE writes it ('virtio=BC:24:11:00:00:01'), model=<model>, or a bare
  model. Any first item whose key is not 'model' is read as the model=MAC form, so no list of model names
  is needed here.
  #>
  [CmdletBinding()]
  [OutputType([System.Collections.Specialized.OrderedDictionary])]
  param(
    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [string]$Value
  )

  $first, $rest = $Value -split ',', 2
  $result = [ordered]@{ model = $null; macaddr = $null }
  $pos = $first.IndexOf('=')
  if ($pos -lt 0) {
    $result.model = $first
  }
  elseif ($first.Substring(0, $pos) -eq 'model') {
    $result.model = $first.Substring($pos + 1)
  }
  else {
    $result.model = $first.Substring(0, $pos)
    $result.macaddr = $first.Substring($pos + 1)
  }
  if ($rest) {
    $others = ConvertFrom-PVEPropertyString -Value $rest
    foreach ($key in $others.Keys) {
      $result[$key] = $others[$key]
    }
  }
  $result
}
