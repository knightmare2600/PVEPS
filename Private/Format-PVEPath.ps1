function Format-PVEPath {
  <#
  .SYNOPSIS
  Expands an API path template such as '/nodes/{node}/tasks/{upid}/status', URL-escaping each value.
  .DESCRIPTION
  Templates use the same placeholder names as the Proxmox VE API schema (apidoc.js), so a path in the
  code can be compared directly against the API viewer.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)]
    [string]$Template,

    [hashtable]$Values = @{}
  )

  $result = $Template
  foreach ($key in $Values.Keys) {
    $value = [string]$Values[$key]
    if ([string]::IsNullOrEmpty($value)) {
      throw "Path template '$Template': value for '{$key}' is empty."
    }
    $result = $result.Replace("{$key}", [uri]::EscapeDataString($value))
  }

  if ($result -match '\{[^}]+\}') {
    throw "Path template '$Template': no value supplied for '$($Matches[0])'."
  }
  $result
}
