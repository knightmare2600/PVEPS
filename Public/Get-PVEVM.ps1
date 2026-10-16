function Get-PVEVM {
  <#
  .SYNOPSIS
  Gets QEMU virtual machines.
  .DESCRIPTION
  Reads every VM in a single /cluster/resources call. Templates are left out unless -IncludeTemplate is
  given, as PowerCLI's Get-VM leaves templates out.

  A non-wildcard -Name, or a -VMId, that matches no VM is reported as a non-terminating "not found" error.
  .PARAMETER Name
  VM name(s). Wildcards allowed.
  .PARAMETER VMId
  VM ID(s).
  .PARAMETER Node
  Only VMs on these node(s). Wildcards allowed. Binds from piped PVEPS.Node objects.
  .PARAMETER IncludeTemplate
  Include VM templates.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection.
  .EXAMPLE
  Get-PVEVM
  .EXAMPLE
  Get-PVEVM -Name 'web*'
  .EXAMPLE
  Get-PVEVM -VMId 100, 101
  .EXAMPLE
  Get-PVENode pve01 | Get-PVEVM
  #>
  [CmdletBinding()]
  [OutputType('PVEPS.VM')]
  param(
    [Parameter(Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Name,

    [Parameter(ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(ValueFromPipelineByPropertyName)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Node,

    [switch]$IncludeTemplate,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  process {
    try {
      $connections = @(Resolve-PVEConnection -Server $Server)
    }
    catch {
      $PSCmdlet.WriteError($_)
      return
    }

    foreach ($connection in $connections) {
      try {
        Get-PVEGuest -Cmdlet $PSCmdlet -Connection $connection -Type qemu -Name $Name -VMId $VMId -Node $Node -IncludeTemplate:$IncludeTemplate
      }
      catch {
        $PSCmdlet.WriteError($_)
      }
    }
  }
}
