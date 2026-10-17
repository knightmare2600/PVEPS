function Remove-PVEStorageContent {
  <#
  .SYNOPSIS
  Deletes volumes from storage: ISO images, templates, backups, or unused disk images.
  .DESCRIPTION
  Deletes each volume with DELETE /nodes/{node}/storage/{storage}/content/{volume} and waits for the task.
  This cannot be undone. Prompts for confirmation by default (ConfirmImpact High). PVE refuses to delete a
  protected backup, and a disk image that a guest still uses. Writes nothing.
  .PARAMETER Volume
  Volume ID(s), for example local:iso/old.iso. Binds from piped PVEPS.StorageContent objects.
  .PARAMETER Node
  Node the storage is on. Binds from piped objects; can be omitted on a single-node server.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Remove-PVEStorageContent -Volume local:iso/debian-12.5.0-amd64-netinst.iso
  .EXAMPLE
  Get-PVEStorageContent -Content backup -VMId 100 | Select-Object -Skip 3 | Remove-PVEStorageContent -Confirm:$false
  #>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  [OutputType([void])]
  param(
    [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Volume,

    [Parameter(ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string]$Node,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $operations = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    foreach ($item in @(Resolve-PVEVolumeTarget -Cmdlet $PSCmdlet -Volume $Volume -Node $Node -Server $Server)) {
      if (-not $PSCmdlet.ShouldProcess("$($item.Volume) on $($item.Node)", 'Delete volume')) {
        continue
      }
      $path = Format-PVEPath '/nodes/{node}/storage/{storage}/content/{volume}' @{ node = $item.Node; storage = $item.Storage; volume = $item.Volume }
      try {
        $upid = [string](Invoke-PVERequest -Connection $item.Connection -Method DELETE -Path $path)
      }
      catch {
        $PSCmdlet.WriteError($_)
        continue
      }
      $operations.Add([pscustomobject]@{ Upid = $upid; Connection = $item.Connection })
    }
  }

  end {
    $null = Wait-PVEOperation -Operation $operations
  }
}
