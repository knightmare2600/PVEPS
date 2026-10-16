function ConvertTo-PVEGB {
  <#
  .SYNOPSIS
  Converts a byte count to GiB rounded to two places (PowerCLI's *GB properties are also binary GiB),
  passing $null through.
  #>
  [CmdletBinding()]
  [OutputType([double])]
  param(
    [AllowNull()]
    [object]$Bytes
  )

  if ($null -eq $Bytes -or [string]::IsNullOrEmpty([string]$Bytes)) {
    return $null
  }
  [math]::Round([double]$Bytes / 1GB, 2)
}
