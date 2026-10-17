function Resolve-PVESingleConnection {
  <#
  .SYNOPSIS
  Resolves -Server to exactly one connection, for operations that belong to one server (creating a guest,
  waiting for a task given as a plain UPID). Throws if it matches none or several.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [AllowNull()]
    [object[]]$Server,

    # Ends the error message, for example 'a task belongs to exactly one'.
    [Parameter(Mandatory)]
    [string]$Reason
  )

  $connections = @(Resolve-PVEConnection -Server $Server)
  if ($connections.Count -ne 1) {
    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
        [System.ArgumentException]::new("-Server matched $($connections.Count) connections; $Reason."),
        'PVEAmbiguousServer',
        [System.Management.Automation.ErrorCategory]::InvalidArgument,
        $Server))
  }
  $connections[0]
}
