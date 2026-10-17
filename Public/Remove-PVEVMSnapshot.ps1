function Remove-PVEVMSnapshot {
  <#
  .SYNOPSIS
  Deletes VM snapshots.
  .DESCRIPTION
  Deletes each snapshot with DELETE /nodes/{node}/qemu/{vmid}/snapshot/{snapname} and waits for the
  tasks.
  The VM's current state is not changed. Prompts for confirmation by default (ConfirmImpact High). Writes
  nothing (with -RunAsync, the tasks).
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM or PVEPS.Snapshot objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER Snapshot
  Snapshot name(s). Wildcards allowed. Binds from piped PVEPS.Snapshot objects.
  .PARAMETER Force
  Remove the snapshot from the configuration even if removing the disk snapshots fails (the API's force
  option). Disk snapshots left behind then have to be cleaned up on the storage by hand.
  .PARAMETER RunAsync
  Return the task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Remove-PVEVMSnapshot -VMId 100 -Snapshot before-upgrade
  .EXAMPLE
  Get-PVEVMSnapshot -VMName '*' | Where-Object Created -LT (Get-Date).AddDays(-30) | Remove-PVEVMSnapshot -Confirm:$false
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVESnapshotOperation.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'High')]
  [OutputType('PVEPS.Task')]
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

    [switch]$Force,

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
        $selection.Snapshots | ForEach-Object { [pscustomobject]@{ Guest = $selection.Guest; Snapshot = $_.Snapshot } }
      }
    )
    $body = if ($Force) { @{ force = 1 } } else { @{} }
    Invoke-PVESnapshotOperation -Cmdlet $PSCmdlet -Item $items -Method DELETE -Suffix '/{snapshot}' -Body $body -Description 'Delete snapshot {snapshot}' -Output None -RunAsync:$RunAsync
  }
}
