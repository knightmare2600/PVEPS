function Get-PVERrdData {
  <#
  .SYNOPSIS
  Reads an rrddata endpoint and writes one PVEPS.Stat object per sample.
  .DESCRIPTION
  The API schema does not describe the samples' fields, so every field except time is copied through
  unchanged, under its PVE name (for example cpu, mem, maxmem, netin), in the units PVE uses. Timestamp
  is the sample's time as a local DateTime. Samples with no value besides the time (gaps in the RRD) are
  left out, as are samples outside -Start / -Finish. -Metric keeps only the matching fields.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [psobject]$Connection,

    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string]$Timeframe,

    [string]$Consolidation,

    [string[]]$Metric,

    [AllowNull()]
    [Nullable[datetime]]$Start,

    [AllowNull()]
    [Nullable[datetime]]$Finish,

    # Identifies what the samples belong to: Entity, Node, VMId, Storage.
    [Parameter(Mandatory)]
    [System.Collections.IDictionary]$Identity
  )

  $parameters = @{ timeframe = $Timeframe }
  if ($Consolidation) {
    $parameters.cf = $Consolidation.ToUpperInvariant()
  }
  foreach ($sample in @(Invoke-PVERequest -Connection $Connection -Path $Path -Parameters $parameters)) {
    $time = Get-PVEValue $sample 'time'
    if ($null -eq $time) {
      continue
    }
    $timestamp = ConvertFrom-PVEUnixTime $time
    if (($Start -and $timestamp -lt $Start) -or ($Finish -and $timestamp -gt $Finish)) {
      continue
    }
    $values = [ordered]@{}
    foreach ($name in (Get-PVEConfigKey -Config $sample)) {
      if ($name -eq 'time' -or -not (Test-PVEWildcardMatch -Value $name -Pattern $Metric)) {
        continue
      }
      $values[$name] = Get-PVEValue $sample $name
    }
    if (@($values.Values | Where-Object { $null -ne $_ }).Count -eq 0) {
      continue
    }
    $item = [ordered]@{ PSTypeName = 'PVEPS.Stat'; Timestamp = $timestamp }
    foreach ($key in $Identity.Keys) {
      $item[$key] = $Identity[$key]
    }
    foreach ($key in $values.Keys) {
      $item[$key] = $values[$key]
    }
    $item.Connection = $Connection
    [pscustomobject]$item
  }
}
