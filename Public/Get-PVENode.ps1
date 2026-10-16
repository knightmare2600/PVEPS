function Get-PVENode {
  <#
  .SYNOPSIS
  Gets Proxmox VE nodes.
  .DESCRIPTION
  Lists nodes from /nodes and, for each online node, adds the PVE version, running kernel and CPU model
  from /nodes/{node}/status. Offline nodes are returned with those fields empty.

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
        $node = [pscustomobject]@{
          PSTypeName      = 'PVEPS.Node'
          Name            = $nodeName
          Status          = $nodeStatus
          Cpus            = Get-PVEValue $raw 'maxcpu'
          CpuModel        = Get-PVEValue (Get-PVEValue $detail 'cpuinfo') 'model'
          CpuUsagePercent = if ($null -ne $cpu) { [math]::Round([double]$cpu * 100, 1) } else { $null }
          MemoryUsedGB    = ConvertTo-PVEGB (Get-PVEValue $raw 'mem')
          MemoryTotalGB   = ConvertTo-PVEGB (Get-PVEValue $raw 'maxmem')
          Uptime          = if ($null -ne $uptime) { [timespan]::FromSeconds([double]$uptime) } else { $null }
          Version         = Get-PVEValue $detail 'pveversion'
          Kernel          = Get-PVEValue (Get-PVEValue $detail 'current-kernel') 'release'
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
