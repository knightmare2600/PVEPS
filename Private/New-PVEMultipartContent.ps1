function New-PVEMultipartContent {
  <#
  .SYNOPSIS
  Builds a multipart/form-data body for an upload, in the field order given.
  .DESCRIPTION
  A value that is a hashtable with Path (and optionally FileName) becomes a file part streamed from Path
  under that file name; a FileInfo becomes a file part under its own name; anything else becomes a text
  part. Field and file names are quoted, as browsers send them. The caller disposes the result, which
  closes the file streams.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private helper; only builds an object.')]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '', Justification = 'Returned with the unary comma because MultipartFormDataContent is enumerable and would otherwise be unrolled into its parts.')]
  [CmdletBinding()]
  [OutputType([System.Net.Http.MultipartFormDataContent], [object[]])]
  param(
    [Parameter(Mandatory)]
    [System.Collections.IDictionary]$Form
  )

  $multipart = [System.Net.Http.MultipartFormDataContent]::new()
  try {
    foreach ($key in $Form.Keys) {
      $value = $Form[$key]
      $filePath = $null
      $fileName = $null
      if ($value -is [System.IO.FileInfo]) {
        $filePath = $value.FullName
        $fileName = $value.Name
      }
      elseif ($value -is [System.Collections.IDictionary] -and $value.Contains('Path')) {
        $filePath = [string]$value['Path']
        $fileName = if ($value['FileName']) { [string]$value['FileName'] } else { Split-Path -Path $filePath -Leaf }
      }

      if ($filePath) {
        $part = [System.Net.Http.StreamContent]::new([System.IO.File]::OpenRead($filePath))
        $part.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream')
        $disposition = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new('form-data')
        $disposition.Name = '"{0}"' -f $key
        $disposition.FileName = '"{0}"' -f $fileName
        $part.Headers.ContentDisposition = $disposition
      }
      else {
        $part = [System.Net.Http.StringContent]::new([string]$value)
        $part.Headers.ContentType = $null
        $disposition = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new('form-data')
        $disposition.Name = '"{0}"' -f $key
        $part.Headers.ContentDisposition = $disposition
      }
      $multipart.Add($part)
    }
  }
  catch {
    $multipart.Dispose()
    throw
  }
  , $multipart
}
