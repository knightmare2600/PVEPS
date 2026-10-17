function ConvertTo-PVEMiB {
  <#
  .SYNOPSIS
  Converts GiB (as used by the -MemoryGB style parameters) to whole MiB, the unit of the PVE memory and
  swap options.
  #>
  [CmdletBinding()]
  [OutputType([long])]
  param(
    [Parameter(Mandatory)]
    [double]$GB
  )

  [long][math]::Round($GB * 1024)
}
