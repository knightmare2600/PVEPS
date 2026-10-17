function Resolve-PVESnapshotTarget {
  <#
  .SYNOPSIS
  Resolves the targets of a snapshot cmdlet into one { Guest; Snapshots } entry per guest.
  .DESCRIPTION
  Like Resolve-PVEDeviceTarget, with the snapshot names (or patterns) carried in each target's Device
  field: guests are resolved with Resolve-PVEGuestTarget, each guest's snapshots listed once, and kept if
  they match a name given for that guest (all of them if none was). A non-wildcard name that matches
  nothing is a "not found" error.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCmdlet]$Cmdlet,

    [Parameter(Mandatory)]
    [ValidateSet('qemu', 'lxc')]
    [string]$Type,

    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [System.Collections.Generic.List[psobject]]$Target,

    [switch]$IncludeTemplate
  )

  $pairs = @(Resolve-PVEGuestTarget -Cmdlet $Cmdlet -Type $Type -Target $Target -IncludeTemplate:$IncludeTemplate -PassTarget)
  foreach ($group in ($pairs | Group-Object -Property { '{0}/{1}' -f $_.Guest.Connection.Id, $_.Guest.VMId })) {
    $guest = $group.Group[0].Guest
    $everything = @($group.Group | Where-Object { -not $_.Target.Device }).Count -gt 0
    $filters = @($group.Group | ForEach-Object { $_.Target.Device } | Where-Object { $_ } | Select-Object -Unique)
    try {
      $snapshots = @(Get-PVEGuestSnapshot -Guest $guest)
    }
    catch {
      $Cmdlet.WriteError($_)
      continue
    }
    if (-not $everything) {
      $snapshots = @($snapshots | Where-Object { Test-PVEWildcardMatch -Value $_.Snapshot -Pattern $filters })
      $notFound = @{
        Cmdlet = $Cmdlet
        Kind   = '{0} snapshot' -f (Get-PVEGuestLabel -Guest $guest)
        Filter = $filters
        Found  = @($snapshots | ForEach-Object { $_.Snapshot })
        Server = $guest.Connection.Server
      }
      Write-PVENotFound @notFound
    }
    [pscustomobject]@{ Guest = $guest; Snapshots = $snapshots }
  }
}
