function ConvertTo-PVEVMTemplate {
  <#
  .SYNOPSIS
  Converts VMs into templates.
  .DESCRIPTION
  Converts each VM with POST /nodes/{node}/qemu/{vmid}/template and writes it with its live status
  (IsTemplate true). A template cannot be started; Copy-PVEVM makes new VMs from it. Treat the
  conversion as one-way: this module has no cmdlet that turns a template back into a VM.

  Prompts for confirmation by default (ConfirmImpact High). A VM that is not stopped is an error and is
  left alone; stop it first. One that is already a template is skipped with a warning and written
  unchanged.
  .PARAMETER Name
  VM name(s). Wildcards allowed.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER RunAsync
  Return the task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  ConvertTo-PVEVMTemplate -VMId 9000
  .EXAMPLE
  Get-PVEVM -Name 'golden-*' | Stop-PVEVMGuest -Confirm:$false | ConvertTo-PVEVMTemplate -Confirm:$false
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestOperation.')]
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
    $guests = @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets -IncludeTemplate)
    Invoke-PVEGuestOperation -Cmdlet $PSCmdlet -Guest $guests -Description 'Convert to template' -Method POST -Suffix '/template' -SkipTemplate -RequireStopped -RunAsync:$RunAsync
  }
}
