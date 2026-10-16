function Get-PVETask {
  <#
  .SYNOPSIS
  Gets Proxmox VE tasks: recent cluster-wide tasks, the task list of specific nodes, or specific tasks by UPID.
  .DESCRIPTION
  - No node or UPID: GET /cluster/tasks (recent tasks across the cluster).
  - -Node: GET /nodes/{node}/tasks, with optional filters.
  - -Upid: GET /nodes/{node}/tasks/{upid}/status. The node is read from the UPID.
  Every task object carries its connection, so it can be piped to Wait-PVETask against the right server.
  .PARAMETER Upid
  Task identifier(s), as returned by asynchronous PVE operations.
  .PARAMETER Node
  Node name(s) whose task list to read.
  .PARAMETER VMId
  Only tasks for this guest ID (with -Node).
  .PARAMETER ErrorsOnly
  Only tasks that ended in error (with -Node).
  .PARAMETER Source
  archive (finished, the PVE default), active (running), or all (with -Node).
  .PARAMETER Limit
  Maximum number of tasks per node (with -Node).
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection.
  .EXAMPLE
  Get-PVETask
  .EXAMPLE
  Get-PVETask -Node pve01 -VMId 9001 -Source all
  .EXAMPLE
  Get-PVETask -Upid 'UPID:pve01:0001A2B3:...'
  #>
  [CmdletBinding(DefaultParameterSetName = 'Cluster')]
  [OutputType('PVEPS.Task')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Upid', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [ValidatePattern('^UPID:[^:]+:')]
    [string[]]$Upid,

    [Parameter(Mandatory, ParameterSetName = 'Node')]
    [ValidateNotNullOrEmpty()]
    [string[]]$Node,

    [Parameter(ParameterSetName = 'Node')]
    [ValidateRange(1, 999999999)]
    [int]$VMId,

    [Parameter(ParameterSetName = 'Node')]
    [switch]$ErrorsOnly,

    [Parameter(ParameterSetName = 'Node')]
    [ValidateSet('archive', 'active', 'all')]
    [string]$Source,

    [Parameter(ParameterSetName = 'Node')]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Limit,

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
      switch ($PSCmdlet.ParameterSetName) {
        'Cluster' {
          try {
            Invoke-PVERequest -Connection $connection -Path '/cluster/tasks' | ConvertTo-PVETask -Connection $connection
          }
          catch {
            $PSCmdlet.WriteError($_)
          }
        }

        'Node' {
          $query = @{}
          if ($PSBoundParameters.ContainsKey('VMId')) { $query.vmid = $VMId }
          if ($ErrorsOnly) { $query.errors = $true }
          if ($Source) { $query.source = $Source }
          if ($PSBoundParameters.ContainsKey('Limit')) { $query.limit = $Limit }
          foreach ($nodeName in $Node) {
            try {
              $path = Format-PVEPath '/nodes/{node}/tasks' @{ node = $nodeName }
              Invoke-PVERequest -Connection $connection -Path $path -Parameters $query | ConvertTo-PVETask -Connection $connection
            }
            catch {
              $PSCmdlet.WriteError($_)
            }
          }
        }

        'Upid' {
          foreach ($id in $Upid) {
            try {
              $null = $id -match '^UPID:([^:]+):'
              $path = Format-PVEPath '/nodes/{node}/tasks/{upid}/status' @{ node = $Matches[1]; upid = $id }
              Invoke-PVERequest -Connection $connection -Path $path | ConvertTo-PVETask -Connection $connection
            }
            catch {
              $PSCmdlet.WriteError($_)
            }
          }
        }
      }
    }
  }
}
