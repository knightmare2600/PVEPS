function Backup-PVEVM {
  <#
  .SYNOPSIS
  Backs up VMs with vzdump.
  .DESCRIPTION
  Starts one backup task per node (POST /nodes/{node}/vzdump) for all the VMs given, waits for it,
  and writes each new backup as a PVEPS.StorageContent object. Options not given come from PVE's own
  backup defaults (its vzdump configuration). Restore-PVEBackup restores one; Remove-PVEStorageContent
  deletes one.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER Storage
  Storage to write the backups to. It must allow backups.
  .PARAMETER Mode
  snapshot (the default: the VM keeps running), suspend, or stop (the VM is shut down for the backup and started again).
  .PARAMETER Compress
  zstd, gzip, lzo, or none.
  .PARAMETER Notes
  Notes for the backup. PVE replaces {{guestname}}, {{vmid}}, {{node}} and {{cluster}}, and the API
  documentation requires a single line.
  .PARAMETER Protected
  Protect the backup, so it cannot be deleted (or pruned) until it is unprotected.
  .PARAMETER RunAsync
  Return the task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Backup-PVEVM -VMId 100 -Storage local
  .EXAMPLE
  Get-PVEVM 'web*' | Backup-PVEVM -Storage backups -Mode snapshot
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEBackup.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.StorageContent', 'PVEPS.Task')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [ValidateNotNullOrEmpty()]
    [string]$Storage,

    [ValidateSet('snapshot', 'suspend', 'stop')]
    [string]$Mode,

    [ValidateSet('zstd', 'gzip', 'lzo', 'none')]
    [string]$Compress,

    [ValidatePattern('^[^\r\n]*$')]
    [string]$Notes,

    [switch]$Protected,

    [switch]$RunAsync,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $body = @{}
    if ($Storage) { $body.storage = $Storage }
    if ($Mode) { $body.mode = $Mode }
    if ($Compress) { $body.compress = if ($Compress -eq 'none') { '0' } else { $Compress } }
    if ($Notes) { $body['notes-template'] = $Notes }
    if ($Protected) { $body.protected = 1 }
    $where = if ($Storage) { " to $Storage" } else { '' }
    $how = if ($Mode) { " (mode $Mode)" } else { '' }
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName
  }

  end {
    $guests = @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets)
    Invoke-PVEBackup -Cmdlet $PSCmdlet -Guest $guests -Body $body -Storage $Storage -Description "Back up$where$how" -RunAsync:$RunAsync
  }
}
