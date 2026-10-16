function ConvertFrom-PVEUnixTime {
  <#
  .SYNOPSIS
  Converts a PVE epoch-seconds value to a local DateTime, passing $null through.
  #>
  [CmdletBinding()]
  [OutputType([datetime])]
  param(
    [AllowNull()]
    [object]$Seconds
  )

  if ($null -eq $Seconds -or [string]::IsNullOrEmpty([string]$Seconds)) {
    return $null
  }
  [DateTimeOffset]::FromUnixTimeSeconds([long]$Seconds).LocalDateTime
}
