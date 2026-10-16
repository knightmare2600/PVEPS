function Start-PVEContainer {
  <#
  .SYNOPSIS
  Starts LXC containers.
  .DESCRIPTION
  Starts each container and, unless -RunAsync is given, waits for the start task to finish and writes the
  container with its live status. A container that is already running is skipped with a warning and
  written unchanged.
  .PARAMETER Name
  Container name(s). Wildcards allowed.
  .PARAMETER VMId
  Container ID(s). Binds from piped PVEPS.Container objects.
  .PARAMETER RunAsync
  Return the PVE task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Start-PVEContainer dns01
  .EXAMPLE
  Get-PVEContainer | Where-Object Status -EQ 'stopped' | Start-PVEContainer
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEPowerAction.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
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
    Invoke-PVEPowerAction -Cmdlet $PSCmdlet -Type lxc -Action start -Description 'Start' -Target $targets -RequiredStatus stopped -RunAsync:$RunAsync
  }
}
