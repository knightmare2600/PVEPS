function Get-PVEGuestById {
  <#
  .SYNOPSIS
  Gets one guest by node and ID, as a PVEPS.VM / PVEPS.Container object with live status.
  .DESCRIPTION
  Used after creating or cloning a guest. Takes the /cluster/resources entry if there is one (for the pool
  and disk usage), then refreshes it from the live status/current endpoint. If /cluster/resources does not
  list the guest yet, the object is built from status/current alone, with -Pool as given.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [psobject]$Connection,

    [Parameter(Mandatory)]
    [ValidateSet('qemu', 'lxc')]
    [string]$Type,

    [Parameter(Mandatory)]
    [string]$Node,

    [Parameter(Mandatory)]
    [int]$VMId,

    [string]$Pool
  )

  $entry = Invoke-PVERequest -Connection $Connection -Path '/cluster/resources' -Parameters @{ type = 'vm' } |
    Where-Object { (Get-PVEValue $_ 'type') -eq $Type -and [int](Get-PVEValue $_ 'vmid') -eq $VMId } |
    Select-Object -First 1
  if ($null -eq $entry) {
    Write-Verbose "$Type $VMId is not in /cluster/resources yet; reading status/current only."
    $entry = @{ type = $Type; vmid = $VMId; node = $Node; pool = $(if ($Pool) { $Pool } else { $null }) }
  }
  $guest = ConvertTo-PVEGuest -InputObject $entry -Connection $Connection
  Update-PVEGuestStatus -Guest $guest
}
