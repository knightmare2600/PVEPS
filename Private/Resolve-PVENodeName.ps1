function Resolve-PVENodeName {
  <#
  .SYNOPSIS
  Returns -Node if given; otherwise the name of the server's only node. Throws if the server has several
  nodes, since the caller then has to choose.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)]
    [psobject]$Connection,

    [string]$Node
  )

  if ($Node) {
    return $Node
  }
  $names = @(Invoke-PVERequest -Connection $Connection -Path '/nodes' | ForEach-Object { [string](Get-PVEValue $_ 'node') })
  if ($names.Count -ne 1) {
    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
        [System.ArgumentException]::new("$($Connection.Server) has $($names.Count) nodes ($($names -join ', ')); specify -Node."),
        'PVENodeRequired',
        [System.Management.Automation.ErrorCategory]::InvalidArgument,
        $Connection))
  }
  $names[0]
}
