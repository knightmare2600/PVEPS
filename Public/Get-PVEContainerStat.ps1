function Get-PVEContainerStat {
  <#
  .SYNOPSIS
  Gets performance statistics of containers from PVE's round-robin database.
  .DESCRIPTION
  Writes one PVEPS.Stat object per sample from GET /nodes/{node}/lxc/{vmid}/rrddata. The API schema does not describe
  the samples, so each field is passed through under its PVE name and in PVE's units (for example cpu as
  a fraction of the container's CPUs, mem and maxmem in bytes, netin and netout in bytes per second);
  Timestamp is the sample time. Samples with no values (gaps) are left out.
  .PARAMETER VMId
  Container ID(s). Binds from piped PVEPS.Container objects.
  .PARAMETER VMName
  Container name(s). Wildcards allowed.
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
  Get-PVEContainerStat -VMId 200 -Timeframe day -Metric cpu, mem
  .EXAMPLE
  Get-PVEContainer | Get-PVEContainerStat -Metric cpu | Group-Object VMName | ForEach-Object { [pscustomobject]@{ VMName = $_.Name; AverageCpu = ($_.Group.cpu | Measure-Object -Average).Average } }
  #>
  [CmdletBinding(DefaultParameterSetName = 'Id')]
  [OutputType('PVEPS.Stat')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

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

  begin {
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName
  }

  end {
    foreach ($guest in @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type lxc -Target $targets -IncludeTemplate)) {
      $path = Format-PVEPath '/nodes/{node}/lxc/{vmid}/rrddata' @{ node = $guest.Node; vmid = $guest.VMId }
      $identity = [ordered]@{ Entity = Get-PVEGuestLabel -Guest $guest; Node = $guest.Node; VMId = $guest.VMId; VMName = $guest.Name }
      try {
        Get-PVERrdData -Connection $guest.Connection -Path $path -Timeframe $Timeframe -Consolidation $Consolidation -Metric $Metric -Start $(if ($PSBoundParameters.ContainsKey('Start')) { $Start }) -Finish $(if ($PSBoundParameters.ContainsKey('Finish')) { $Finish }) -Identity $identity
      }
      catch {
        $PSCmdlet.WriteError($_)
      }
    }
  }
}
