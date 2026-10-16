function Stop-PVEContainer {
  <#
  .SYNOPSIS
  Stops LXC containers immediately (hard stop).
  .DESCRIPTION
  Every process in the container is stopped abruptly. For a clean shutdown use Stop-PVEContainerGuest.

  Prompts for confirmation by default (ConfirmImpact High). A container that is not running is skipped
  with a warning and written unchanged.
  .PARAMETER Name
  Container name(s). Wildcards allowed.
  .PARAMETER VMId
  Container ID(s). Binds from piped PVEPS.Container objects.
  .PARAMETER OverruleShutdown
  Abort a shutdown that is already in progress for the container before stopping it.
  .PARAMETER RunAsync
  Return the PVE task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Stop-PVEContainer dns01 -Confirm:$false
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

    [switch]$OverruleShutdown,

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
    if ($OverruleShutdown) {
      $parameters['overrule-shutdown'] = $true
    }
    Invoke-PVEPowerAction -Cmdlet $PSCmdlet -Type lxc -Action stop -Description 'Stop (hard stop)' -Target $targets -RequiredStatus running -Parameters $parameters -RunAsync:$RunAsync
  }
}
