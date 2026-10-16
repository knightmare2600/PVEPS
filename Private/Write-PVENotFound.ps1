function Write-PVENotFound {
  <#
  .SYNOPSIS
  Writes an ObjectNotFound error for each non-wildcard filter value that matched nothing.
  .DESCRIPTION
  Mirrors PowerCLI: Get-VM -Name typo writes "not found" rather than silently returning nothing, so a
  pipeline built on a mistyped name fails visibly. Wildcard patterns that match nothing are not errors.
  If a missed value matches one of -HintValue, -Hint is appended to the message.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCmdlet]$Cmdlet,

    [Parameter(Mandatory)]
    [string]$Kind,

    [AllowNull()]
    [object[]]$Filter,

    [AllowNull()]
    [object[]]$Found,

    [Parameter(Mandatory)]
    [string]$Server,

    [AllowNull()]
    [object[]]$HintValue,

    [string]$Hint
  )

  foreach ($item in $Filter) {
    $value = [string]$item
    if ([WildcardPattern]::ContainsWildcardCharacters($value)) {
      continue
    }
    if (@($Found | Where-Object { [string]$_ -like $value }).Count -gt 0) {
      continue
    }
    $message = "$Kind '$value' was not found on $Server."
    if ($Hint -and @($HintValue | Where-Object { [string]$_ -like $value }).Count -gt 0) {
      $message = '{0} {1}' -f $message, $Hint
    }
    $Cmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
        [System.Management.Automation.ItemNotFoundException]::new($message),
        'PVEObjectNotFound',
        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
        $value))
  }
}
