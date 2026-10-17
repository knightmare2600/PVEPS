function Test-PVECloudInitVolume {
  <#
  .SYNOPSIS
  True if a volume ID is a PVE cloud-init drive image, which PVE names vm-<vmid>-cloudinit (with a file
  extension on file-based storage), for example local-lvm:vm-100-cloudinit or
  local:100/vm-100-cloudinit.qcow2.
  #>
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [AllowNull()]
    [AllowEmptyString()]
    [string]$Volume
  )

  $Volume -match '^[^:]+:(.*/)?vm-\d+-cloudinit(\.\w+)?$'
}
