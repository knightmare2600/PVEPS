function ConvertTo-PVEContainerTemplate {
  <#
  .SYNOPSIS
  Converts containers into templates.
  .DESCRIPTION
  Converts each container with POST /nodes/{node}/lxc/{vmid}/template and writes it with its live status
  (IsTemplate true). A template cannot be started; Copy-PVEContainer makes new containers from it. Treat the
  conversion as one-way: this module has no cmdlet that turns a template back into a container.

  Prompts for confirmation by default (ConfirmImpact High). A container that is not stopped is an error and is
  left alone; stop it first. One that is already a template is skipped with a warning and written
  unchanged.
  .PARAMETER Name
  Container name(s). Wildcards allowed.
  .PARAMETER VMId
  Container ID(s). Binds from piped PVEPS.Container objects.
  .PARAMETER RunAsync
  Return the task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  ConvertTo-PVEContainerTemplate -VMId 9100
  .EXAMPLE
  Get-PVEContainer -Name 'golden-*' | Stop-PVEContainerGuest -Confirm:$false | ConvertTo-PVEContainerTemplate -Confirm:$false
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestOperation.')]
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
    $guests = @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type lxc -Target $targets -IncludeTemplate)
    Invoke-PVEGuestOperation -Cmdlet $PSCmdlet -Guest $guests -Description 'Convert to template' -Method POST -Suffix '/template' -SkipTemplate -RequireStopped -RunAsync:$RunAsync
  }
}
