function Stop-PVEVM {
  <#
  .SYNOPSIS
  Powers off QEMU virtual machines immediately (hard stop).
  .DESCRIPTION
  The QEMU process exits at once, like pulling the power plug; the guest OS gets no chance to shut down
  and data not yet written can be lost. For a clean shutdown use Stop-PVEVMGuest.

  Prompts for confirmation by default (ConfirmImpact High); use -Confirm:$false in scripts. A VM that is
  not running is skipped with a warning and written unchanged.
  .PARAMETER Name
  VM name(s). Wildcards allowed.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER OverruleShutdown
  Abort a guest shutdown that is already in progress for the VM before stopping it.
  .PARAMETER RunAsync
  Return the PVE task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Stop-PVEVM web01
  .EXAMPLE
  Get-PVEVM -Name 'test*' | Stop-PVEVM -Confirm:$false
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
    Invoke-PVEPowerAction -Cmdlet $PSCmdlet -Type qemu -Action stop -Description 'Power off (hard stop)' -Target $targets -RequiredStatus running -Parameters $parameters -RunAsync:$RunAsync
  }
}
