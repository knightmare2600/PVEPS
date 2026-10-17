function New-PVEVMHardDisk {
  <#
  .SYNOPSIS
  Adds a hard disk to QEMU virtual machines.
  .DESCRIPTION
  Adds a new disk of -SizeGB GiB on -Storage, or attaches an existing volume given as -Volume (for
  example one listed as unusedN after Remove-PVEVMHardDisk), with POST /nodes/{node}/qemu/{vmid}/config.
  Writes the new PVEPS.HardDisk object.

  The disk goes on the -Bus bus at the lowest free index unless -Index is given. On a running VM, PVE
  hot-plugs the disk if the VM's hotplug settings allow it; otherwise the disk is pending until the VM is
  next started, and a warning says so.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER SizeGB
  Size of the new disk in GiB. Needs -Storage.
  .PARAMETER Storage
  Storage for the new disk.
  .PARAMETER Volume
  An existing volume to attach instead of creating a disk, for example local-lvm:vm-100-disk-3.
  .PARAMETER Bus
  scsi (the default), virtio, sata or ide.
  .PARAMETER Index
  Index on the bus, for example 2 for scsi2. Defaults to the lowest free index.
  .PARAMETER Format
  Disk format on file-based storage: raw, qcow2 or vmdk.
  .PARAMETER Cache
  Cache mode: none, writethrough, writeback, unsafe or directsync.
  .PARAMETER SSD
  Present the disk to the guest as an SSD.
  .PARAMETER Discard
  Pass discard/TRIM requests from the guest to the storage.
  .PARAMETER IOThread
  Give the disk its own I/O thread.
  .PARAMETER NoBackup
  Leave the disk out of backups (backup=0).
  .PARAMETER Parameter
  Further drive options by their API names, for example @{ iops_rd = 500 }.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  New-PVEVMHardDisk -VMId 100 -SizeGB 50 -Storage local-lvm -SSD -Discard
  .EXAMPLE
  Get-PVEVM db01 | New-PVEVMHardDisk -SizeGB 200 -Storage bulk -Bus virtio -IOThread
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestChange.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.HardDisk')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [ValidateRange(1, [int]::MaxValue)]
    [int]$SizeGB,

    [ValidateNotNullOrEmpty()]
    [string]$Storage,

    [ValidateNotNullOrEmpty()]
    [string]$Volume,

    [ValidateSet('scsi', 'virtio', 'sata', 'ide')]
    [string]$Bus = 'scsi',

    [ValidateRange(0, 30)]
    [int]$Index,

    [ValidateSet('raw', 'qcow2', 'vmdk')]
    [string]$Format,

    [ValidateSet('none', 'writethrough', 'writeback', 'unsafe', 'directsync')]
    [string]$Cache,

    [switch]$SSD,

    [switch]$Discard,

    [switch]$IOThread,

    [switch]$NoBackup,

    [hashtable]$Parameter,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    if ($Volume -and ($SizeGB -or $Storage)) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message 'Give either -Volume, or -SizeGB with -Storage, not both.' -Target $Volume))
    }
    if (-not $Volume -and -not ($SizeGB -and $Storage)) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message 'Give -SizeGB with -Storage for a new disk, or -Volume to attach an existing one.' -Target $null))
    }
    $slots = @{ scsi = 31; virtio = 16; sata = 6; ide = 4 }
    if ($PSBoundParameters.ContainsKey('Index') -and $Index -ge $slots[$Bus]) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message "The $Bus bus has indexes 0 to $($slots[$Bus] - 1)." -Target $Index))
    }
    $option = [ordered]@{ file = if ($Volume) { $Volume } else { '{0}:{1}' -f $Storage, $SizeGB } }
    if ($Format) { $option.format = $Format }
    if ($Cache) { $option.cache = $Cache }
    if ($SSD) { $option.ssd = 1 }
    if ($Discard) { $option.discard = 'on' }
    if ($IOThread) { $option.iothread = 1 }
    if ($NoBackup) { $option.backup = 0 }
    if ($Parameter) {
      foreach ($key in $Parameter.Keys) {
        $option[$key] = $Parameter[$key]
      }
    }
    $value = ConvertTo-PVEPropertyString -Option $option -DefaultKey file
    $what = if ($Volume) { "volume $Volume" } else { "$SizeGB GiB on $Storage" }
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName
  }

  end {
    foreach ($guest in @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets)) {
      $slot = if ($PSBoundParameters.ContainsKey('Index')) { $Index } else { -1 }
      Add-PVEGuestDevice -Cmdlet $PSCmdlet -Guest $guest -Prefix $Bus -Index $slot -Count $slots[$Bus] -Value $value -Kind HardDisk -Description "Add hard disk {key} ($what)"
    }
  }
}
