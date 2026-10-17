function ConvertTo-PVEHardDisk {
  <#
  .SYNOPSIS
  Converts one QEMU disk entry (ide/sata/scsi/virtio N) into a PVEPS.HardDisk object.
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
    PSTypeName = 'PVEPS.HardDisk'
    VMId       = $Guest.VMId
    VMName     = $Guest.Name
    Node       = $Guest.Node
    Device     = $Device
    Bus        = $Device -replace '\d+$', ''
    Volume     = $volume
    Storage    = if ($volume -match '^([^:/]+):') { $Matches[1] } else { $null }
    SizeGB     = ConvertTo-PVEGB (ConvertFrom-PVESize ([string]$option['size']))
    Cache      = $option['cache']
    Discard    = $option['discard'] -eq 'on'
    SSD        = $option['ssd'] -eq '1'
    IOThread   = $option['iothread'] -eq '1'
    ReadOnly   = $option['ro'] -eq '1'
    Options    = $option
    Type       = 'qemu'
    Connection = $Guest.Connection
  }
}
