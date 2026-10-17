function Invoke-PVESnapshotOperation {
  <#
  .SYNOPSIS
  Shared engine for the snapshot cmdlets: one request per guest and snapshot, waited for together.
  .DESCRIPTION
  For each item ({ Guest; Snapshot }), asks ShouldProcess on the calling cmdlet with -Description (where
  {snapshot} is replaced by the snapshot name), then sends -Method to /nodes/{node}/{type}/{vmid}/snapshot
  plus -Suffix ('{snapshot}' in it is replaced by the URL-escaped name), with -Body ('{snapshot}' in a
  value is replaced too). Then waits for all tasks (Wait-PVEOperation) and writes, per -Output:
  Snapshot, the snapshot as it now is; Guest, the guest with its live status; None, nothing. With
  -RunAsync, writes the tasks instead.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Calls ShouldProcess on the calling public cmdlet, passed as -Cmdlet, so its -WhatIf and -Confirm apply.')]
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCmdlet]$Cmdlet,

    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [psobject[]]$Item,

    [Parameter(Mandatory)]
    [ValidateSet('POST', 'PUT', 'DELETE')]
    [string]$Method,

    [AllowEmptyString()]
    [string]$Suffix = '',

    [hashtable]$Body = @{},

    [Parameter(Mandatory)]
    [string]$Description,

    [Parameter(Mandatory)]
    [ValidateSet('Snapshot', 'Guest', 'None')]
    [string]$Output,

    [switch]$RunAsync
  )

  $operations = [System.Collections.Generic.List[psobject]]::new()
  foreach ($entry in $Item) {
    $guest = $entry.Guest
    $name = $entry.Snapshot
    if (-not $Cmdlet.ShouldProcess((Get-PVEGuestLabel -Guest $guest), $Description.Replace('{snapshot}', $name))) {
      continue
    }
    $path = Format-PVEPath '/nodes/{node}/{type}/{vmid}/snapshot' @{ node = $guest.Node; type = $guest.Type; vmid = $guest.VMId }
    $path += $Suffix.Replace('{snapshot}', [uri]::EscapeDataString($name))
    $parameters = @{}
    foreach ($key in $Body.Keys) {
      $value = $Body[$key]
      $parameters[$key] = if ($value -is [string]) { $value.Replace('{snapshot}', $name) } else { $value }
    }
    try {
      $result = [string](Invoke-PVERequest -Connection $guest.Connection -Method $Method -Path $path -Parameters $parameters)
    }
    catch {
      $Cmdlet.WriteError($_)
      continue
    }
    Write-Verbose "$($Description.Replace('{snapshot}', $name)) on $(Get-PVEGuestLabel -Guest $guest): $(if ($result) { "task $result" } else { 'done' })"
    $operations.Add([pscustomobject]@{ Upid = $result; Connection = $guest.Connection; Guest = $guest; Snapshot = $name })
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
      switch ($Output) {
        'Snapshot' { Get-PVEGuestSnapshot -Guest $op.Guest | Where-Object { $_.Snapshot -eq $op.Snapshot } }
        'Guest' { Update-PVEGuestStatus -Guest $op.Guest }
      }
    }
    catch {
      $Cmdlet.WriteError($_)
    }
  }
}
