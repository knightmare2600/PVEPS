function Get-PVEBackup {
  <#
  .SYNOPSIS
  Lists backups, optionally of particular guests, newest first.
  .DESCRIPTION
  Lists the backup content of storages (Get-PVEStorageContent -Content backup). With -VMId, only those
  guests' backups; the IDs are not checked against existing guests, so backups of deleted guests are
  found too. -Latest keeps only the newest backup of each guest.
  .PARAMETER VMId
  Guest ID(s). Binds from piped PVEPS.VM or PVEPS.Container objects.
  .PARAMETER Storage
  Storage name(s). Wildcards allowed.
  .PARAMETER Node
  Node name(s). Wildcards allowed.
  .PARAMETER Latest
  Only the newest backup of each guest.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Get-PVEVM web01 | Get-PVEBackup
  .EXAMPLE
  Get-PVEBackup -Latest | Where-Object Created -LT (Get-Date).AddDays(-7)
  #>
  [CmdletBinding()]
  [OutputType('PVEPS.StorageContent')]
  param(
    [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
    [ValidateRange(1, 999999999)]
    [int[]]$VMId,

    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Storage,

    [Parameter(ValueFromPipelineByPropertyName)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Node,

    [switch]$Latest,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $all = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    $find = @{ Content = 'backup'; Server = $Server }
    if ($Storage) { $find.Storage = $Storage }
    if ($Node) { $find.Node = $Node }
    foreach ($item in @(Get-PVEStorageContent @find)) {
      if (-not $VMId -or $item.VMId -in $VMId) {
        $all.Add($item)
      }
    }
  }

  end {
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $sorted = $all | Sort-Object -Property @{ Expression = { if ($_.Created) { $_.Created } else { [datetime]::MinValue } }; Descending = $true }, Volume
    foreach ($item in $sorted) {
      if (-not $seen.Add(('{0}|{1}' -f $item.Connection.Id, $item.Volume))) {
        continue
      }
      if ($Latest -and -not $seen.Add(('latest|{0}|{1}' -f $item.Connection.Id, $item.VMId))) {
        continue
      }
      $item
    }
  }
}
