function Resolve-PVEGuestTarget {
  <#
  .SYNOPSIS
  Resolves the -VMId / -Name targets collected by Add-PVEGuestTarget into guest objects.
  .DESCRIPTION
  Reads /cluster/resources once per connection. Unknown IDs and exact names, and guests of the other type,
  are reported as errors on the calling cmdlet (with a hint naming the right cmdlets). Each guest is
  written once, in the order first named, even if several targets match it.

  An ID names exactly one guest, so it matches templates too. A name matches templates only with
  -IncludeTemplate, so a wildcard such as 'web*' does not sweep up templates by accident.

  With -PassTarget, writes one { Guest; Target } pair per target and matching guest instead, without
  removing duplicates, so device cmdlets can tell which devices were asked for on which guest. Pairs
  for the same guest share the same guest object.
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

    [switch]$IncludeTemplate,

    [switch]$PassTarget
  )

  $kind = if ($Type -eq 'qemu') { 'VM' } else { 'Container' }
  $otherHint = if ($Type -eq 'qemu') { 'It is a container; use the *-PVEContainer cmdlets.' } else { 'It is a VM; use the *-PVEVM cmdlets.' }
  $templateHint = 'It is a template; add -IncludeTemplate.'
  $seen = [System.Collections.Generic.HashSet[string]]::new()

  foreach ($group in ($Target | Group-Object -Property { $_.Connection.Id })) {
    $connection = $group.Group[0].Connection
    try {
      $guests = @(Invoke-PVERequest -Connection $connection -Path '/cluster/resources' -Parameters @{ type = 'vm' } | ConvertTo-PVEGuest -Connection $connection)
    }
    catch {
      $Cmdlet.WriteError($_)
      continue
    }

    foreach ($item in $group.Group) {
      if ($null -ne $item.VMId) {
        $found = @($guests | Where-Object { $_.VMId -eq $item.VMId })
        if ($found.Count -eq 0) {
          Write-PVENotFound -Cmdlet $Cmdlet -Kind "$kind with ID" -Filter $item.VMId -Found @() -Server $connection.Server
        }
        elseif ($found[0].Type -ne $Type) {
          Write-PVENotFound -Cmdlet $Cmdlet -Kind "$kind with ID" -Filter $item.VMId -Found @() -Server $connection.Server -HintValue $item.VMId -Hint $otherHint
          $found = @()
        }
      }
      else {
        $named = @($guests | Where-Object { $_.Type -eq $Type -and $_.Name -like $item.Name } | Sort-Object -Property VMId)
        $found = @($named | Where-Object { $IncludeTemplate -or -not $_.IsTemplate })
        if ($found.Count -eq 0) {
          if ($named.Count -gt 0) {
            Write-PVENotFound -Cmdlet $Cmdlet -Kind "$kind with name" -Filter $item.Name -Found @() -Server $connection.Server -HintValue $item.Name -Hint $templateHint
          }
          else {
            $otherNames = @($guests | Where-Object { $_.Type -ne $Type } | ForEach-Object { $_.Name })
            Write-PVENotFound -Cmdlet $Cmdlet -Kind "$kind with name" -Filter $item.Name -Found @() -Server $connection.Server -HintValue $otherNames -Hint $otherHint
          }
        }
      }

      foreach ($guest in $found) {
        if ($PassTarget) {
          [pscustomobject]@{ Guest = $guest; Target = $item }
          continue
        }
        if ($seen.Add(('{0}/{1}' -f $connection.Id, $guest.VMId))) {
          $guest
        }
      }
    }
  }
}
