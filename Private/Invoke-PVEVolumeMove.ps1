function Invoke-PVEVolumeMove {
  <#
  .SYNOPSIS
  Shared engine for Move-PVEVM and Move-PVEContainer: moves guest volumes to another storage.
  .DESCRIPTION
  For each guest, lists its storage-backed volumes (Get-PVEGuestVolume), keeps those named in -Key (all
  if -Key is omitted) that are not already on -Storage, asks ShouldProcess on the calling cmdlet once
  for the guest, then moves the volumes one at a time, waiting for each task before starting the next.
  A failed move stops the remaining moves for that guest. Each guest is written with its live status
  once its moves are done (or if it had nothing to move).

  QEMU: POST /nodes/{node}/qemu/{vmid}/move_disk. LXC: POST /nodes/{node}/lxc/{vmid}/move_volume.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Calls ShouldProcess on the calling public cmdlet, passed as -Cmdlet, so its -WhatIf and -Confirm apply.')]
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCmdlet]$Cmdlet,

    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [psobject[]]$Guest,

    [Parameter(Mandatory)]
    [string]$Storage,

    [string[]]$Key,

    [switch]$DeleteSource,

    [string]$Format
  )

  foreach ($item in $Guest) {
    $label = Get-PVEGuestLabel -Guest $item
    try {
      $volumes = @(Get-PVEGuestVolume -Guest $item)
    }
    catch {
      $Cmdlet.WriteError($_)
      continue
    }

    if ($Key) {
      $missing = @($Key | Where-Object { $_ -notin @($volumes | ForEach-Object { $_.Key }) })
      foreach ($name in $missing) {
        $Cmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
            [System.Management.Automation.ItemNotFoundException]::new("$label has no storage volume '$name'. Volumes: $(@($volumes | ForEach-Object { $_.Key }) -join ', ')."),
            'PVEVolumeNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $name))
      }
      if ($missing.Count -gt 0) {
        continue
      }
      $volumes = @($volumes | Where-Object { $_.Key -in $Key })
    }

    $toMove = @($volumes | Where-Object { $_.Storage -ne $Storage })
    if ($toMove.Count -eq 0) {
      Write-Warning "$label has no volumes to move; they are already on $Storage."
      try {
        Update-PVEGuestStatus -Guest $item
      }
      catch {
        $Cmdlet.WriteError($_)
      }
      continue
    }

    $keys = @($toMove | ForEach-Object { $_.Key }) -join ', '
    $action = 'Move {0} to storage {1}{2}' -f $keys, $Storage, $(if ($DeleteSource) { ', deleting the source volumes' } else { '' })
    if (-not $Cmdlet.ShouldProcess($label, $action)) {
      continue
    }

    $failed = $false
    foreach ($volume in $toMove) {
      if ($item.Type -eq 'lxc') {
        $path = Format-PVEPath '/nodes/{node}/lxc/{vmid}/move_volume' @{ node = $item.Node; vmid = $item.VMId }
        $body = @{ volume = $volume.Key; storage = $Storage }
      }
      else {
        $path = Format-PVEPath '/nodes/{node}/qemu/{vmid}/move_disk' @{ node = $item.Node; vmid = $item.VMId }
        $body = @{ disk = $volume.Key; storage = $Storage }
        if ($Format) {
          $body.format = $Format
        }
      }
      if ($DeleteSource) {
        $body.delete = 1
      }
      try {
        $upid = [string](Invoke-PVERequest -Connection $item.Connection -Method POST -Path $path -Parameters $body)
      }
      catch {
        $Cmdlet.WriteError($_)
        $failed = $true
        break
      }
      Write-Verbose "Move $($volume.Key) of $label to $Storage`: task $upid"
      if ($upid -match '^UPID:') {
        $finished = @([pscustomobject]@{ Upid = $upid; Connection = $item.Connection } | Wait-PVETask)
        if ($finished.Count -eq 0) {
          $failed = $true
          break
        }
      }
    }
    if ($failed) {
      continue
    }

    try {
      Update-PVEGuestStatus -Guest $item
    }
    catch {
      $Cmdlet.WriteError($_)
    }
  }
}
