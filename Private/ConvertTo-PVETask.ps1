function ConvertTo-PVETask {
  <#
  .SYNOPSIS
  Normalises a task record from any PVE task endpoint into a PVEPS.Task object.
  .DESCRIPTION
  The endpoints disagree on field meaning:
  - GET /nodes/{node}/tasks/{upid}/status: "status" is running|stopped, "exitstatus" is the result.
  - GET /nodes/{node}/tasks and /cluster/tasks: "status" is the result of a finished task (with
    "endtime" set); running tasks have no "endtime".
  This function maps both to State (Running/Stopped) and ExitStatus.
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

    $upid = [string](Get-PVEValue $raw 'upid')
    $node = [string](Get-PVEValue $raw 'node')
    if (-not $node -and $upid -match '^UPID:([^:]+):') {
      $node = $Matches[1]
    }

    $exitStatus = Get-PVEValue $raw 'exitstatus'
    $rawStatus = Get-PVEValue $raw 'status'
    $endTime = Get-PVEValue $raw 'endtime'

    if ($rawStatus -eq 'running') {
      $state = 'Running'
    }
    elseif ($rawStatus -eq 'stopped') {
      $state = 'Stopped'
    }
    elseif ($endTime) {
      $state = 'Stopped'
      $exitStatus = $rawStatus
    }
    else {
      $state = 'Running'
    }

    $succeeded = $null
    if ($state -eq 'Stopped') {
      $succeeded = $exitStatus -eq 'OK' -or $exitStatus -like 'WARNINGS*'
    }

    [pscustomobject]@{
      PSTypeName = 'PVEPS.Task'
      Upid       = $upid
      Node       = $node
      Type       = Get-PVEValue $raw 'type'
      Id         = Get-PVEValue $raw 'id'
      User       = Get-PVEValue $raw 'user'
      State      = $state
      ExitStatus = $exitStatus
      Succeeded  = $succeeded
      StartTime  = ConvertFrom-PVEUnixTime (Get-PVEValue $raw 'starttime')
      EndTime    = ConvertFrom-PVEUnixTime $endTime
      Connection = $Connection
    }
  }
}
