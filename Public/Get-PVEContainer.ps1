function Get-PVEContainer {
  <#
  .SYNOPSIS
  Gets LXC containers.
  .DESCRIPTION
  Reads every container in a single /cluster/resources call. Templates are left out unless
  -IncludeTemplate is given.

  A non-wildcard -Name, or a -VMId, that matches no container is reported as a non-terminating "not found"
  error.
  .PARAMETER Name
  Container name(s) (host names). Wildcards allowed.
  .PARAMETER VMId
  Container ID(s).
  .PARAMETER Node
  Only containers on these node(s). Wildcards allowed. Binds from piped PVEPS.Node objects.
  .PARAMETER IncludeTemplate
  Include container templates.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection.
  .EXAMPLE
  Get-PVEContainer
  .EXAMPLE
  Get-PVEContainer -Name 'dns*' | Where-Object Status -EQ 'running'
  #>
  [CmdletBinding()]
  [OutputType('PVEPS.Container')]
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
        Get-PVEGuest -Cmdlet $PSCmdlet -Connection $connection -Type lxc -Name $Name -VMId $VMId -Node $Node -IncludeTemplate:$IncludeTemplate
      }
      catch {
        $PSCmdlet.WriteError($_)
      }
    }
  }
}
