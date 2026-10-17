function Restore-PVEBackup {
  <#
  .SYNOPSIS
  Restores a VM or container from a backup.
  .DESCRIPTION
  Restores with POST /nodes/{node}/qemu (archive=<backup>) for a VM backup, or POST /nodes/{node}/lxc
  (ostemplate=<backup>, restore=1) for a container backup, waits for the task, and writes the restored
  guest with its live status. Whether the backup is of a VM or a container comes from -GuestType, which
  binds from piped PVEPS.StorageContent objects; otherwise it is looked up in the storage's backup list.

  The guest is restored as -VMId. Restoring over an existing guest needs -Force and replaces that guest,
  disks included; that cannot be undone. Prompts for confirmation by default (ConfirmImpact High).
  .PARAMETER Volume
  Backup volume ID, for example local:backup/vzdump-qemu-100-2026_10_17-02_00_00.vma.zst. Binds from
  piped PVEPS.StorageContent objects.
  .PARAMETER VMId
  ID to restore as. Binds from piped objects, so a piped backup restores to its original ID unless
  -VMId is given.
  .PARAMETER GuestType
  qemu or lxc. Binds from piped objects; looked up if omitted.
  .PARAMETER Storage
  Storage for the restored disks. PVE restores to the original storages if omitted.
  .PARAMETER Pool
  Resource pool to add the restored guest to. The API documentation lets VM.Allocate on the pool stand
  in for VM.Allocate on the guest, so a user whose rights are on a pool needs this to restore a new
  guest.
  .PARAMETER Force
  Replace an existing guest with this ID.
  .PARAMETER Unique
  Give the restored guest new random MAC addresses, for example when the original still runs.
  .PARAMETER PowerOn
  Start the guest once it has been restored.
  .PARAMETER Node
  Node to restore on. Binds from piped objects; can be omitted on a single-node server.
  .PARAMETER RunAsync
  Return the task at once instead of waiting.
  .PARAMETER Server
  Connection to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Get-PVEBackup -VMId 100 -Latest | Restore-PVEBackup -VMId 150 -Unique
  .EXAMPLE
  Get-PVEBackup -VMId 100 -Latest | Restore-PVEBackup -Force -Confirm:$false
  #>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  [OutputType('PVEPS.VM', 'PVEPS.Container', 'PVEPS.Task')]
  param(
    [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
    [ValidatePattern('^[^:]+:.+')]
    [string]$Volume,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int]$VMId,

    [Parameter(ValueFromPipelineByPropertyName)]
    [ValidateSet('qemu', 'lxc')]
    [string]$GuestType,

    [ValidateNotNullOrEmpty()]
    [string]$Storage,

    [ValidateNotNullOrEmpty()]
    [string]$Pool,

    [switch]$Force,

    [switch]$Unique,

    [switch]$PowerOn,

    [Parameter(ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string]$Node,

    [switch]$RunAsync,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object]$Server
  )

  process {
    try {
      $connection = Resolve-PVESingleConnection -Server $Server -Reason 'a backup is restored on exactly one'
      $nodeName = Resolve-PVENodeName -Connection $connection -Node $Node
      $type = $GuestType
      $entry = $null
      if (-not $type) {
        $backupStorage = $Volume.Substring(0, $Volume.IndexOf(':'))
        $entry = Get-PVEStorageItem -Connection $connection -Node $nodeName -Storage $backupStorage -Content backup | Where-Object { $_.Volume -eq $Volume }
      }
    }
    catch {
      $PSCmdlet.WriteError($_)
      return
    }
    if (-not $type) {
      if (-not $entry) {
        $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
            [System.Management.Automation.ItemNotFoundException]::new("Backup '$Volume' was not found on $backupStorage on $nodeName."),
            'PVEObjectNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $Volume))
        return
      }
      $type = $entry.GuestType
      if (-not $type) {
        $PSCmdlet.WriteError((New-PVEArgumentError -Message "Cannot tell whether '$Volume' is a VM or a container backup; give -GuestType." -Target $Volume))
        return
      }
    }

    $kind = if ($type -eq 'lxc') { 'container' } else { 'VM' }
    $action = '{0}Restore {1} {2} from {3}' -f $(if ($Force) { 'Replace and ' } else { '' }), $kind, $VMId, $Volume
    if (-not $PSCmdlet.ShouldProcess("$kind $VMId on $nodeName", $action)) {
      return
    }

    $body = @{ vmid = $VMId }
    if ($type -eq 'lxc') {
      $body.ostemplate = $Volume
      $body.restore = 1
    }
    else {
      $body.archive = $Volume
    }
    if ($Storage) { $body.storage = $Storage }
    if ($Pool) { $body.pool = $Pool }
    if ($Force) { $body.force = 1 }
    if ($Unique) { $body.unique = 1 }
    if ($PowerOn) { $body.start = 1 }

    $path = Format-PVEPath '/nodes/{node}/{type}' @{ node = $nodeName; type = $type }
    try {
      $upid = [string](Invoke-PVERequest -Connection $connection -Method POST -Path $path -Parameters $body)
    }
    catch {
      $PSCmdlet.WriteError($_)
      return
    }
    $operations = [System.Collections.Generic.List[psobject]]::new()
    $operations.Add([pscustomobject]@{ Upid = $upid; Connection = $connection; Guest = $null; Type = $type; Node = $nodeName; VMId = $VMId; Pool = $Pool })
    Complete-PVEOperation -Cmdlet $PSCmdlet -Operation $operations -RunAsync:$RunAsync
  }
}
