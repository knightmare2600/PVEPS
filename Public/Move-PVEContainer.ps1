function Move-PVEContainer {
  <#
  .SYNOPSIS
  Moves the storage of containers to another storage.
  .DESCRIPTION
  Moves each container's volumes (the root file system and mount points backed by a storage volume; bind
  mounts and device mounts are left alone) to -Storage, one at a time with POST
  /nodes/{node}/lxc/{vmid}/move_volume, waiting for each to finish. Writes each container with its live
  status when its moves are done.

  By default PVE keeps each source volume after the copy, as an unusedN entry in the configuration;
  -DeleteSource deletes it once the copy has succeeded. Whether PVE moves the volumes of a running
  container is unverified; if it refuses, the error says so.

  Moving guests between nodes needs a cluster and is not covered by this cmdlet yet.

  Prompts for confirmation at ConfirmImpact Medium, so not by default.
  .PARAMETER Name
  Container name(s). Wildcards allowed.
  .PARAMETER VMId
  Container ID(s). Binds from piped PVEPS.Container objects.
  .PARAMETER IncludeTemplate
  Let -Name match templates as well as containers.
  .PARAMETER Storage
  Target storage.
  .PARAMETER Volume
  Volumes to move: rootfs and/or mp0, mp1, ... Defaults to every volume not already on -Storage.
  .PARAMETER DeleteSource
  Delete each source volume after it has been copied.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Move-PVEContainer -VMId 200 -Storage local-zfs
  .EXAMPLE
  Move-PVEContainer dns01 -Storage fast-ssd -Volume mp0 -DeleteSource
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEVolumeMove.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.Container')]
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
    [string[]]$Volume,

    [switch]$DeleteSource,

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
    $guests = @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type lxc -Target $targets -IncludeTemplate:$IncludeTemplate)
    Invoke-PVEVolumeMove -Cmdlet $PSCmdlet -Guest $guests -Storage $Storage -Key $Volume -DeleteSource:$DeleteSource
  }
}
