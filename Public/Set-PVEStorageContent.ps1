function Set-PVEStorageContent {
  <#
  .SYNOPSIS
  Changes the notes or protection of stored volumes.
  .DESCRIPTION
  Sends the change with PUT /nodes/{node}/storage/{storage}/content/{volume} and writes the volume as it
  now is. The API documentation says protection is currently only supported for backups; a protected
  backup cannot be deleted until it is unprotected.
  .PARAMETER Volume
  Volume ID(s). Binds from piped PVEPS.StorageContent objects.
  .PARAMETER Node
  Node the storage is on. Binds from piped objects; can be omitted on a single-node server.
  .PARAMETER Notes
  New notes.
  .PARAMETER Protected
  Whether the backup is protected.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Get-PVEStorageContent -Content backup -VMId 100 | Select-Object -First 1 | Set-PVEStorageContent -Protected $true -Notes 'Before the migration'
  #>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.StorageContent')]
  param(
    [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Volume,

    [Parameter(ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string]$Node,

    [AllowEmptyString()]
    [string]$Notes,

    [bool]$Protected,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $body = @{}
    if ($PSBoundParameters.ContainsKey('Notes')) { $body.notes = $Notes }
    if ($PSBoundParameters.ContainsKey('Protected')) { $body.protected = $Protected }
    if ($body.Count -eq 0) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message 'No change given; specify -Notes or -Protected.' -Target $null))
    }
  }

  process {
    foreach ($item in @(Resolve-PVEVolumeTarget -Cmdlet $PSCmdlet -Volume $Volume -Node $Node -Server $Server)) {
      if (-not $PSCmdlet.ShouldProcess("$($item.Volume) on $($item.Node)", "Set $(@($body.Keys | Sort-Object) -join ', ')")) {
        continue
      }
      $path = Format-PVEPath '/nodes/{node}/storage/{storage}/content/{volume}' @{ node = $item.Node; storage = $item.Storage; volume = $item.Volume }
      try {
        $null = Invoke-PVERequest -Connection $item.Connection -Method PUT -Path $path -Parameters $body
        Get-PVEStorageItem -Connection $item.Connection -Node $item.Node -Storage $item.Storage | Where-Object { $_.Volume -eq $item.Volume }
      }
      catch {
        $PSCmdlet.WriteError($_)
      }
    }
  }
}
