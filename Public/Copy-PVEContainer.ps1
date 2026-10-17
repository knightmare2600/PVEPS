function Copy-PVEContainer {
  <#
  .SYNOPSIS
  Clones a container or container template into a new container.
  .DESCRIPTION
  Clones the source with POST /nodes/{node}/lxc/{vmid}/clone, waits for the clone task, and writes the
  new container with its live status. The new container is created on the source's node.

  From the API documentation: a clone of a normal container is always a full clone (a full copy of every
  disk); for a template, PVE tries to make a linked clone by default, whose disks share the template's
  base image. -Full asks for a full clone of a template. -Storage applies to full clones.

  The source can be named by ID or name (templates included), or piped in. Exactly one source is
  cloned per call.
  .PARAMETER Name
  Name of the source container or template.
  .PARAMETER VMId
  ID of the source container or template. Binds from a piped PVEPS.Container object.
  .PARAMETER NewName
  Host name for the new container.
  .PARAMETER NewVMId
  ID for the new container. Defaults to the next free ID.
  .PARAMETER Full
  Make a full clone of a template instead of a linked clone.
  .PARAMETER Storage
  Target storage for a full clone.
  .PARAMETER Pool
  Resource pool to add the new container to.
  .PARAMETER Description
  Description for the new container.
  .PARAMETER Snapshot
  Clone the source as it was at this snapshot.
  .PARAMETER RunAsync
  Return the clone task at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from a piped object.
  .EXAMPLE
  Copy-PVEContainer tmpl-debian13 -NewName dns02
  .EXAMPLE
  Copy-PVEContainer -VMId 9100 -NewName dns03 -Full -Storage local-lvm | Start-PVEContainer
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestClone.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.Container', 'PVEPS.Task')]
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
    if ($Pool) {
      $parameters.pool = $Pool
    }
    if ($PSBoundParameters.ContainsKey('Description')) {
      $parameters.description = $Description
    }
    if ($Snapshot) {
      $parameters.snapname = $Snapshot
    }
    Invoke-PVEGuestClone -Cmdlet $PSCmdlet -Type lxc -Target $targets -NewName $NewName -NewVMId $NewVMId -Parameters $parameters -RunAsync:$RunAsync
  }
}
