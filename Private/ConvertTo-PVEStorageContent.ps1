function ConvertTo-PVEStorageContent {
  <#
  .SYNOPSIS
  Converts one entry of GET /nodes/{node}/storage/{storage}/content into a PVEPS.StorageContent object.
  .DESCRIPTION
  Content is the entry's own content field. The API schema does not list that field, so it is $null if
  PVE leaves it out; -Content (the type the listing was filtered by) fills it in then. SizeGB is the
  size, or PVE's approximate-size where the storage reports only that. GuestType is qemu or lxc for
  backups (from PVE's subtype field, or else from PVE's vzdump-qemu-/vzdump-lxc- file names and PBS's
  backup/vm/ and backup/ct/ paths), and $null otherwise.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [psobject]$InputObject,

    [Parameter(Mandatory)]
    [string]$Storage,

    [Parameter(Mandatory)]
    [string]$Node,

    [string]$Content,

    [Parameter(Mandatory)]
    [psobject]$Connection
  )

  $raw = $InputObject
  $volume = [string](Get-PVEValue $raw 'volid')
  $kind = Get-PVEValue $raw 'content'
  if (-not $kind -and $Content) {
    $kind = $Content
  }
  $size = Get-PVEValue $raw 'size'
  if ($null -eq $size) {
    $size = Get-PVEValue $raw 'approximate-size'
  }
  $ctime = Get-PVEValue $raw 'ctime'
  $vmid = Get-PVEValue $raw 'vmid'

  $guestType = $null
  if ($kind -eq 'backup') {
    $subtype = [string](Get-PVEValue $raw 'subtype')
    $guestType = switch -Regex ("$subtype|$volume") {
      '^qemu\||vzdump-qemu-|:backup/vm/' { 'qemu'; break }
      '^lxc\||vzdump-lxc-|:backup/ct/' { 'lxc'; break }
      default { $null }
    }
  }

  [pscustomobject]@{
    PSTypeName = 'PVEPS.StorageContent'
    Volume     = $volume
    Storage    = $Storage
    Node       = $Node
    Content    = $kind
    Format     = Get-PVEValue $raw 'format'
    SizeGB     = ConvertTo-PVEGB $size
    Created    = if ($null -ne $ctime) { ConvertFrom-PVEUnixTime $ctime } else { $null }
    VMId       = if ($null -ne $vmid) { [int]$vmid } else { $null }
    GuestType  = $guestType
    Notes      = Get-PVEValue $raw 'notes'
    Protected  = [bool][int](Get-PVEValue $raw 'protected')
    Connection = $Connection
  }
}
