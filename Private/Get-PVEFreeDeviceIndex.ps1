function Get-PVEFreeDeviceIndex {
  <#
  .SYNOPSIS
  Returns the lowest index N for which Prefix + N (for example scsi1) is not in -Used.
  .DESCRIPTION
  -Count is the number of slots the bus has (from the API schema: ide 4, sata 6, scsi 31, virtio 16,
  LXC mp 256). Without -Count there is no upper bound and PVE enforces any limit. Throws when the bus is
  full.
  #>
  [CmdletBinding()]
  [OutputType([int])]
  param(
    [Parameter(Mandatory)]
    [string]$Prefix,

    [AllowEmptyCollection()]
    [string[]]$Used = @(),

    [int]$Count = [int]::MaxValue
  )

  for ($i = 0; $i -lt $Count; $i++) {
    if ("$Prefix$i" -notin $Used) {
      return $i
    }
  }
  throw "All $Count $Prefix slots are in use."
}
