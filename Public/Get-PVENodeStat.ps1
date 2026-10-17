function Get-PVENodeStat {
  <#
  .SYNOPSIS
  Gets performance statistics of nodes from PVE's round-robin database.
  .DESCRIPTION
  Writes one PVEPS.Stat object per sample from GET /nodes/{node}/rrddata. The API schema does not describe
  the samples, so each field is passed through under its PVE name and in PVE's units (for example cpu as
  a fraction of the node's CPUs, mem and maxmem in bytes, netin and netout in bytes per second);
  Timestamp is the sample time. Samples with no values (gaps) are left out.
  .PARAMETER Node
  Node name(s). Wildcards allowed. All online nodes if omitted. Binds from piped PVEPS.Node objects.
  .PARAMETER Timeframe
  hour (the default), day, week, month or year, decade. PVE keeps fewer, coarser samples the longer the
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
  Get-PVENodeStat -Timeframe week -Metric loadavg, cpu
  .EXAMPLE
  Get-PVENode pve01 | Get-PVENodeStat -Consolidation Max -Timeframe day
  #>
  [CmdletBinding()]
  [OutputType('PVEPS.Stat')]
  param(
    [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
    [Alias('Name')]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Node,

    [ValidateSet('hour', 'day', 'week', 'month', 'year', 'decade')]
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
    foreach ($item in @(Get-PVENode -Name $(if ($Node) { $Node } else { '*' }) -Server $Server)) {
      if ($item.Status -ne 'online') {
        Write-Warning "Node $($item.Name) is $($item.Status); skipped."
        continue
      }
      $path = Format-PVEPath '/nodes/{node}/rrddata' @{ node = $item.Name }
      $identity = [ordered]@{ Entity = "Node $($item.Name)"; Node = $item.Name }
      try {
        Get-PVERrdData -Connection $item.Connection -Path $path -Timeframe $Timeframe -Consolidation $Consolidation -Metric $Metric -Start $(if ($PSBoundParameters.ContainsKey('Start')) { $Start }) -Finish $(if ($PSBoundParameters.ContainsKey('Finish')) { $Finish }) -Identity $identity
      }
      catch {
        $PSCmdlet.WriteError($_)
      }
    }
  }
}
