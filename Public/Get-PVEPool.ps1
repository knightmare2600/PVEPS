function Get-PVEPool {
  <#
  .SYNOPSIS
  Gets resource pools and their members.
  .DESCRIPTION
  Lists pools from /pools, then reads each matching pool's members with GET /pools?poolid=<id> (the
  per-pool path /pools/{poolid} is deprecated in the API). Only pools the caller has Pool.Audit on are
  visible.

  A non-wildcard -Name that matches no pool is reported as a non-terminating "not found" error.
  .PARAMETER Name
  Pool ID(s). Wildcards allowed.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection.
  .EXAMPLE
  Get-PVEPool
  .EXAMPLE
  (Get-PVEPool lab).Members | Where-Object Type -EQ 'qemu'
  #>
  [CmdletBinding()]
  [OutputType('PVEPS.Pool')]
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
        $poolIds = @(
          Invoke-PVERequest -Connection $connection -Path '/pools' |
            ForEach-Object { [string](Get-PVEValue $_ 'poolid') } |
            Where-Object { Test-PVEWildcardMatch -Value $_ -Pattern $Name } |
            Sort-Object
        )
      }
      catch {
        $PSCmdlet.WriteError($_)
        continue
      }

      foreach ($poolId in $poolIds) {
        try {
          $raw = @(Invoke-PVERequest -Connection $connection -Path '/pools' -Parameters @{ poolid = $poolId }) |
            Where-Object { (Get-PVEValue $_ 'poolid') -eq $poolId } |
            Select-Object -First 1
        }
        catch {
          $PSCmdlet.WriteError($_)
          continue
        }

        # Assign first: Get-PVEValue returns an array as a single object, so @(Get-PVEValue ...) would
        # wrap it in a second array.
        $memberList = Get-PVEValue $raw 'members'
        $members = foreach ($member in @($memberList)) {
          if ($null -eq $member) {
            continue
          }
          $vmid = Get-PVEValue $member 'vmid'
          [pscustomobject]@{
            PSTypeName = 'PVEPS.PoolMember'
            Type       = Get-PVEValue $member 'type'
            Id         = Get-PVEValue $member 'id'
            VMId       = if ($null -ne $vmid) { [int]$vmid } else { $null }
            Name       = Get-PVEValue $member 'name'
            Node       = Get-PVEValue $member 'node'
            Storage    = Get-PVEValue $member 'storage'
            Status     = Get-PVEValue $member 'status'
          }
        }

        [pscustomobject]@{
          PSTypeName = 'PVEPS.Pool'
          Name       = $poolId
          Comment    = Get-PVEValue $raw 'comment'
          Members    = @($members)
          Connection = $connection
        }
      }

      if ($Name) {
        Write-PVENotFound -Cmdlet $PSCmdlet -Kind 'Pool' -Filter $Name -Found $poolIds -Server $connection.Server
      }
    }
  }
}
