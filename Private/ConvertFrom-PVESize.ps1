function ConvertFrom-PVESize {
  <#
  .SYNOPSIS
  Converts a PVE disk-size value such as '32G', '512M' or '4M' to bytes.
  .DESCRIPTION
  The suffix is K, M, G or T in powers of 1024; a number without a suffix is bytes. This is the format of
  the size= option PVE writes into disk and volume entries, and of the resize endpoints' size parameter
  (whose schema pattern is \+?\d+(\.\d+)?[KMGT]?). Returns $null for anything else.
  #>
  [CmdletBinding()]
  [OutputType([long])]
  param(
    [AllowNull()]
    [AllowEmptyString()]
    [string]$Size
  )

  if ($Size -notmatch '^(\d+(?:\.\d+)?)([KMGT]?)$') {
    return $null
  }
  $factor = switch ($Matches[2]) {
    'K' { 1KB }
    'M' { 1MB }
    'G' { 1GB }
    'T' { 1TB }
    default { 1 }
  }
  [long]([double]::Parse($Matches[1], [cultureinfo]::InvariantCulture) * $factor)
}
