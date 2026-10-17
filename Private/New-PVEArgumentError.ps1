function New-PVEArgumentError {
  <#
  .SYNOPSIS
  Returns an InvalidArgument ErrorRecord (error ID PVEInvalidArgument) for a cmdlet to throw or write,
  for parameter combinations the parameter attributes cannot express.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private helper; only builds an object.')]
  [CmdletBinding()]
  [OutputType([System.Management.Automation.ErrorRecord])]
  param(
    [Parameter(Mandatory)]
    [string]$Message,

    [AllowNull()]
    [object]$Target
  )

  [System.Management.Automation.ErrorRecord]::new(
    [System.ArgumentException]::new($Message),
    'PVEInvalidArgument',
    [System.Management.Automation.ErrorCategory]::InvalidArgument,
    $Target)
}
