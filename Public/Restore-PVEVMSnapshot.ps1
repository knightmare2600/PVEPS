function Restore-PVEVMSnapshot {
  <#
  .SYNOPSIS
  Rolls VMs back to a snapshot.
  .DESCRIPTION
  Rolls back with POST /nodes/{node}/qemu/{vmid}/snapshot/{snapname}/rollback, waits for the task, and
  writes the VM with its live status. Everything since the snapshot is lost, which is why this prompts
  for
  confirmation by default (ConfirmImpact High). The snapshot itself is kept.

  Exactly one snapshot per VM: a name or pattern matching several snapshots of one VM is an error for
  that
  VM.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM or PVEPS.Snapshot objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER Snapshot
  Snapshot name. Wildcards allowed. Binds from piped PVEPS.Snapshot objects.
  .PARAMETER PowerOn
  Start the VM after rolling back (the API documents that a VM is started anyway after rolling back to a
  snapshot that includes RAM).
  .PARAMETER RunAsync
  Return the task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Restore-PVEVMSnapshot -VMId 100 -Snapshot before-upgrade
  .EXAMPLE
  Get-PVEVMSnapshot -VMId 100 | Where-Object IsCurrent | Restore-PVEVMSnapshot -PowerOn -Confirm:$false
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVESnapshotOperation.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'High')]
  [OutputType('PVEPS.VM', 'PVEPS.Task')]
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
      foreach ($selection in @(Resolve-PVESnapshotTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets -IncludeTemplate)) {
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
