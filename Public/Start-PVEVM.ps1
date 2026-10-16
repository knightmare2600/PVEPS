function Start-PVEVM {
  <#
  .SYNOPSIS
  Starts QEMU virtual machines.
  .DESCRIPTION
  Starts each VM and, unless -RunAsync is given, waits for the start task to finish and writes the VM
  with its live status. A VM that is already running is skipped with a warning and written unchanged.
  Also resumes a VM that was suspended to disk with Suspend-PVEVM -ToDisk.
  .PARAMETER Name
  VM name(s). Wildcards allowed.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER RunAsync
  Return the PVE task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Start-PVEVM web01
  .EXAMPLE
  Get-PVEVM -Name 'web*' | Start-PVEVM
  .EXAMPLE
  Start-PVEVM -VMId 100, 101 -RunAsync | Wait-PVETask
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEPowerAction.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.VM', 'PVEPS.Task')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Name,

    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

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
    Invoke-PVEPowerAction -Cmdlet $PSCmdlet -Type qemu -Action start -Description 'Start' -Target $targets -RequiredStatus stopped -RunAsync:$RunAsync
  }
}
