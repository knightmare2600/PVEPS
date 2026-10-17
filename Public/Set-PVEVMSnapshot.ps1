function Set-PVEVMSnapshot {
  <#
  .SYNOPSIS
  Changes the description of VM snapshots.
  .DESCRIPTION
  Sends the description with PUT /nodes/{node}/qemu/{vmid}/snapshot/{snapname}/config and writes the
  snapshot as it now is. The description is the only snapshot property the API can change.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM or PVEPS.Snapshot objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER Snapshot
  Snapshot name(s). Wildcards allowed. Binds from piped PVEPS.Snapshot objects.
  .PARAMETER Description
  New description. An empty string clears it.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Set-PVEVMSnapshot -VMId 100 -Snapshot before-upgrade -Description 'Kept until the upgrade is signed off'
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVESnapshotOperation.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.Snapshot')]
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

    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [string]$Description,

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
    Invoke-PVESnapshotOperation -Cmdlet $PSCmdlet -Item $items -Method PUT -Suffix '/{snapshot}/config' -Body @{ description = $Description } -Description 'Set the description of snapshot {snapshot}' -Output Snapshot
  }
}
