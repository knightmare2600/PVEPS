function Wait-PVEOperation {
  <#
  .SYNOPSIS
  Waits for the tasks of several operations together and returns the operations that succeeded, in
  their original order.
  .DESCRIPTION
  Each operation has Upid and Connection. One whose Upid is not a task UPID (an endpoint that finished
  synchronously) counts as succeeded. Failed and timed-out tasks are errors from Wait-PVETask.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [System.Collections.Generic.List[psobject]]$Operation
  )

  $succeeded = [System.Collections.Generic.HashSet[string]]::new()
  $tasks = @(
    foreach ($op in $Operation) {
      if ($op.Upid -match '^UPID:') {
        [pscustomobject]@{ Upid = $op.Upid; Connection = $op.Connection }
      }
    }
  )
  if ($tasks.Count -gt 0) {
    foreach ($task in @($tasks | Wait-PVETask)) {
      $null = $succeeded.Add($task.Upid)
    }
  }
  foreach ($op in $Operation) {
    if ($op.Upid -notmatch '^UPID:' -or $succeeded.Contains($op.Upid)) {
      $op
    }
  }
}
