function Invoke-PVEAgentRequest {
  <#
  .SYNOPSIS
  Calls one QEMU guest agent endpoint, /nodes/{node}/qemu/{vmid}/agent/<Command>, and returns its data.
  .DESCRIPTION
  Most agent endpoints return an object with a single 'result' property (the API documentation's wording);
  that result is returned. Endpoints whose data has no 'result' (exec, exec-status, file-read) are
  returned as they are. The shapes inside 'result' are defined by the QEMU guest agent protocol, not by
  PVE.
  #>
  [CmdletBinding()]
  [OutputType([object], [object[]])]
  param(
    [Parameter(Mandatory)]
    [psobject]$Guest,

    [Parameter(Mandatory)]
    [string]$Command,

    [ValidateSet('GET', 'POST')]
    [string]$Method = 'GET',

    [hashtable]$Parameters
  )

  $path = (Format-PVEPath '/nodes/{node}/qemu/{vmid}/agent' @{ node = $Guest.Node; vmid = $Guest.VMId }) + "/$Command"
  $data = Invoke-PVERequest -Connection $Guest.Connection -Method $Method -Path $path -Parameters $Parameters
  $result = Get-PVEValue $data 'result'
  if ($null -ne $result) {
    return , $result
  }
  $data
}
