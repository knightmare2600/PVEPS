function ConvertFrom-PVESecureString {
  <#
  .SYNOPSIS
  Returns the plain text of a SecureString. Cross-platform (does not rely on DPAPI or Marshal BSTR).
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)]
    [securestring]$SecureString
  )

  [System.Net.NetworkCredential]::new('', $SecureString).Password
}
