function Import-PVEStorageContent {
  <#
  .SYNOPSIS
  Puts an ISO image, container template or import file onto a PVE storage, from a URL or a local file.
  .DESCRIPTION
  -Url makes the node download the file itself (POST /nodes/{node}/storage/{storage}/download-url), which
  is usually fastest. -Path uploads a local file (POST .../upload, multipart). Either way the cmdlet waits
  for PVE's task, then writes the stored PVEPS.StorageContent object.

  -Checksum with -ChecksumAlgorithm makes PVE verify the file and fail the task on a mismatch. The API
  documentation warns that PVE normalises the file name; if the stored name differs, a warning says so.
  .PARAMETER Url
  URL for the node to download from.
  .PARAMETER Path
  Local file to upload.
  .PARAMETER Storage
  Target storage. It must allow the content type.
  .PARAMETER Content
  iso, vztmpl (container template) or import.
  .PARAMETER FileName
  Name to store the file under. Defaults to the last part of the URL, or the local file's name.
  .PARAMETER Checksum
  Expected checksum of the file.
  .PARAMETER ChecksumAlgorithm
  md5, sha1, sha224, sha256, sha384 or sha512.
  .PARAMETER Compression
  With -Url: decompress the download with this algorithm (for example zst or gz).
  .PARAMETER SkipCertificateCheck
  With -Url: the node does not verify the download server's TLS certificate.
  .PARAMETER Node
  Node to store the file on. Can be omitted on a single-node server.
  .PARAMETER RunAsync
  Return the task at once instead of waiting.
  .PARAMETER Server
  Connection to use. Defaults to the default connection.
  .EXAMPLE
  Import-PVEStorageContent -Url https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.1.0-amd64-netinst.iso -Storage local -Content iso
  .EXAMPLE
  Import-PVEStorageContent -Path ./virtio-win.iso -Storage local -Content iso -Checksum $sha256 -ChecksumAlgorithm sha256
  #>
  [CmdletBinding(DefaultParameterSetName = 'Url', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.StorageContent', 'PVEPS.Task')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Url', Position = 0)]
    [ValidatePattern('^(https?|ftp)://')]
    [string]$Url,

    [Parameter(Mandatory, ParameterSetName = 'Path')]
    [ValidateNotNullOrEmpty()]
    [string]$Path,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Storage,

    [Parameter(Mandatory)]
    [ValidateSet('iso', 'vztmpl', 'import')]
    [string]$Content,

    [ValidateLength(1, 255)]
    [string]$FileName,

    [ValidateNotNullOrEmpty()]
    [string]$Checksum,

    [ValidateSet('md5', 'sha1', 'sha224', 'sha256', 'sha384', 'sha512')]
    [string]$ChecksumAlgorithm,

    [Parameter(ParameterSetName = 'Url')]
    [ValidateNotNullOrEmpty()]
    [string]$Compression,

    [Parameter(ParameterSetName = 'Url')]
    [switch]$SkipCertificateCheck,

    [ValidateNotNullOrEmpty()]
    [string]$Node,

    [switch]$RunAsync,

    [Alias('Connection')]
    [object]$Server
  )

  if ([bool]$Checksum -ne [bool]$ChecksumAlgorithm) {
    $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message '-Checksum and -ChecksumAlgorithm go together.' -Target $Checksum))
  }
  if ($Path) {
    $localPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
      $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
          [System.IO.FileNotFoundException]::new("Local file '$Path' was not found.", $localPath),
          'PVELocalFileNotFound',
          [System.Management.Automation.ErrorCategory]::ObjectNotFound,
          $Path))
    }
  }
  $name = if ($FileName) {
    $FileName
  }
  elseif ($Path) {
    Split-Path -Path $localPath -Leaf
  }
  else {
    [uri]::UnescapeDataString(([uri]$Url).Segments[-1])
  }
  if (-not $name -or $name -eq '/') {
    $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message "No file name in '$Url'; give -FileName." -Target $Url))
  }

  try {
    $connection = Resolve-PVESingleConnection -Server $Server -Reason 'a file is stored on exactly one'
    $nodeName = Resolve-PVENodeName -Connection $connection -Node $Node
  }
  catch {
    $PSCmdlet.WriteError($_)
    return
  }

  $source = if ($Path) { "local file $localPath" } else { $Url }
  if (-not $PSCmdlet.ShouldProcess("$Storage on $nodeName", "Store $source as $Content/$name")) {
    return
  }

  try {
    if ($Path) {
      $form = [ordered]@{ content = $Content }
      if ($Checksum) {
        $form.checksum = $Checksum
        $form['checksum-algorithm'] = $ChecksumAlgorithm
      }
      $form.filename = @{ Path = $localPath; FileName = $name }
      $apiPath = Format-PVEPath '/nodes/{node}/storage/{storage}/upload' @{ node = $nodeName; storage = $Storage }
      $upid = [string](Invoke-PVERequest -Connection $connection -Method POST -Path $apiPath -Form $form)
    }
    else {
      $body = @{ url = $Url; content = $Content; filename = $name }
      if ($Checksum) {
        $body.checksum = $Checksum
        $body['checksum-algorithm'] = $ChecksumAlgorithm
      }
      if ($Compression) {
        $body.compression = $Compression
      }
      if ($SkipCertificateCheck) {
        $body['verify-certificates'] = 0
      }
      $apiPath = Format-PVEPath '/nodes/{node}/storage/{storage}/download-url' @{ node = $nodeName; storage = $Storage }
      $upid = [string](Invoke-PVERequest -Connection $connection -Method POST -Path $apiPath -Parameters $body)
    }
  }
  catch {
    $PSCmdlet.WriteError($_)
    return
  }

  $operations = [System.Collections.Generic.List[psobject]]::new()
  $operations.Add([pscustomobject]@{ Upid = $upid; Connection = $connection })
  if ($RunAsync -and $upid -match '^UPID:') {
    Get-PVETask -Upid $upid -Server $connection
    return
  }
  if (@(Wait-PVEOperation -Operation $operations).Count -eq 0) {
    return
  }
  try {
    Find-PVEStoredFile -Connection $connection -Node $nodeName -Storage $Storage -Content $Content -FileName $name
  }
  catch {
    $PSCmdlet.WriteError($_)
  }
}
