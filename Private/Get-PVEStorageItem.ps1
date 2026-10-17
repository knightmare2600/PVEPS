function Get-PVEStorageItem {
  <#
  .SYNOPSIS
  Lists one storage's content on one node as PVEPS.StorageContent objects, newest first.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [psobject]$Connection,

    [Parameter(Mandatory)]
    [string]$Node,

    [Parameter(Mandatory)]
    [string]$Storage,

    [string]$Content,

    [int]$VMId
  )

  $parameters = @{}
  if ($Content) {
    $parameters.content = $Content
  }
  if ($VMId) {
    $parameters.vmid = $VMId
  }
  $path = Format-PVEPath '/nodes/{node}/storage/{storage}/content' @{ node = $Node; storage = $Storage }
  Invoke-PVERequest -Connection $Connection -Path $path -Parameters $parameters |
    ForEach-Object { ConvertTo-PVEStorageContent -InputObject $_ -Storage $Storage -Node $Node -Content $Content -Connection $Connection } |
    Sort-Object -Property @{ Expression = { if ($_.Created) { $_.Created } else { [datetime]::MinValue } }; Descending = $true }, Volume
}
