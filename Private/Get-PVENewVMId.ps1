function Get-PVENewVMId {
  <#
  .SYNOPSIS
  Returns the ID for a new guest: -VMId after checking it is free, or else the next free ID.
  .DESCRIPTION
  Both use GET /cluster/nextid; with ?vmid= PVE checks that ID is free (at the time of the check) and
  errors if not. The check is not a reservation: something else can still take the ID before the create
  request, in which case the create fails.
  #>
  [CmdletBinding()]
  [OutputType([int])]
  param(
    [Parameter(Mandatory)]
    [psobject]$Connection,

    [int]$VMId
  )

  $parameters = if ($VMId) { @{ vmid = $VMId } } else { @{} }
  [int](Invoke-PVERequest -Connection $Connection -Path '/cluster/nextid' -Parameters $parameters)
}
