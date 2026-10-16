function Stop-PVEVMGuest {
  <#
  .SYNOPSIS
  Shuts down the guest operating system of QEMU virtual machines cleanly.
  .DESCRIPTION
  Sends the guest OS a shutdown request (the PVE API describes it as an ACPI event, like pressing the
  power button). The guest OS must respond; if it has not shut down when the timeout runs out, the task
  fails unless -ForceStop is given.

  Prompts for confirmation by default (ConfirmImpact High). A VM that is not running is skipped with a
  warning and written unchanged.
  .PARAMETER Name
  VM name(s). Wildcards allowed.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER TimeoutSec
  Seconds PVE waits for the guest to shut down. PVE's own default applies when omitted.
  .PARAMETER ForceStop
  Power the VM off if it has not shut down when the timeout runs out.
  .PARAMETER RunAsync
  Return the PVE task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Stop-PVEVMGuest web01
  .EXAMPLE
  Get-PVEVM -Node pve | Stop-PVEVMGuest -TimeoutSec 120 -ForceStop -Confirm:$false
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEPowerAction.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'High')]
  [OutputType('PVEPS.VM', 'PVEPS.Task')]
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
    Invoke-PVEPowerAction -Cmdlet $PSCmdlet -Type qemu -Action shutdown -Description 'Shut down guest OS' -Target $targets -RequiredStatus running -Parameters $parameters -RunAsync:$RunAsync
  }
}
