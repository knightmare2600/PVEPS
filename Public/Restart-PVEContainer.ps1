function Restart-PVEContainer {
  <#
  .SYNOPSIS
  Reboots LXC containers cleanly.
  .DESCRIPTION
  PVE shuts the container down cleanly and starts it again, applying pending configuration changes.
  LXC has no hard reset; to force a restart, use Stop-PVEContainer then Start-PVEContainer.

  Prompts for confirmation by default (ConfirmImpact High). A container that is not running is skipped
  with a warning and written unchanged.
  .PARAMETER Name
  Container name(s). Wildcards allowed.
  .PARAMETER VMId
  Container ID(s). Binds from piped PVEPS.Container objects.
  .PARAMETER TimeoutSec
  Seconds PVE waits for the shutdown half of the reboot. PVE's own default applies when omitted.
  .PARAMETER RunAsync
  Return the PVE task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Restart-PVEContainer dns01
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
    Invoke-PVEPowerAction -Cmdlet $PSCmdlet -Type lxc -Action reboot -Description 'Reboot' -Target $targets -RequiredStatus running -Parameters $parameters -RunAsync:$RunAsync
  }
}
