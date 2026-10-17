function ConvertTo-PVECDDrive {
  <#
  .SYNOPSIS
  Converts one QEMU CD drive entry (media=cdrom) into a PVEPS.CDDrive object.
  .DESCRIPTION
  IsoImage is the inserted volume, or $null when the drive is empty (file 'none'). 'cdrom' means the
  host's physical drive.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [psobject]$Guest,

    [Parameter(Mandatory)]
    [string]$Device,

    [Parameter(Mandatory)]
    [string]$Value
  )

  $option = ConvertFrom-PVEPropertyString -Value $Value -DefaultKey file
  $volume = [string]$option['file']
  [pscustomobject]@{
    PSTypeName = 'PVEPS.CDDrive'
    VMId       = $Guest.VMId
    VMName     = $Guest.Name
    Node       = $Guest.Node
    Device     = $Device
    IsoImage   = if ($volume -and $volume -ne 'none') { $volume } else { $null }
    Storage    = if ($volume -match '^([^:/]+):') { $Matches[1] } else { $null }
    Options    = $option
    Type       = 'qemu'
    Connection = $Guest.Connection
  }
}
