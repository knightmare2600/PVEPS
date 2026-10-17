function New-PVEVMSnapshot {
  <#
  .SYNOPSIS
  Takes a snapshot of QEMU virtual machines.
  .DESCRIPTION
  Takes the snapshot with POST /nodes/{node}/qemu/{vmid}/snapshot, waits for the task, and writes the new
  PVEPS.Snapshot object. Several VMs get a snapshot of the same name, and are waited on together. The
  storage of every disk must support snapshots, or PVE refuses.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM or PVEPS.Snapshot objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER Snapshot
  Name of the new snapshot: up to 40 characters, in the format the API schema calls pve-configid, which
  PVE checks.
  .PARAMETER Description
  Description of the snapshot.
  .PARAMETER IncludeMemory
  Also save the VM's RAM (vmstate). The API documents that rolling back to such a snapshot starts the
  VM.
  .PARAMETER RunAsync
  Return the task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  New-PVEVMSnapshot -VMId 100 -Snapshot before-upgrade -Description 'Before the upgrade'
  .EXAMPLE
  Get-PVEVM 'web*' | New-PVEVMSnapshot -Snapshot nightly
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVESnapshotOperation.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.Snapshot', 'PVEPS.Task')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [Parameter(Mandatory)]
    [ValidateLength(1, 40)]
    [string]$Snapshot,

    [string]$Description,

    [switch]$IncludeMemory,

    [switch]$RunAsync,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $body = @{ snapname = $Snapshot }
    if ($Description) {
      $body.description = $Description
    }
    if ($IncludeMemory) {
      $body.vmstate = 1
    }
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName
  }

  end {
    $items = @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets | ForEach-Object { [pscustomobject]@{ Guest = $_; Snapshot = $Snapshot } })
    Invoke-PVESnapshotOperation -Cmdlet $PSCmdlet -Item $items -Method POST -Body $body -Description 'Take snapshot {snapshot}' -Output Snapshot -RunAsync:$RunAsync
  }
}
