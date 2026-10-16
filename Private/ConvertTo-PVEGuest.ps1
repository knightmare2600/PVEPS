function ConvertTo-PVEGuest {
  <#
  .SYNOPSIS
  Converts a /cluster/resources entry of type qemu or lxc into a PVEPS.VM or PVEPS.Container object.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory, ValueFromPipeline)]
    [psobject]$InputObject,

    [Parameter(Mandatory)]
    [psobject]$Connection
  )

  process {
    $raw = $InputObject
    $type = [string](Get-PVEValue $raw 'type')
    $cpu = Get-PVEValue $raw 'cpu'
    $uptime = Get-PVEValue $raw 'uptime'
    $tags = [string](Get-PVEValue $raw 'tags')

    [pscustomobject]@{
      PSTypeName      = if ($type -eq 'lxc') { 'PVEPS.Container' } else { 'PVEPS.VM' }
      VMId            = [int](Get-PVEValue $raw 'vmid')
      Name            = [string](Get-PVEValue $raw 'name')
      Node            = [string](Get-PVEValue $raw 'node')
      Status          = [string](Get-PVEValue $raw 'status')
      IsTemplate      = [bool][int](Get-PVEValue $raw 'template')
      Cpus            = Get-PVEValue $raw 'maxcpu'
      MemoryGB        = ConvertTo-PVEGB (Get-PVEValue $raw 'maxmem')
      MemoryUsedGB    = ConvertTo-PVEGB (Get-PVEValue $raw 'mem')
      DiskGB          = ConvertTo-PVEGB (Get-PVEValue $raw 'maxdisk')
      DiskUsedGB      = ConvertTo-PVEGB (Get-PVEValue $raw 'disk')
      CpuUsagePercent = if ($null -ne $cpu) { [math]::Round([double]$cpu * 100, 1) } else { $null }
      Uptime          = if ($null -ne $uptime) { [timespan]::FromSeconds([double]$uptime) } else { $null }
      Tags            = [string[]]@($tags -split '[;,\s]+' | Where-Object { $_ })
      Pool            = Get-PVEValue $raw 'pool'
      Lock            = Get-PVEValue $raw 'lock'
      Type            = $type
      Connection      = $Connection
    }
  }
}
