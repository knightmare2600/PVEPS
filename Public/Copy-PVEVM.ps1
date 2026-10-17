function Copy-PVEVM {
  <#
  .SYNOPSIS
  Clones a VM or VM template into a new VM.
  .DESCRIPTION
  Clones the source with POST /nodes/{node}/qemu/{vmid}/clone, waits for the clone task, and writes the
  new VM with its live status. The new VM is created on the source's node.

  From the API documentation: a clone of a normal VM is always a full clone (a full copy of every
  disk); for a template, PVE tries to make a linked clone by default, whose disks share the template's
  base image. -Full asks for a full clone of a template. -Storage and -Format apply to full clones.

  The source can be named by ID or name (templates included), or piped in. Exactly one source is
  cloned per call.
  .PARAMETER Name
  Name of the source VM or template.
  .PARAMETER VMId
  ID of the source VM or template. Binds from a piped PVEPS.VM object.
  .PARAMETER NewName
  Name for the new VM.
  .PARAMETER NewVMId
  ID for the new VM. Defaults to the next free ID.
  .PARAMETER Full
  Make a full clone of a template instead of a linked clone.
  .PARAMETER Storage
  Target storage for a full clone.
  .PARAMETER Format
  Disk format for a full clone: raw, qcow2 or vmdk. If the target storage does not support it, PVE uses
  the storage's default format.
  .PARAMETER Pool
  Resource pool to add the new VM to.
  .PARAMETER Description
  Description for the new VM.
  .PARAMETER Snapshot
  Clone the source as it was at this snapshot.
  .PARAMETER RunAsync
  Return the clone task at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from a piped object.
  .EXAMPLE
  Copy-PVEVM tmpl-debian13 -NewName web03
  .EXAMPLE
  Copy-PVEVM -VMId 9000 -NewName web04 -NewVMId 104 -Full -Storage local-lvm -Pool web | Start-PVEVM
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestClone.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.VM', 'PVEPS.Task')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int]$VMId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$NewName,

    [ValidateRange(100, 999999999)]
    [int]$NewVMId,

    [switch]$Full,

    [ValidateNotNullOrEmpty()]
    [string]$Storage,

    [ValidateSet('raw', 'qcow2', 'vmdk')]
    [string]$Format,

    [ValidateNotNullOrEmpty()]
    [string]$Pool,

    [string]$Description,

    [ValidateNotNullOrEmpty()]
    [string]$Snapshot,

    [switch]$RunAsync,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    # -VMId and -Name are scalars here, so the one not in use holds 0 or '' rather than $null.
    if ($PSCmdlet.ParameterSetName -eq 'Id') {
      Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId
    }
    else {
      Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -Name $Name
    }
  }

  end {
    $parameters = @{}
    if ($Full) {
      $parameters.full = 1
    }
    if ($Storage) {
      $parameters.storage = $Storage
    }
    if ($Format) {
      $parameters.format = $Format
    }
    if ($Pool) {
      $parameters.pool = $Pool
    }
    if ($PSBoundParameters.ContainsKey('Description')) {
      $parameters.description = $Description
    }
    if ($Snapshot) {
      $parameters.snapname = $Snapshot
    }
    Invoke-PVEGuestClone -Cmdlet $PSCmdlet -Type qemu -Target $targets -NewName $NewName -NewVMId $NewVMId -Parameters $parameters -RunAsync:$RunAsync
  }
}
