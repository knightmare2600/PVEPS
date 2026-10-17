function Get-PVEVMSnapshot {
  <#
  .SYNOPSIS
  Gets the snapshots of QEMU virtual machines.
  .DESCRIPTION
  Writes one PVEPS.Snapshot object per snapshot, oldest first, from GET
  /nodes/{node}/qemu/{vmid}/snapshot. IsCurrent marks the snapshot the VM is running from (the parent of
  its current state). IncludesMemory says whether the snapshot saved the RAM (vmstate).
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM or PVEPS.Snapshot objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed. Templates are included.
  .PARAMETER Snapshot
  Snapshot name(s) to return. Wildcards allowed. All snapshots if omitted.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Get-PVEVM web01 | Get-PVEVMSnapshot
  .EXAMPLE
  Get-PVEVMSnapshot -VMName '*' | Where-Object Created -LT (Get-Date).AddDays(-30)
  #>
  [CmdletBinding(DefaultParameterSetName = 'Id')]
  [OutputType('PVEPS.Snapshot')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [Parameter(ValueFromPipelineByPropertyName)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Snapshot,

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
    foreach ($selection in @(Resolve-PVESnapshotTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets -IncludeTemplate)) {
      $selection.Snapshots
    }
  }
}
