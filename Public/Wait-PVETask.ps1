function Wait-PVETask {
  <#
  .SYNOPSIS
  Waits for Proxmox VE tasks to finish.
  .DESCRIPTION
  Polls each task's status until it stops, starting at 0.5 s between polls and backing off to 5 s. Every
  task piped in is waited on at the same time.

  - A task that ends with OK is written to the output.
  - A task that ends with WARNINGS is written to the output, with a warning.
  - A task that ends with any other exit status is a non-terminating error. The task object is the
    error's TargetObject and is not written to the output, so a following pipeline stage only receives
    tasks that succeeded.
  - A task still running when -TimeoutSec runs out is a non-terminating error. The task itself is not
    cancelled.
  .PARAMETER Upid
  Task UPID(s). Binds from piped task objects or plain UPID strings.
  .PARAMETER Server
  Connection to use for plain UPID strings. Task objects carry their own connection. Defaults to the
  default connection.
  .PARAMETER TimeoutSec
  Maximum seconds to wait. 0 (the default) waits without limit.
  .EXAMPLE
  Get-PVETask -Upid $upid | Wait-PVETask -TimeoutSec 300
  #>
  [CmdletBinding()]
  [OutputType('PVEPS.Task')]
  param(
    [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [ValidatePattern('^UPID:[^:]+:')]
    [string[]]$Upid,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server,

    [ValidateRange(0, [int]::MaxValue)]
    [int]$TimeoutSec = 0
  )

  begin {
    $pending = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    try {
      $connections = @(Resolve-PVEConnection -Server $Server)
    }
    catch {
      $PSCmdlet.WriteError($_)
      return
    }
    if ($connections.Count -ne 1) {
      $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
          [System.ArgumentException]::new("-Server matched $($connections.Count) connections; a task belongs to exactly one."),
          'PVEAmbiguousServer',
          [System.Management.Automation.ErrorCategory]::InvalidArgument,
          $Server))
      return
    }
    foreach ($id in $Upid) {
      $pending.Add([pscustomobject]@{ Upid = $id; Connection = $connections[0] })
    }
  }

  end {
    if ($pending.Count -eq 0) {
      return
    }

    $total = $pending.Count
    $deadline = if ($TimeoutSec -gt 0) { (Get-Date).AddSeconds($TimeoutSec) } else { $null }
    $delayMs = 500

    while ($pending.Count -gt 0) {
      foreach ($item in @($pending)) {
        try {
          $task = Get-PVETask -Upid $item.Upid -Server $item.Connection -ErrorAction Stop
        }
        catch {
          $PSCmdlet.WriteError($_)
          $null = $pending.Remove($item)
          continue
        }
        if ($task.State -ne 'Stopped') {
          continue
        }

        $null = $pending.Remove($item)
        if ($task.Succeeded) {
          if ($task.ExitStatus -ne 'OK') {
            Write-Warning "Task $($task.Type) $($task.Id) on $($task.Node) finished with $($task.ExitStatus)."
          }
          $task
        }
        else {
          $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
              [System.InvalidOperationException]::new("Task $($task.Type) $($task.Id) on $($task.Node) failed: $($task.ExitStatus)"),
              'PVETaskFailed',
              [System.Management.Automation.ErrorCategory]::OperationStopped,
              $task))
        }
      }

      if ($pending.Count -eq 0) {
        break
      }
      if ($deadline -and (Get-Date) -ge $deadline) {
        foreach ($item in $pending) {
          $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
              [System.TimeoutException]::new("Task $($item.Upid) was still running after $TimeoutSec seconds."),
              'PVETaskTimeout',
              [System.Management.Automation.ErrorCategory]::OperationTimeout,
              $item.Upid))
        }
        break
      }

      Write-Progress -Activity 'Waiting for Proxmox VE tasks' -Status "$($total - $pending.Count) of $total finished" -PercentComplete ((($total - $pending.Count) / $total) * 100)
      Start-Sleep -Milliseconds $delayMs
      $delayMs = [math]::Min($delayMs * 2, 5000)
    }

    Write-Progress -Activity 'Waiting for Proxmox VE tasks' -Completed
  }
}
