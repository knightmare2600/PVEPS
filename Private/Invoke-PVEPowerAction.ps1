function Invoke-PVEPowerAction {
  <#
  .SYNOPSIS
  Shared engine for every VM and container power cmdlet.
  .DESCRIPTION
  1. Resolves the collected targets (IDs or names) with Resolve-PVEGuestTarget. Unknown IDs or exact
     names and guests of the other type are reported as errors there; templates are errors here.
  2. Reads each guest's live status. A guest already in the requested state is skipped with a warning
     and written to the output unchanged, so pipelines keep flowing.
  3. Asks ShouldProcess on the calling cmdlet (so -WhatIf and -Confirm apply), then POSTs
     /nodes/{node}/{type}/{vmid}/status/{action}. Each call returns a task UPID.
  4. Complete-PVEOperation: with -RunAsync, writes the tasks. Otherwise waits for all of them together
     (Wait-PVETask), then writes each guest whose task succeeded, with its live status. Failed tasks are
     errors.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Calls ShouldProcess on the calling public cmdlet, passed as -Cmdlet, so its -WhatIf and -Confirm apply.')]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCmdlet]$Cmdlet,

    [Parameter(Mandatory)]
    [ValidateSet('qemu', 'lxc')]
    [string]$Type,

    [Parameter(Mandatory)]
    [ValidateSet('start', 'stop', 'shutdown', 'reset', 'reboot', 'suspend', 'resume')]
    [string]$Action,

    # Text for ShouldProcess and messages, for example 'Power off (hard stop)'.
    [Parameter(Mandatory)]
    [string]$Description,

    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [System.Collections.Generic.List[psobject]]$Target,

    # Status the guest must be in for the action to make sense; others are skipped with a warning.
    [Parameter(Mandatory)]
    [ValidateSet('running', 'stopped', 'any')]
    [string]$RequiredStatus,

    [hashtable]$Parameters,

    [switch]$RunAsync
  )

  $operations = [System.Collections.Generic.List[psobject]]::new()

  foreach ($guest in @(Resolve-PVEGuestTarget -Cmdlet $Cmdlet -Type $Type -Target $Target -IncludeTemplate)) {
    $label = Get-PVEGuestLabel -Guest $guest

    if ($guest.IsTemplate) {
      $Cmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
          [System.InvalidOperationException]::new("$label is a template; templates cannot be powered on or off."),
          'PVEGuestIsTemplate',
          [System.Management.Automation.ErrorCategory]::InvalidOperation,
          $guest))
      continue
    }

    try {
      $null = Update-PVEGuestStatus -Guest $guest
    }
    catch {
      $Cmdlet.WriteError($_)
      continue
    }

    if ($RequiredStatus -eq 'running' -and $guest.Status -ne 'running') {
      Write-Warning "$label is $($guest.Status); '$Description' skipped."
      $guest
      continue
    }
    if ($RequiredStatus -eq 'stopped' -and $guest.Status -eq 'running') {
      Write-Warning "$label is already running; '$Description' skipped."
      $guest
      continue
    }

    if (-not $Cmdlet.ShouldProcess($label, $Description)) {
      continue
    }

    $path = Format-PVEPath '/nodes/{node}/{type}/{vmid}/status/{action}' @{
      node   = $guest.Node
      type   = $Type
      vmid   = $guest.VMId
      action = $Action
    }
    try {
      $upid = [string](Invoke-PVERequest -Connection $guest.Connection -Method POST -Path $path -Parameters $Parameters)
    }
    catch {
      $Cmdlet.WriteError($_)
      continue
    }
    Write-Verbose "$Description $label`: task $upid"
    $operations.Add([pscustomobject]@{ Upid = $upid; Connection = $guest.Connection; Guest = $guest })
  }

  Complete-PVEOperation -Cmdlet $Cmdlet -Operation $operations -RunAsync:$RunAsync
}
