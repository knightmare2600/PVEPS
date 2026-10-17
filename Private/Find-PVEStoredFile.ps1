function Find-PVEStoredFile {
  <#
  .SYNOPSIS
  After an upload or download, finds the stored file by name in a storage's content of one type, and
  warns if it is not there.
  .DESCRIPTION
  The API documentation warns that PVE normalises the file name given, so the stored name can differ.
  The file is looked for as <storage>:<content>/<name>; if that is missing, a warning says to look it up
  with Get-PVEStorageContent.
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

    [Parameter(Mandatory)]
    [string]$Content,

    [Parameter(Mandatory)]
    [string]$FileName
  )

  $expected = '{0}:{1}/{2}' -f $Storage, $Content, $FileName
  $item = Get-PVEStorageItem -Connection $Connection -Node $Node -Storage $Storage -Content $Content | Where-Object { $_.Volume -eq $expected }
  if ($item) {
    return $item
  }
  Write-Warning "The task succeeded but $expected is not listed; PVE normalises file names, so look for it with Get-PVEStorageContent -Storage $Storage -Content $Content."
}
