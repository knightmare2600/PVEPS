function Backup-PVEContainer {
  <#
  .SYNOPSIS
  Backs up containers with vzdump.
  .DESCRIPTION
  Starts one backup task per node (POST /nodes/{node}/vzdump) for all the containers given, waits for it,
  and writes each new backup as a PVEPS.StorageContent object. Options not given come from PVE's own
  backup defaults (its vzdump configuration). Restore-PVEBackup restores one; Remove-PVEStorageContent
  deletes one.
  .PARAMETER VMId
  Container ID(s). Binds from piped PVEPS.Container objects.
  .PARAMETER VMName
  Container name(s). Wildcards allowed.
  .PARAMETER Storage
  Storage to write the backups to. It must allow backups.
  .PARAMETER Mode
  snapshot (the default; needs storage that supports snapshots), suspend, or stop (the container is shut down for the backup and started again).
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
  Backup-PVEContainer -VMId 200 -Storage local
  .EXAMPLE
  Get-PVEContainer | Backup-PVEContainer -Storage backups -Compress zstd
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
    $guests = @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type lxc -Target $targets)
    Invoke-PVEBackup -Cmdlet $PSCmdlet -Guest $guests -Body $body -Storage $Storage -Description "Back up$where$how" -RunAsync:$RunAsync
  }
}
