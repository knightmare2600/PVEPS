function ConvertFrom-PVEPropertyString {
  <#
  .SYNOPSIS
  Parses a PVE property string such as 'local-lvm:vm-100-disk-0,size=32G,ssd=1' into an ordered
  hashtable.
  .DESCRIPTION
  PVE configuration values are comma-separated key=value lists. The first item may omit its key; it then
  belongs to the format's default key (the schema's default_key), given as -DefaultKey: 'file' for QEMU
  drives, 'volume' for LXC rootfs and mount points.
  #>
  [CmdletBinding()]
  [OutputType([System.Collections.Specialized.OrderedDictionary])]
  param(
    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [string]$Value,

    [string]$DefaultKey
  )

  $result = [ordered]@{}
  $first = $true
  foreach ($item in ($Value -split ',')) {
    if ($item -eq '') {
      $first = $false
      continue
    }
    $pos = $item.IndexOf('=')
    if ($pos -lt 0) {
      if ($first -and $DefaultKey) {
        $result[$DefaultKey] = $item
      }
      else {
        $result[$item] = $null
      }
    }
    else {
      $result[$item.Substring(0, $pos)] = $item.Substring($pos + 1)
    }
    $first = $false
  }
  $result
}
