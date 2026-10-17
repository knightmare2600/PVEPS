function Resolve-PVEDeviceTarget {
  <#
  .SYNOPSIS
  Resolves the targets of a device cmdlet into one { Guest; Config; Devices } entry per guest.
  .DESCRIPTION
  Guests are resolved with Resolve-PVEGuestTarget. For each guest the configuration is read once, the
  devices of -Kind listed (Get-PVEGuestDevice), and kept if they match any device name given with the
  targets for that guest (all of them if none was given). A non-wildcard device name that matches
  nothing is a "not found" error. A guest whose configuration cannot be read is an error and is left out.
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

    [Parameter(Mandatory)]
    [string]$Kind,

    # Words for messages, for example 'hard disk'.
    [Parameter(Mandatory)]
    [string]$Noun,

    [switch]$IncludeTemplate
  )

  $pairs = @(Resolve-PVEGuestTarget -Cmdlet $Cmdlet -Type $Type -Target $Target -IncludeTemplate:$IncludeTemplate -PassTarget)
  foreach ($group in ($pairs | Group-Object -Property { '{0}/{1}' -f $_.Guest.Connection.Id, $_.Guest.VMId })) {
    $guest = $group.Group[0].Guest
    $everything = @($group.Group | Where-Object { -not $_.Target.Device }).Count -gt 0
    $filters = @($group.Group | ForEach-Object { $_.Target.Device } | Where-Object { $_ } | Select-Object -Unique)

    try {
      $config = Get-PVEGuestConfig -Guest $guest
    }
    catch {
      $Cmdlet.WriteError($_)
      continue
    }
    $devices = @(Get-PVEGuestDevice -Guest $guest -Kind $Kind -Config $config)
    if (-not $everything) {
      $devices = @($devices | Where-Object { Test-PVEWildcardMatch -Value $_.Device -Pattern $filters })
      $notFound = @{
        Cmdlet = $Cmdlet
        Kind   = '{0} {1}' -f (Get-PVEGuestLabel -Guest $guest), $Noun
        Filter = $filters
        Found  = @($devices | ForEach-Object { $_.Device })
        Server = $guest.Connection.Server
      }
      Write-PVENotFound @notFound
    }
    [pscustomobject]@{ Guest = $guest; Config = $config; Devices = $devices }
  }
}
