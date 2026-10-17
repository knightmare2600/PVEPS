function Get-PVEGuestVolume {
  <#
  .SYNOPSIS
  Lists the storage-backed volumes in a guest configuration: the disks a move can relocate.
  .DESCRIPTION
  Reads GET /nodes/{node}/{type}/{vmid}/config and returns one object per volume, with Key (for example
  scsi0 or rootfs), Volume (the volume ID) and Storage.

  QEMU: ide/sata/scsi/virtio disks, efidisk0 and tpmstate0. CD drives (media=cdrom) and empty drives
  (none) are left out. LXC: rootfs and mp mount points. In both, entries whose volume is an absolute
  path rather than a storage volume (pass-through devices, bind mounts) are left out.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [psobject]$Guest
  )

  $config = Get-PVEGuestConfig -Guest $Guest
  if ($Guest.Type -eq 'lxc') {
    $pattern = '^(rootfs|mp\d+)$'
    $defaultKey = 'volume'
  }
  else {
    $pattern = '^((ide|sata|scsi|virtio)\d+|efidisk0|tpmstate0)$'
    $defaultKey = 'file'
  }

  foreach ($key in (Get-PVEConfigKey -Config $config | Where-Object { $_ -match $pattern } | Sort-Object)) {
    $option = ConvertFrom-PVEPropertyString -Value ([string](Get-PVEValue $config $key)) -DefaultKey $defaultKey
    $volume = [string]$option[$defaultKey]
    if ($option['media'] -eq 'cdrom' -or $volume -eq 'none' -or $volume.StartsWith('/') -or $volume -notmatch '^[^:]+:') {
      continue
    }
    [pscustomobject]@{
      Key     = $key
      Volume  = $volume
      Storage = $volume.Substring(0, $volume.IndexOf(':'))
    }
  }
}
