function Remove-PVEVM {
  <#
  .SYNOPSIS
  Deletes QEMU virtual machines and their disks.
  .DESCRIPTION
  Deletes each VM with DELETE /nodes/{node}/qemu/{vmid}, which PVE documents as destroying the VM and all
  the volumes it uses or owns, and removing its VM-specific permissions and firewall rules. This cannot
  be undone.

  Prompts for confirmation by default (ConfirmImpact High). A VM that is not stopped is an error and is
  left alone; stop it first. A VM with the protection flag set is refused by PVE.

  Templates are deleted when named by ID or piped in. A name or wildcard matches templates only with
  -IncludeTemplate.

  Writes nothing on success (with -RunAsync, the delete tasks).
  .PARAMETER Name
  VM name(s). Wildcards allowed.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER IncludeTemplate
  Let -Name match templates as well as VMs.
  .PARAMETER Purge
  Also remove the VM ID from backup jobs, replication jobs and HA.
  .PARAMETER DestroyUnreferencedDisks
  Also destroy disks on any enabled storage that carry the VM's ID but are not in its configuration.
  .PARAMETER RunAsync
  Return the delete task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Remove-PVEVM -VMId 105
  .EXAMPLE
  Get-PVEVM -Name 'scratch-*' | Stop-PVEVM -Confirm:$false | Remove-PVEVM -Purge -Confirm:$false
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

    [switch]$DestroyUnreferencedDisks,

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
    if ($DestroyUnreferencedDisks) {
      $parameters['destroy-unreferenced-disks'] = 1
    }
    $guests = @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets -IncludeTemplate:$IncludeTemplate)
    Invoke-PVEGuestOperation -Cmdlet $PSCmdlet -Guest $guests -Description 'Remove (delete the VM and its disks)' -Method DELETE -Parameters $parameters -RequireStopped -RunAsync:$RunAsync -NoOutput
  }
}
