function Get-PVEGuestDevice {
  <#
  .SYNOPSIS
  Lists one kind of device from a guest configuration, as device objects, sorted by bus and index.
  .DESCRIPTION
  - HardDisk: QEMU ide/sata/scsi/virtio N entries that are not CD drives.
  - CDDrive: QEMU ide/sata/scsi N entries with media=cdrom, except cloud-init drives.
  - CloudInitDrive: QEMU entries whose volume is a cloud-init image (Test-PVECloudInitVolume).
  - VMNetworkAdapter: QEMU netN entries.
  - ContainerVolume: LXC rootfs and mpN entries.
  - ContainerNetworkAdapter: LXC netN entries.
  Reads the configuration unless it is passed as -Config.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [psobject]$Guest,

    [Parameter(Mandatory)]
    [ValidateSet('HardDisk', 'CDDrive', 'CloudInitDrive', 'VMNetworkAdapter', 'ContainerVolume', 'ContainerNetworkAdapter')]
    [string]$Kind,

    [AllowNull()]
    [object]$Config
  )

  if (-not $PSBoundParameters.ContainsKey('Config')) {
    $Config = Get-PVEGuestConfig -Guest $Guest
  }

  $pattern = switch ($Kind) {
    'HardDisk' { '^(ide|sata|scsi|virtio)\d+$' }
    'CDDrive' { '^(ide|sata|scsi)\d+$' }
    'CloudInitDrive' { '^(ide|sata|scsi)\d+$' }
    'VMNetworkAdapter' { '^net\d+$' }
    'ContainerVolume' { '^(rootfs|mp\d+)$' }
    'ContainerNetworkAdapter' { '^net\d+$' }
  }
  $keys = @(
    Get-PVEConfigKey -Config $Config |
      Where-Object { $_ -match $pattern } |
      Sort-Object -Property { if ($_ -eq 'rootfs') { '' } else { $_ -replace '\d+$', '' } }, { [int]($_ -replace '^\D+', '0') }
  )

  foreach ($key in $keys) {
    $value = [string](Get-PVEValue $Config $key)
    switch ($Kind) {
      'HardDisk' {
        if ((ConvertFrom-PVEPropertyString -Value $value -DefaultKey file)['media'] -ne 'cdrom') {
          ConvertTo-PVEHardDisk -Guest $Guest -Device $key -Value $value
        }
      }
      { $_ -in 'CDDrive', 'CloudInitDrive' } {
        $option = ConvertFrom-PVEPropertyString -Value $value -DefaultKey file
        $isCloudInit = Test-PVECloudInitVolume -Volume ([string]$option['file'])
        if ($Kind -eq 'CloudInitDrive' -and $isCloudInit) {
          ConvertTo-PVECDDrive -Guest $Guest -Device $key -Value $value
        }
        elseif ($Kind -eq 'CDDrive' -and $option['media'] -eq 'cdrom' -and -not $isCloudInit) {
          ConvertTo-PVECDDrive -Guest $Guest -Device $key -Value $value
        }
      }
      'VMNetworkAdapter' { ConvertTo-PVEVMNetworkAdapter -Guest $Guest -Device $key -Value $value }
      'ContainerVolume' { ConvertTo-PVEContainerVolume -Guest $Guest -Device $key -Value $value }
      'ContainerNetworkAdapter' { ConvertTo-PVEContainerNetworkAdapter -Guest $Guest -Device $key -Value $value }
    }
  }
}
