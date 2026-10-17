function Invoke-PVEBackup {
  <#
  .SYNOPSIS
  Shared engine for Backup-PVEVM and Backup-PVEContainer.
  .DESCRIPTION
  Asks ShouldProcess on the calling cmdlet for each guest, then starts one backup task per node with
  POST /nodes/{node}/vzdump, vmid being the approved guests' IDs as a comma-separated list (the schema's
  pve-vmid-list format). Waits for the tasks, then writes the backups each one created as
  PVEPS.StorageContent objects.

  The new backups are found by listing the backup content of the target storage (or, without -Storage,
  of every active storage on the node that holds backups) before and after: whatever is new for the
  guest's ID is its backup. This needs no comparison of clocks between this computer and the node.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Calls ShouldProcess on the calling public cmdlet, passed as -Cmdlet, so its -WhatIf and -Confirm apply.')]
  [CmdletBinding()]
  [OutputType([psobject], [object[]])]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCmdlet]$Cmdlet,

    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [psobject[]]$Guest,

    [Parameter(Mandatory)]
    [hashtable]$Body,

    [string]$Storage,

    [Parameter(Mandatory)]
    [string]$Description,

    [switch]$RunAsync
  )

  $operations = [System.Collections.Generic.List[psobject]]::new()
  foreach ($group in ($Guest | Group-Object -Property { '{0}/{1}' -f $_.Connection.Id, $_.Node })) {
    $connection = $group.Group[0].Connection
    $node = $group.Group[0].Node
    $approved = @($group.Group | Where-Object { $Cmdlet.ShouldProcess((Get-PVEGuestLabel -Guest $_), $Description) })
    if ($approved.Count -eq 0) {
      continue
    }

    try {
      $storages = if ($Storage) {
        @($Storage)
      }
      else {
        @(Get-PVEStorage -Node $node -Content backup -Server $connection -ErrorAction Stop | Where-Object Active | ForEach-Object { $_.Name })
      }
      $before = [System.Collections.Generic.HashSet[string]]::new()
      foreach ($name in $storages) {
        foreach ($item in @(Get-PVEStorageItem -Connection $connection -Node $node -Storage $name -Content backup)) {
          $null = $before.Add($item.Volume)
        }
      }
    }
    catch {
      $Cmdlet.WriteError($_)
      continue
    }

    $parameters = $Body.Clone()
    $parameters.vmid = @($approved | ForEach-Object { $_.VMId }) -join ','
    $path = Format-PVEPath '/nodes/{node}/vzdump' @{ node = $node }
    try {
      $upid = [string](Invoke-PVERequest -Connection $connection -Method POST -Path $path -Parameters $parameters)
    }
    catch {
      $Cmdlet.WriteError($_)
      continue
    }
    Write-Verbose "Backup of $($parameters.vmid) on $node`: task $upid"
    $operations.Add([pscustomobject]@{ Upid = $upid; Connection = $connection; Node = $node; Guests = $approved; Storages = $storages; Before = $before })
  }
  if ($operations.Count -eq 0) {
    return
  }

  if ($RunAsync) {
    foreach ($op in $operations) {
      if ($op.Upid -match '^UPID:') {
        try {
          Get-PVETask -Upid $op.Upid -Server $op.Connection -ErrorAction Stop
        }
        catch {
          $Cmdlet.WriteError($_)
        }
      }
    }
    return
  }

  foreach ($op in @(Wait-PVEOperation -Operation $operations)) {
    try {
      $new = @(
        foreach ($name in $op.Storages) {
          Get-PVEStorageItem -Connection $op.Connection -Node $op.Node -Storage $name -Content backup |
            Where-Object { -not $op.Before.Contains($_.Volume) }
        }
      )
    }
    catch {
      $Cmdlet.WriteError($_)
      continue
    }
    foreach ($member in $op.Guests) {
      $mine = @($new | Where-Object { $_.VMId -eq $member.VMId })
      if ($mine.Count -eq 0) {
        Write-Warning "$(Get-PVEGuestLabel -Guest $member): the backup task succeeded, but no new backup was found on $($op.Storages -join ', ')."
      }
      $mine
    }
  }
}
