function Move-PVEVM {
  <#
  .SYNOPSIS
  Moves the storage of VMs to another storage.
  .DESCRIPTION
  Moves each VM's disks (ide, sata, scsi and virtio disks, the EFI vars disk and the TPM state disk; CD
  drives are left alone) to -Storage, one at a time with POST /nodes/{node}/qemu/{vmid}/move_disk,
  waiting for each to finish. Writes each VM with its live status when its moves are done.

  By default PVE keeps each source volume after the copy, as an unusedN entry in the configuration;
  -DeleteSource deletes it once the copy has succeeded. PVE can move the disks of a running VM.

  Moving guests between nodes needs a cluster and is not covered by this cmdlet yet.

  Prompts for confirmation at ConfirmImpact Medium, so not by default.
  .PARAMETER Name
  VM name(s). Wildcards allowed.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER IncludeTemplate
  Let -Name match templates as well as VMs.
  .PARAMETER Storage
  Target storage.
  .PARAMETER Disk
  Disks to move, for example scsi0, virtio1, efidisk0. Defaults to every disk not already on -Storage.
  .PARAMETER DeleteSource
  Delete each source volume after it has been copied.
  .PARAMETER Format
  Disk format on the target storage: raw, qcow2 or vmdk. If the target storage does not support it, PVE
  uses the storage's default format.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Move-PVEVM -VMId 100 -Storage local-zfs
  .EXAMPLE
  Get-PVEVM -Name 'db*' | Move-PVEVM -Storage fast-ssd -Disk scsi1 -DeleteSource
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEVolumeMove.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.VM')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Name,

    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(ParameterSetName = 'Name')]
    [switch]$IncludeTemplate,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Storage,

    [ValidateNotNullOrEmpty()]
    [string[]]$Disk,

    [switch]$DeleteSource,

    [ValidateSet('raw', 'qcow2', 'vmdk')]
    [string]$Format,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $Name
  }

  end {
    $guests = @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets -IncludeTemplate:$IncludeTemplate)
    Invoke-PVEVolumeMove -Cmdlet $PSCmdlet -Guest $guests -Storage $Storage -Key $Disk -DeleteSource:$DeleteSource -Format $Format
  }
}
