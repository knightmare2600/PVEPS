function Invoke-PVEVMScript {
  <#
  .SYNOPSIS
  Runs a command inside running VMs through the QEMU guest agent and returns its output.
  .DESCRIPTION
  Starts the command with POST /nodes/{node}/qemu/{vmid}/agent/exec on every VM, then polls
  GET .../agent/exec-status for each until it exits or -TimeoutSec runs out. Writes one
  PVEPS.VMScriptResult per VM with the exit code, standard output and standard error. A non-zero exit
  code is a result, not an error. A command still running at the timeout is an error
  (PVEGuestCommandTimeout); it keeps running in the guest.

  -Command runs a program directly with the given arguments. -ScriptText runs text through an
  interpreter chosen by -ScriptType:
  - Bash: /bin/bash -c <text>      - Sh: /bin/sh -c <text>
  - PowerShell: powershell.exe -NoProfile -NonInteractive -Command <text>
  - Pwsh: pwsh -NoProfile -NonInteractive -Command <text>
  - Cmd: cmd.exe /c <text>

  The VM must be running, with the agent installed and running in the guest. The API documentation
  requires the VM.GuestAgent.Unrestricted privilege for exec.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER Command
  Program and arguments, one per element, for example 'ls', '-l', '/etc'.
  .PARAMETER ScriptText
  Script text to run through the -ScriptType interpreter.
  .PARAMETER ScriptType
  Bash (the default), Sh, PowerShell, Pwsh or Cmd.
  .PARAMETER InputData
  Text passed to the command as standard input.
  .PARAMETER TimeoutSec
  Seconds to wait for the command to exit. Defaults to 300.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Invoke-PVEVMScript -VMId 100 -ScriptText 'uptime; df -h /'
  .EXAMPLE
  Get-PVEVM 'web*' | Invoke-PVEVMScript -Command systemctl, is-active, nginx | Select-Object VMName, ExitCode, StdOut
  .EXAMPLE
  Invoke-PVEVMScript -VMName win01 -ScriptType PowerShell -ScriptText 'Get-Service W32Time'
  #>
  [CmdletBinding(DefaultParameterSetName = 'IdScript', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.VMScriptResult')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'IdScript', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory, ParameterSetName = 'IdCommand', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'NameScript', Position = 0)]
    [Parameter(Mandatory, ParameterSetName = 'NameCommand', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [Parameter(Mandatory, ParameterSetName = 'IdCommand')]
    [Parameter(Mandatory, ParameterSetName = 'NameCommand')]
    [ValidateNotNullOrEmpty()]
    [string[]]$Command,

    [Parameter(Mandatory, ParameterSetName = 'IdScript')]
    [Parameter(Mandatory, ParameterSetName = 'NameScript')]
    [ValidateNotNullOrEmpty()]
    [string]$ScriptText,

    [Parameter(ParameterSetName = 'IdScript')]
    [Parameter(ParameterSetName = 'NameScript')]
    [ValidateSet('Bash', 'Sh', 'PowerShell', 'Pwsh', 'Cmd')]
    [string]$ScriptType = 'Bash',

    [string]$InputData,

    [ValidateRange(1, [int]::MaxValue)]
    [int]$TimeoutSec = 300,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $argv = if ($Command) {
      $Command
    }
    else {
      switch ($ScriptType) {
        'Bash' { '/bin/bash', '-c', $ScriptText }
        'Sh' { '/bin/sh', '-c', $ScriptText }
        'PowerShell' { 'powershell.exe', '-NoProfile', '-NonInteractive', '-Command', $ScriptText }
        'Pwsh' { 'pwsh', '-NoProfile', '-NonInteractive', '-Command', $ScriptText }
        'Cmd' { 'cmd.exe', '/c', $ScriptText }
      }
    }
    $argv = [string[]]@($argv)
    $body = @{ command = $argv }
    if ($PSBoundParameters.ContainsKey('InputData')) {
      $body['input-data'] = $InputData
    }
    $shown = if ($Command) { $Command -join ' ' } else { "$ScriptType script" }
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName
  }

  end {
    $running = [System.Collections.Generic.List[psobject]]::new()
    foreach ($guest in @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets)) {
      $label = Get-PVEGuestLabel -Guest $guest
      try {
        $null = Update-PVEGuestStatus -Guest $guest
      }
      catch {
        $PSCmdlet.WriteError($_)
        continue
      }
      if ($guest.Status -ne 'running') {
        $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new("$label is $($guest.Status); the guest agent only runs in a running VM."),
            'PVEGuestNotRunning',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $guest))
        continue
      }
      if (-not $PSCmdlet.ShouldProcess($label, "Run in the guest: $shown")) {
        continue
      }
      try {
        $started = Invoke-PVEAgentRequest -Guest $guest -Command exec -Method POST -Parameters $body
      }
      catch {
        $PSCmdlet.WriteError($_)
        continue
      }
      $processId = Get-PVEValue $started 'pid'
      Write-Verbose "$label`: started $shown as guest PID $processId"
      $running.Add([pscustomobject]@{ Guest = $guest; ProcessId = $processId })
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $delayMs = 250
    while ($running.Count -gt 0) {
      foreach ($item in @($running)) {
        try {
          $status = Invoke-PVEAgentRequest -Guest $item.Guest -Command exec-status -Parameters @{ pid = $item.ProcessId }
        }
        catch {
          $PSCmdlet.WriteError($_)
          $null = $running.Remove($item)
          continue
        }
        if (-not [bool][int](Get-PVEValue $status 'exited')) {
          continue
        }
        $null = $running.Remove($item)
        [pscustomobject]@{
          PSTypeName   = 'PVEPS.VMScriptResult'
          VMId         = $item.Guest.VMId
          VMName       = $item.Guest.Name
          Node         = $item.Guest.Node
          Command      = $argv
          ExitCode     = Get-PVEValue $status 'exitcode'
          Signal       = Get-PVEValue $status 'signal'
          StdOut       = [string](Get-PVEValue $status 'out-data')
          StdErr       = [string](Get-PVEValue $status 'err-data')
          OutTruncated = [bool][int](Get-PVEValue $status 'out-truncated')
          ErrTruncated = [bool][int](Get-PVEValue $status 'err-truncated')
          Connection   = $item.Guest.Connection
        }
      }
      if ($running.Count -eq 0) {
        break
      }
      if ((Get-Date) -ge $deadline) {
        foreach ($item in $running) {
          $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
              [System.TimeoutException]::new("$(Get-PVEGuestLabel -Guest $item.Guest): $shown (guest PID $($item.ProcessId)) was still running after $TimeoutSec seconds; it keeps running in the guest."),
              'PVEGuestCommandTimeout',
              [System.Management.Automation.ErrorCategory]::OperationTimeout,
              $item.Guest))
        }
        break
      }
      Start-Sleep -Milliseconds $delayMs
      $delayMs = [math]::Min($delayMs * 2, 2000)
    }
  }
}
