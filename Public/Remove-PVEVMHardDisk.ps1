function Remove-PVEVMHardDisk {
  <#
  .SYNOPSIS
  Detaches hard disks from QEMU virtual machines, or deletes them.
  .DESCRIPTION
  By default the disk is detached with POST /nodes/{node}/qemu/{vmid}/config (delete=<disk>): PVE removes
  it from the VM and keeps the volume as an unusedN entry, so its data survives and New-PVEVMHardDisk
  -Volume can attach it again. -DeletePermanently also sends force=1, which the API documents as forcing
  physical removal of the volume. That cannot be undone.

  Prompts for confirmation by default (ConfirmImpact High). On a running VM, PVE hot-unplugs the disk if
  it can; otherwise the removal is pending until the next start, and a warning says so. Writes nothing.
  .PARAMETER VMId
  VM ID. Binds from piped PVEPS.HardDisk objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER Device
  Disk(s) to remove, for example scsi1. Binds from piped PVEPS.HardDisk objects.
  .PARAMETER DeletePermanently
  Delete the volume instead of keeping it as an unused disk.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Remove-PVEVMHardDisk -VMId 100 -Device scsi1
  .EXAMPLE
  Get-PVEVMHardDisk -VMId 100 -Device scsi2 | Remove-PVEVMHardDisk -DeletePermanently -Confirm:$false
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestChange.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'High')]
  [OutputType([void])]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Device,

    [switch]$DeletePermanently,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName -Device $Device
  }

  end {
    foreach ($selection in @(Resolve-PVEDeviceTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets -Kind HardDisk -Noun 'hard disk')) {
      foreach ($disk in $selection.Devices) {
        Remove-PVEGuestDevice -Cmdlet $PSCmdlet -Guest $selection.Guest -Device $disk.Device -Kind HardDisk -Force:$DeletePermanently -Description $(
          if ($DeletePermanently) { "Delete hard disk $($disk.Device) and its volume $($disk.Volume)" } else { "Detach hard disk $($disk.Device) (kept as an unused disk)" })
      }
    }
  }
}
