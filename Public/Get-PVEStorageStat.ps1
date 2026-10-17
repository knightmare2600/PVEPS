function Get-PVEStorageStat {
  <#
  .SYNOPSIS
  Gets usage statistics of storages from PVE's round-robin database.
  .DESCRIPTION
  Writes one PVEPS.Stat object per sample from GET /nodes/{node}/storage/{storage}/rrddata. The API schema does not describe
  the samples, so each field is passed through under its PVE name and in PVE's units (for example cpu as
  a fraction of the storage's CPUs, mem and maxmem in bytes, netin and netout in bytes per second);
  Timestamp is the sample time. Samples with no values (gaps) are left out.
  The storages are found with Get-PVEStorage; inactive ones are skipped with a warning.
  .PARAMETER Storage
  Storage name(s). Wildcards allowed. Binds from piped PVEPS.Storage objects.
  .PARAMETER Node
  Node name(s). Wildcards allowed. Binds from piped objects.
  .PARAMETER Timeframe
  hour (the default), day, week, month or year. PVE keeps fewer, coarser samples the longer the
  time frame.
  .PARAMETER Consolidation
  Average or Max: how PVE combines the raw values into each sample. PVE's default applies if omitted.
  .PARAMETER Metric
  Only these fields, for example cpu or 'net*'. Wildcards allowed.
  .PARAMETER Start
  Only samples at or after this time.
  .PARAMETER Finish
  Only samples at or before this time.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Get-PVEStorageStat local-lvm -Timeframe month -Metric used, total
  #>
  [CmdletBinding()]
  [OutputType('PVEPS.Stat')]
  param(
    [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
    [Alias('Name')]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Storage,

    [Parameter(ValueFromPipelineByPropertyName)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Node,

    [ValidateSet('hour', 'day', 'week', 'month', 'year')]
    [string]$Timeframe = 'hour',

    [ValidateSet('Average', 'Max')]
    [string]$Consolidation,

    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Metric,

    [datetime]$Start,

    [datetime]$Finish,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  process {
    $find = @{ Server = $Server }
    if ($Storage) { $find.Name = $Storage }
    if ($Node) { $find.Node = $Node }
    foreach ($store in @(Get-PVEStorage @find)) {
      if (-not $store.Active) {
        Write-Warning "Storage $($store.Name) on $($store.Node) is not active; skipped."
        continue
      }
      $path = Format-PVEPath '/nodes/{node}/storage/{storage}/rrddata' @{ node = $store.Node; storage = $store.Name }
      $identity = [ordered]@{ Entity = "Storage $($store.Name) on $($store.Node)"; Node = $store.Node; Storage = $store.Name }
      try {
        Get-PVERrdData -Connection $store.Connection -Path $path -Timeframe $Timeframe -Consolidation $Consolidation -Metric $Metric -Start $(if ($PSBoundParameters.ContainsKey('Start')) { $Start }) -Finish $(if ($PSBoundParameters.ContainsKey('Finish')) { $Finish }) -Identity $identity
      }
      catch {
        $PSCmdlet.WriteError($_)
      }
    }
  }
}
