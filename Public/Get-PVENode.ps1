function Get-PVENode {
  <#
  .SYNOPSIS
  Gets Proxmox VE nodes.
  .DESCRIPTION
  Lists nodes from /nodes and, for each online node, adds details from /nodes/{node}/status: PVE version,
  running kernel, CPU model, sockets and physical cores, load average, root file system and swap usage,
  and boot mode. Offline nodes are returned with those fields empty.

  The swap fields are not in the API schema; they are read as a PVE 9.2.21 node returns them. SecureBoot
  is empty unless the node booted through EFI (according to the API schema).

  A non-wildcard -Name that matches no node is reported as a non-terminating "not found" error.

  Node objects have both a Name and a Node property (Node is an alias of Name), so they can be piped to
  Get-PVEVM, Get-PVEContainer and Get-PVEStorage.
  .PARAMETER Name
  Node name(s). Wildcards allowed.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection.
  .EXAMPLE
  Get-PVENode
  .EXAMPLE
  Get-PVENode pve01 | Get-PVEVM
  #>
  [CmdletBinding()]
  [OutputType('PVEPS.Node')]
  param(
    [Parameter(Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Name,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  process {
    try {
      $connections = @(Resolve-PVEConnection -Server $Server)
    }
    catch {
      $PSCmdlet.WriteError($_)
      return
    }

    foreach ($connection in $connections) {
      try {
        $nodes = @(
          Invoke-PVERequest -Connection $connection -Path '/nodes' |
            Where-Object { Test-PVEWildcardMatch -Value (Get-PVEValue $_ 'node') -Pattern $Name } |
            Sort-Object -Property { Get-PVEValue $_ 'node' }
        )
      }
      catch {
        $PSCmdlet.WriteError($_)
        continue
      }

      foreach ($raw in $nodes) {
        $nodeName = [string](Get-PVEValue $raw 'node')
        $nodeStatus = [string](Get-PVEValue $raw 'status')

        $detail = $null
        if ($nodeStatus -eq 'online') {
          try {
            $detail = Invoke-PVERequest -Connection $connection -Path (Format-PVEPath '/nodes/{node}/status' @{ node = $nodeName })
          }
          catch {
            $PSCmdlet.WriteError($_)
          }
        }

        $cpu = Get-PVEValue $raw 'cpu'
        $uptime = Get-PVEValue $raw 'uptime'
        $cpuInfo = Get-PVEValue $detail 'cpuinfo'
        $rootFs = Get-PVEValue $detail 'rootfs'
        $swap = Get-PVEValue $detail 'swap'
        $bootInfo = Get-PVEValue $detail 'boot-info'
        $secureBoot = Get-PVEValue $bootInfo 'secureboot'
        $loadAverage = Get-PVEValue $detail 'loadavg'
        $node = [pscustomobject]@{
          PSTypeName      = 'PVEPS.Node'
          Name            = $nodeName
          Status          = $nodeStatus
          Cpus            = Get-PVEValue $raw 'maxcpu'
          CpuModel        = Get-PVEValue $cpuInfo 'model'
          CpuSockets      = Get-PVEValue $cpuInfo 'sockets'
          CpuCores        = Get-PVEValue $cpuInfo 'cores'
          CpuUsagePercent = if ($null -ne $cpu) { [math]::Round([double]$cpu * 100, 1) } else { $null }
          MemoryUsedGB    = ConvertTo-PVEGB (Get-PVEValue $raw 'mem')
          MemoryTotalGB   = ConvertTo-PVEGB (Get-PVEValue $raw 'maxmem')
          LoadAverage     = [double[]]@(@($loadAverage) | Where-Object { $null -ne $_ } | ForEach-Object { [double]::Parse([string]$_, [cultureinfo]::InvariantCulture) })
          RootFsUsedGB    = ConvertTo-PVEGB (Get-PVEValue $rootFs 'used')
          RootFsTotalGB   = ConvertTo-PVEGB (Get-PVEValue $rootFs 'total')
          SwapUsedGB      = ConvertTo-PVEGB (Get-PVEValue $swap 'used')
          SwapTotalGB     = ConvertTo-PVEGB (Get-PVEValue $swap 'total')
          Uptime          = if ($null -ne $uptime) { [timespan]::FromSeconds([double]$uptime) } else { $null }
          Version         = Get-PVEValue $detail 'pveversion'
          Kernel          = Get-PVEValue (Get-PVEValue $detail 'current-kernel') 'release'
          BootMode        = Get-PVEValue $bootInfo 'mode'
          SecureBoot      = if ($null -ne $secureBoot) { [bool][int]$secureBoot } else { $null }
          SslFingerprint  = Get-PVEValue $raw 'ssl_fingerprint'
          Connection      = $connection
        }
        $node | Add-Member -MemberType AliasProperty -Name Node -Value Name
        $node
      }

      if ($Name) {
        Write-PVENotFound -Cmdlet $PSCmdlet -Kind 'Node' -Filter $Name -Found @($nodes | ForEach-Object { Get-PVEValue $_ 'node' }) -Server $connection.Server
      }
    }
  }
}
