function Remove-PVEContainer {
  <#
  .SYNOPSIS
  Deletes LXC containers and their volumes.
  .DESCRIPTION
  Deletes each container with DELETE /nodes/{node}/lxc/{vmid}, which PVE documents as destroying the
  container and all the files it uses. This cannot be undone.

  Prompts for confirmation by default (ConfirmImpact High). A container that is not stopped is an error
  and is left alone; stop it first. A container with the protection flag set is refused by PVE.

  Templates are deleted when named by ID or piped in. A name or wildcard matches templates only with
  -IncludeTemplate.

  Writes nothing on success (with -RunAsync, the delete tasks).
  .PARAMETER Name
  Container name(s). Wildcards allowed.
  .PARAMETER VMId
  Container ID(s). Binds from piped PVEPS.Container objects.
  .PARAMETER IncludeTemplate
  Let -Name match templates as well as containers.
  .PARAMETER Purge
  Also remove the container from backup jobs, replication jobs and HA. PVE always removes its ACLs and
  firewall entries.
  .PARAMETER RunAsync
  Return the delete task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Remove-PVEContainer -VMId 205
  .EXAMPLE
  Get-PVEContainer -Name 'scratch-*' | Stop-PVEContainer -Confirm:$false | Remove-PVEContainer -Purge -Confirm:$false
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestOperation.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'High')]
  [OutputType('PVEPS.Task')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Name,

    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(ParameterSetName = 'Name')]
    [switch]$IncludeTemplate,

    [switch]$Purge,

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
    if ($Purge) {
      $parameters.purge = 1
    }
    $guests = @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type lxc -Target $targets -IncludeTemplate:$IncludeTemplate)
    Invoke-PVEGuestOperation -Cmdlet $PSCmdlet -Guest $guests -Description 'Remove (delete the container and its volumes)' -Method DELETE -Parameters $parameters -RequireStopped -RunAsync:$RunAsync -NoOutput
  }
}
