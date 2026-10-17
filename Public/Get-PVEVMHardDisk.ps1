function Get-PVEVMHardDisk {
  <#
  .SYNOPSIS
  Gets the hard disks of QEMU virtual machines.
  .DESCRIPTION
  Reads each VM's configuration and writes one PVEPS.HardDisk object per ide, sata, scsi or virtio disk
  (CD drives are listed by Get-PVEVMCDDrive). The configuration PVE returns has pending changes applied.

  Device is the configuration key (for example scsi0); Options holds every option of the entry as PVE
  wrote it.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed. Templates are included.
  .PARAMETER Device
  Disk(s) to return, for example scsi0 or 'virtio*'. All disks if omitted.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Get-PVEVM web01 | Get-PVEVMHardDisk
  .EXAMPLE
  Get-PVEVMHardDisk -VMName '*' | Where-Object Storage -EQ 'local-lvm' | Measure-Object -Property SizeGB -Sum
  #>
  [CmdletBinding(DefaultParameterSetName = 'Id')]
  [OutputType('PVEPS.HardDisk')]
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
    [string[]]$Device,

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
    foreach ($selection in @(Resolve-PVEDeviceTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets -Kind HardDisk -Noun 'hard disk' -IncludeTemplate)) {
      $selection.Devices
    }
  }
}
