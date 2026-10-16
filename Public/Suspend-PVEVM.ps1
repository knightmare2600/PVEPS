function Suspend-PVEVM {
  <#
  .SYNOPSIS
  Suspends (pauses) QEMU virtual machines, or hibernates them to disk.
  .DESCRIPTION
  Without -ToDisk, the VM is paused in memory; resume it with Resume-PVEVM. PVE still reports a paused VM
  with Status 'running', because the QEMU process is still running.

  With -ToDisk, the VM's memory is saved to a state volume and the VM stops (Status 'stopped', Lock
  'suspended'); resume it with Start-PVEVM. This needs VM.Config.Disk on the VM and
  Datastore.AllocateSpace on the state storage, as well as VM.PowerMgmt.

  Prompts for confirmation by default (ConfirmImpact High). A VM that is not running is skipped with a
  warning and written unchanged.
  .PARAMETER Name
  VM name(s). Wildcards allowed.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER ToDisk
  Hibernate: save memory to disk and stop the VM.
  .PARAMETER StateStorage
  Storage for the saved memory state (with -ToDisk). PVE chooses when omitted.
  .PARAMETER RunAsync
  Return the PVE task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Suspend-PVEVM web01
  .EXAMPLE
  Suspend-PVEVM web01 -ToDisk -StateStorage local-lvm
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

    [switch]$ToDisk,

    [ValidateNotNullOrEmpty()]
    [string]$StateStorage,

    [switch]$RunAsync,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    if ($StateStorage -and -not $ToDisk) {
      $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
          [System.ArgumentException]::new('-StateStorage only applies with -ToDisk.'),
          'PVEStateStorageWithoutToDisk',
          [System.Management.Automation.ErrorCategory]::InvalidArgument,
          $StateStorage))
    }
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $Name
  }

  end {
    $parameters = @{}
    if ($ToDisk) {
      $parameters.todisk = $true
    }
    if ($StateStorage) {
      $parameters.statestorage = $StateStorage
    }
    $description = if ($ToDisk) { 'Suspend to disk (hibernate)' } else { 'Suspend (pause)' }
    Invoke-PVEPowerAction -Cmdlet $PSCmdlet -Type qemu -Action suspend -Description $description -Target $targets -RequiredStatus running -Parameters $parameters -RunAsync:$RunAsync
  }
}
