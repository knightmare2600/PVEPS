function Restore-PVEContainerSnapshot {
  <#
  .SYNOPSIS
  Rolls containers back to a snapshot.
  .DESCRIPTION
  Rolls back with POST /nodes/{node}/lxc/{vmid}/snapshot/{snapname}/rollback, waits for the task, and
  writes the container with its live status. Everything since the snapshot is lost, which is why this
  prompts for
  confirmation by default (ConfirmImpact High). The snapshot itself is kept.

  Exactly one snapshot per container: a name or pattern matching several snapshots of one container is
  an error for that
  container.
  .PARAMETER VMId
  Container ID(s). Binds from piped PVEPS.Container or PVEPS.Snapshot objects.
  .PARAMETER VMName
  Container name(s). Wildcards allowed.
  .PARAMETER Snapshot
  Snapshot name. Wildcards allowed. Binds from piped PVEPS.Snapshot objects.
  .PARAMETER PowerOn
  Start the container after rolling back.
  .PARAMETER RunAsync
  Return the task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Restore-PVEContainerSnapshot -VMId 200 -Snapshot before-upgrade
  .EXAMPLE
  Get-PVEContainerSnapshot -VMId 200 | Where-Object IsCurrent | Restore-PVEContainerSnapshot -PowerOn -Confirm:$false
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVESnapshotOperation.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'High')]
  [OutputType('PVEPS.Container', 'PVEPS.Task')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Snapshot,

    [switch]$PowerOn,

    [switch]$RunAsync,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName -Device $Snapshot
  }

  end {
    $items = @(
      foreach ($selection in @(Resolve-PVESnapshotTarget -Cmdlet $PSCmdlet -Type lxc -Target $targets -IncludeTemplate)) {
        if ($selection.Snapshots.Count -gt 1) {
          $names = @($selection.Snapshots | ForEach-Object { $_.Snapshot }) -join ', '
          $PSCmdlet.WriteError((New-PVEArgumentError -Message "$(Get-PVEGuestLabel -Guest $selection.Guest): $($selection.Snapshots.Count) snapshots match ($names); roll back to exactly one." -Target $selection.Snapshots))
          continue
        }
        $selection.Snapshots | ForEach-Object { [pscustomobject]@{ Guest = $selection.Guest; Snapshot = $_.Snapshot } }
      }
    )
    $body = if ($PowerOn) { @{ start = 1 } } else { @{} }
    Invoke-PVESnapshotOperation -Cmdlet $PSCmdlet -Item $items -Method POST -Suffix '/{snapshot}/rollback' -Body $body -Description 'Roll back to snapshot {snapshot}, discarding everything since' -Output Guest -RunAsync:$RunAsync
  }
}
