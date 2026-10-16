function Stop-PVEContainerGuest {
  <#
  .SYNOPSIS
  Shuts down LXC containers cleanly.
  .DESCRIPTION
  Asks the container's init system to shut down (see lxc-stop(1)). If the container has not stopped when
  the timeout runs out, the task fails unless -ForceStop is given.

  Prompts for confirmation by default (ConfirmImpact High). A container that is not running is skipped
  with a warning and written unchanged.
  .PARAMETER Name
  Container name(s). Wildcards allowed.
  .PARAMETER VMId
  Container ID(s). Binds from piped PVEPS.Container objects.
  .PARAMETER TimeoutSec
  Seconds PVE waits for the shutdown. PVE's own default applies when omitted.
  .PARAMETER ForceStop
  Stop the container if it has not shut down when the timeout runs out.
  .PARAMETER RunAsync
  Return the PVE task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Stop-PVEContainerGuest dns01
  .EXAMPLE
  Get-PVEContainer | Stop-PVEContainerGuest -TimeoutSec 60 -ForceStop -Confirm:$false
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEPowerAction.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'High')]
  [OutputType('PVEPS.Container', 'PVEPS.Task')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Name,

    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [ValidateRange(1, [int]::MaxValue)]
    [int]$TimeoutSec,

    [switch]$ForceStop,

    [switch]$RunAsync,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $Name
  }

  end {
    $parameters = @{}
    if ($PSBoundParameters.ContainsKey('TimeoutSec')) {
      $parameters.timeout = $TimeoutSec
    }
    if ($ForceStop) {
      $parameters.forceStop = $true
    }
    Invoke-PVEPowerAction -Cmdlet $PSCmdlet -Type lxc -Action shutdown -Description 'Shut down' -Target $targets -RequiredStatus running -Parameters $parameters -RunAsync:$RunAsync
  }
}
