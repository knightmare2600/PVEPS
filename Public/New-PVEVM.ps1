function New-PVEVM {
  <#
  .SYNOPSIS
  Creates a QEMU virtual machine.
  .DESCRIPTION
  Creates the VM with POST /nodes/{node}/qemu, waits for the create task, and writes the new VM with its
  live status. Options not given are left to PVE's own defaults (for example 512 MiB of memory, one core,
  no disk, no network device).

  What the parameters add to the configuration:
  - -DiskGB: one new disk per value on -Storage, on the -DiskBus bus (scsi0, scsi1, ...). With the scsi
    bus the controller is set to virtio-scsi-single (PVE's own default is lsi).
  - -NetworkBridge: one network device per bridge (net0, net1, ...), of model -NetworkModel.
  - -IsoImage: a CD drive (ide2) with that ISO.
  - -Bios ovmf: also an EFI vars disk (efidisk0, efitype 4m) on -Storage.
  - A boot order of the first disk, then the CD drive, then the first network device, for the ones that
    exist.
  - -Parameter: any other create options, by their API names. Applied last, so they override the above.
  .PARAMETER Name
  VM name. PVE requires a valid DNS name.
  .PARAMETER VMId
  ID for the VM. Defaults to the next free ID. PVE checks a given ID is free before the VM is created.
  .PARAMETER Node
  Node to create the VM on. Can be omitted when the server has a single node.
  .PARAMETER Cores
  Cores per socket.
  .PARAMETER Sockets
  CPU sockets.
  .PARAMETER MemoryGB
  Memory in GiB, sent to PVE in whole MiB (for example 1.5 is 1536 MiB).
  .PARAMETER DiskGB
  Size in GiB of each new disk to create on -Storage. One disk per value.
  .PARAMETER DiskBus
  Bus for the new disks: scsi (the default), virtio, sata or ide.
  .PARAMETER Storage
  Storage for the new disks and the EFI vars disk. Required with -DiskGB and with -Bios ovmf.
  .PARAMETER NetworkBridge
  Bridge for each network device, for example vmbr0. One device per value.
  .PARAMETER NetworkModel
  Network device model. Defaults to virtio.
  .PARAMETER IsoImage
  ISO volume to insert in a CD drive, for example local:iso/debian-13.1.0-amd64-netinst.iso.
  .PARAMETER OSType
  Guest OS type, which PVE uses to enable OS-specific optimisations. From the PVE API documentation: l26
  is a Linux 2.6 - 7.x kernel; win10 is Windows 10/2016/2019; win11 is Windows 11/2022/2025; other is
  unspecified.
  .PARAMETER Bios
  seabios (PVE's default) or ovmf (UEFI).
  .PARAMETER Machine
  QEMU machine type, for example q35 or pc (i440fx).
  .PARAMETER CpuType
  Emulated CPU type, for example host or x86-64-v2-AES.
  .PARAMETER GuestAgent
  Enable the QEMU guest agent device. The agent itself has to be installed in the guest.
  .PARAMETER Pool
  Resource pool to add the VM to.
  .PARAMETER Tags
  Tags for the VM.
  .PARAMETER Description
  Description (notes) shown in the VM's summary.
  .PARAMETER StartOnBoot
  Start the VM when the node boots.
  .PARAMETER PowerOn
  Start the VM once it has been created.
  .PARAMETER Parameter
  Further create options by their API names, for example @{ balloon = 0; vga = 'serial0' }.
  .PARAMETER RunAsync
  Return the create task at once instead of waiting.
  .PARAMETER Server
  Connection to use. Defaults to the default connection.
  .EXAMPLE
  New-PVEVM -Name web01 -Cores 2 -MemoryGB 4 -DiskGB 32 -Storage local-lvm -NetworkBridge vmbr0 -OSType l26
  .EXAMPLE
  New-PVEVM web02 -DiskGB 32, 100 -Storage local-lvm -IsoImage local:iso/debian-13.1.0-amd64-netinst.iso -PowerOn
  .EXAMPLE
  New-PVEVM win01 -OSType win11 -Bios ovmf -Machine q35 -MemoryGB 8 -DiskGB 80 -Storage local-lvm -Parameter @{ tpmstate0 = 'local-lvm:1,version=v2.0' }
  #>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.VM', 'PVEPS.Task')]
  param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [ValidateRange(100, 999999999)]
    [int]$VMId,

    [ValidateNotNullOrEmpty()]
    [string]$Node,

    [ValidateRange(1, [int]::MaxValue)]
    [int]$Cores,

    [ValidateRange(1, [int]::MaxValue)]
    [int]$Sockets,

    [ValidateRange(0.015625, [double]::MaxValue)]
    [double]$MemoryGB,

    [ValidateRange(1, [int]::MaxValue)]
    [int[]]$DiskGB,

    [ValidateSet('scsi', 'virtio', 'sata', 'ide')]
    [string]$DiskBus = 'scsi',

    [ValidateNotNullOrEmpty()]
    [string]$Storage,

    [ValidateNotNullOrEmpty()]
    [string[]]$NetworkBridge,

    [ValidateSet('e1000', 'e1000-82540em', 'e1000-82544gc', 'e1000-82545em', 'e1000e', 'i82551', 'i82557b', 'i82559er', 'ne2k_isa', 'ne2k_pci', 'pcnet', 'rtl8139', 'virtio', 'vmxnet3')]
    [string]$NetworkModel = 'virtio',

    [ValidateNotNullOrEmpty()]
    [string]$IsoImage,

    [ValidateSet('other', 'wxp', 'w2k', 'w2k3', 'w2k8', 'wvista', 'win7', 'win8', 'win10', 'win11', 'l24', 'l26', 'solaris')]
    [string]$OSType,

    [ValidateSet('seabios', 'ovmf')]
    [string]$Bios,

    [ValidateNotNullOrEmpty()]
    [string]$Machine,

    [ValidateNotNullOrEmpty()]
    [string]$CpuType,

    [switch]$GuestAgent,

    [ValidateNotNullOrEmpty()]
    [string]$Pool,

    [ValidateNotNullOrEmpty()]
    [string[]]$Tags,

    [string]$Description,

    [switch]$StartOnBoot,

    [switch]$PowerOn,

    [hashtable]$Parameter,

    [switch]$RunAsync,

    [Alias('Connection')]
    [object]$Server
  )

  # Unbound array parameters are $null, and .Count on $null throws under strict mode.
  $diskSizes = @(if ($DiskGB) { $DiskGB })
  $bridges = @(if ($NetworkBridge) { $NetworkBridge })

  if ($DiskGB -and -not $Storage) {
    $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message '-DiskGB needs -Storage, the storage to create the disks on.' -Target $DiskGB))
  }
  if ($Bios -eq 'ovmf' -and -not $Storage) {
    $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message '-Bios ovmf needs -Storage, for the EFI vars disk.' -Target $Bios))
  }
  $slots = @{ scsi = 31; virtio = 16; sata = 6; ide = 4 }
  $diskSlots = @(0..($slots[$DiskBus] - 1) | Where-Object { -not ($DiskBus -eq 'ide' -and $IsoImage -and $_ -eq 2) })
  if ($diskSizes.Count -gt $diskSlots.Count) {
    $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message "The $DiskBus bus has room for $($diskSlots.Count) disks here; -DiskGB has $($diskSizes.Count)." -Target $DiskGB))
  }
  foreach ($key in 'vmid', 'node') {
    if ($Parameter -and $Parameter.ContainsKey($key)) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message "-Parameter cannot set '$key'; use -VMId or -Node." -Target $Parameter))
    }
  }

  try {
    $connection = Resolve-PVESingleConnection -Server $Server -Reason 'a VM is created on exactly one'
    $nodeName = Resolve-PVENodeName -Connection $connection -Node $Node
    $id = Get-PVENewVMId -Connection $connection -VMId $VMId
  }
  catch {
    $PSCmdlet.WriteError($_)
    return
  }

  $body = @{ vmid = $id; name = $Name }
  if ($PSBoundParameters.ContainsKey('Cores')) { $body.cores = $Cores }
  if ($PSBoundParameters.ContainsKey('Sockets')) { $body.sockets = $Sockets }
  if ($PSBoundParameters.ContainsKey('MemoryGB')) { $body.memory = ConvertTo-PVEMiB $MemoryGB }
  if ($OSType) { $body.ostype = $OSType }
  if ($Bios) { $body.bios = $Bios }
  if ($Machine) { $body.machine = $Machine }
  if ($CpuType) { $body.cpu = $CpuType }
  if ($GuestAgent) { $body.agent = 1 }
  if ($Pool) { $body.pool = $Pool }
  if ($Tags) { $body.tags = $Tags -join ';' }
  if ($PSBoundParameters.ContainsKey('Description')) { $body.description = $Description }
  if ($StartOnBoot) { $body.onboot = 1 }
  if ($PowerOn) { $body.start = 1 }

  $boot = [System.Collections.Generic.List[string]]::new()
  for ($i = 0; $i -lt $diskSizes.Count; $i++) {
    $key = '{0}{1}' -f $DiskBus, $diskSlots[$i]
    $body[$key] = '{0}:{1}' -f $Storage, $diskSizes[$i]
    if ($i -eq 0) {
      $boot.Add($key)
    }
  }
  if ($DiskGB -and $DiskBus -eq 'scsi') {
    $body.scsihw = 'virtio-scsi-single'
  }
  if ($IsoImage) {
    $body.ide2 = '{0},media=cdrom' -f $IsoImage
    $boot.Add('ide2')
  }
  for ($i = 0; $i -lt $bridges.Count; $i++) {
    $body["net$i"] = '{0},bridge={1}' -f $NetworkModel, $bridges[$i]
    if ($i -eq 0) {
      $boot.Add('net0')
    }
  }
  if ($Bios -eq 'ovmf') {
    $body.efidisk0 = '{0}:1,efitype=4m' -f $Storage
  }
  if ($boot.Count -gt 0) {
    $body.boot = 'order={0}' -f ($boot -join ';')
  }
  if ($Parameter) {
    foreach ($key in $Parameter.Keys) {
      $body[$key] = $Parameter[$key]
    }
  }

  $label = 'VM {0} ({1}) on {2}' -f $id, $Name, $nodeName
  if (-not $PSCmdlet.ShouldProcess($label, 'Create')) {
    return
  }

  $operations = [System.Collections.Generic.List[psobject]]::new()
  try {
    $path = Format-PVEPath '/nodes/{node}/qemu' @{ node = $nodeName }
    $upid = Invoke-PVERequest -Connection $connection -Method POST -Path $path -Parameters $body
  }
  catch {
    $PSCmdlet.WriteError($_)
    return
  }
  Write-Verbose "Create $label`: task $upid"
  $operations.Add([pscustomobject]@{ Upid = [string]$upid; Connection = $connection; Guest = $null; Type = 'qemu'; Node = $nodeName; VMId = $id; Pool = $Pool })
  Complete-PVEOperation -Cmdlet $PSCmdlet -Operation $operations -RunAsync:$RunAsync
}
