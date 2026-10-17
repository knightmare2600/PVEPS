function Complete-PVEOperation {
  <#
  .SYNOPSIS
  Finishes the operations a cmdlet started: waits for their tasks together and writes the results.
  .DESCRIPTION
  Each operation is an object with:
    Upid        the task UPID the API returned, or $null for endpoints that finish synchronously (and for
                POST .../config when PVE finished the change before replying)
    Connection  the connection the operation ran on
    Guest       the guest object to refresh and write, or $null to read it with Get-PVEGuestById
    Type, Node, VMId, Pool   used when Guest is $null

  Without -RunAsync, waits for every task (Wait-PVETask; failures are errors there) and writes each
  successful operation's guest with its live status. With -RunAsync, writes the task of each operation
  that has one, and the guest of each that finished synchronously. -NoOutput writes nothing for
  successful operations (used by the Remove cmdlets).
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCmdlet]$Cmdlet,

    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [System.Collections.Generic.List[psobject]]$Operation,

    [switch]$RunAsync,

    [switch]$NoOutput
  )

  if ($Operation.Count -eq 0) {
    return
  }

  $writeGuest = {
    param($op)
    try {
      if ($op.Guest) {
        Update-PVEGuestStatus -Guest $op.Guest
      }
      else {
        Get-PVEGuestById -Connection $op.Connection -Type $op.Type -Node $op.Node -VMId $op.VMId -Pool $op.Pool
      }
    }
    catch {
      $Cmdlet.WriteError($_)
    }
  }

  if ($RunAsync) {
    foreach ($op in $Operation) {
      if ($op.Upid -match '^UPID:') {
        try {
          Get-PVETask -Upid $op.Upid -Server $op.Connection -ErrorAction Stop
        }
        catch {
          $Cmdlet.WriteError($_)
        }
      }
      elseif (-not $NoOutput) {
        & $writeGuest $op
      }
    }
    return
  }

  foreach ($op in @(Wait-PVEOperation -Operation $Operation)) {
    if (-not $NoOutput) {
      & $writeGuest $op
    }
  }
}
