function Update-PVEGuestStatus {
  <#
  .SYNOPSIS
  Refreshes a PVEPS.VM / PVEPS.Container object from the live /nodes/{node}/{type}/{vmid}/status/current
  endpoint, and returns the object.
  .DESCRIPTION
  /cluster/resources is a cached summary, so a guest started, stopped or reconfigured a moment ago can
  still show old values there. Cmdlets that change a guest decide on, and write, the values from this
  live endpoint instead.

  Status, Uptime and Lock are always replaced. Tags are replaced, and are empty when the endpoint omits
  them (its schema: "the current configured tags, if any"). Name, Cpus, MemoryGB, MemoryUsedGB, DiskGB,
  CpuUsagePercent and IsTemplate are replaced when the endpoint returns them. Pool and DiskUsedGB are not
  on this endpoint and keep their /cluster/resources values.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private helper; only updates a local object from a GET request.')]
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [psobject]$Guest
  )

  $path = Format-PVEPath '/nodes/{node}/{type}/{vmid}/status/current' @{
    node = $Guest.Node
    type = $Guest.Type
    vmid = $Guest.VMId
  }
  $current = Invoke-PVERequest -Connection $Guest.Connection -Path $path

  $status = Get-PVEValue $current 'status'
  if ($status) {
    $Guest.Status = [string]$status
  }
  $uptime = Get-PVEValue $current 'uptime'
  $Guest.Uptime = if ($null -ne $uptime) { [timespan]::FromSeconds([double]$uptime) } else { $null }
  $Guest.Lock = Get-PVEValue $current 'lock'
  $tags = [string](Get-PVEValue $current 'tags')
  $Guest.Tags = [string[]]@($tags -split '[;,\s]+' | Where-Object { $_ })

  $name = Get-PVEValue $current 'name'
  if ($null -ne $name) {
    $Guest.Name = [string]$name
  }
  $cpus = Get-PVEValue $current 'cpus'
  if ($null -ne $cpus) {
    $Guest.Cpus = $cpus
  }
  $maxmem = Get-PVEValue $current 'maxmem'
  if ($null -ne $maxmem) {
    $Guest.MemoryGB = ConvertTo-PVEGB $maxmem
  }
  $mem = Get-PVEValue $current 'mem'
  if ($null -ne $mem) {
    $Guest.MemoryUsedGB = ConvertTo-PVEGB $mem
  }
  $maxdisk = Get-PVEValue $current 'maxdisk'
  if ($null -ne $maxdisk) {
    $Guest.DiskGB = ConvertTo-PVEGB $maxdisk
  }
  $cpu = Get-PVEValue $current 'cpu'
  if ($null -ne $cpu) {
    $Guest.CpuUsagePercent = [math]::Round([double]$cpu * 100, 1)
  }
  $template = Get-PVEValue $current 'template'
  if ($null -ne $template) {
    $Guest.IsTemplate = [bool][int]$template
  }
  $Guest
}
