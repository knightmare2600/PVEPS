function Get-PVEGuestConfig {
  <#
  .SYNOPSIS
  Reads a guest's configuration with GET /nodes/{node}/{type}/{vmid}/config.
  .DESCRIPTION
  PVE returns the configuration with pending changes applied (the API documentation: "Set the 'current'
  parameter to get the current configuration instead"), plus a digest of the configuration file. Changes
  built from this configuration send the digest back, so PVE refuses them if the file changed in between.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [psobject]$Guest
  )

  $path = Format-PVEPath '/nodes/{node}/{type}/{vmid}/config' @{ node = $Guest.Node; type = $Guest.Type; vmid = $Guest.VMId }
  Invoke-PVERequest -Connection $Guest.Connection -Path $path
}
