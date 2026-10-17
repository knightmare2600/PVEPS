function Copy-PVEVMGuestFile {
  <#
  .SYNOPSIS
  Copies a file between this computer and a VM, through the QEMU guest agent.
  .DESCRIPTION
  -LocalToGuest writes the local file into each VM with POST /nodes/{node}/qemu/{vmid}/agent/file-write.
  The API limits the content to 61440 characters; the file is sent base64-encoded (so any bytes copy
  unchanged), which limits it to 46080 bytes. A larger file is an error and nothing is sent. The guest
  file is replaced if it exists. Writes nothing.

  -GuestToLocal reads the guest file with GET .../agent/file-read, in chunks (the API limits one read to
  16777216 bytes), and writes it to -Destination. Exactly one VM. An existing local file is an error
  unless -Force is given. Writes the local file's FileInfo.

  The VM must be running, with the agent running in the guest. The API documentation requires
  VM.GuestAgent.FileWrite or FileRead (or Unrestricted).
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER Source
  The file to copy: a local path with -LocalToGuest, a guest path with -GuestToLocal.
  .PARAMETER Destination
  Where to put it: a guest path with -LocalToGuest, a local path with -GuestToLocal.
  .PARAMETER LocalToGuest
  Copy from this computer into the VM.
  .PARAMETER GuestToLocal
  Copy from the VM to this computer.
  .PARAMETER Force
  With -GuestToLocal, replace an existing local file.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Copy-PVEVMGuestFile -VMId 100 -LocalToGuest -Source ./motd -Destination /etc/motd
  .EXAMPLE
  Copy-PVEVMGuestFile -VMId 100 -GuestToLocal -Source /var/log/syslog -Destination ./syslog-web01.txt
  #>
  [CmdletBinding(DefaultParameterSetName = 'IdToGuest', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType([System.IO.FileInfo])]
  param(
    [Parameter(Mandatory, ParameterSetName = 'IdToGuest', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory, ParameterSetName = 'IdToLocal', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'NameToGuest', Position = 0)]
    [Parameter(Mandatory, ParameterSetName = 'NameToLocal', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Source,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Destination,

    [Parameter(Mandatory, ParameterSetName = 'IdToGuest')]
    [Parameter(Mandatory, ParameterSetName = 'NameToGuest')]
    [switch]$LocalToGuest,

    [Parameter(Mandatory, ParameterSetName = 'IdToLocal')]
    [Parameter(Mandatory, ParameterSetName = 'NameToLocal')]
    [switch]$GuestToLocal,

    [Parameter(ParameterSetName = 'IdToLocal')]
    [Parameter(ParameterSetName = 'NameToLocal')]
    [switch]$Force,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $maxWriteBytes = 46080
    $chunkBytes = 4MB
    if ($LocalToGuest) {
      $localPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Source)
      if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.IO.FileNotFoundException]::new("Local file '$Source' was not found.", $localPath),
            'PVELocalFileNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $Source))
      }
      $bytes = [System.IO.File]::ReadAllBytes($localPath)
      if ($bytes.Length -gt $maxWriteBytes) {
        $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message "'$Source' is $($bytes.Length) bytes; the guest agent file-write call takes at most $maxWriteBytes bytes (61440 base64 characters)." -Target $Source))
      }
      $content = [Convert]::ToBase64String($bytes)
    }
    else {
      $localPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Destination)
      if ((Test-Path -LiteralPath $localPath) -and -not $Force) {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.IO.IOException]::new("Local file '$Destination' exists; add -Force to replace it."),
            'PVELocalFileExists',
            [System.Management.Automation.ErrorCategory]::ResourceExists,
            $Destination))
      }
    }
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName
  }

  end {
    $guests = @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets)
    if ($GuestToLocal -and $guests.Count -gt 1) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message "-GuestToLocal copies from exactly one VM; $($guests.Count) are targeted." -Target $guests))
    }

    foreach ($guest in $guests) {
      $label = Get-PVEGuestLabel -Guest $guest
      if ($LocalToGuest) {
        if (-not $PSCmdlet.ShouldProcess($label, "Write $($bytes.Length) bytes from '$Source' to guest file '$Destination'")) {
          continue
        }
        try {
          $null = Invoke-PVEAgentRequest -Guest $guest -Command file-write -Method POST -Parameters @{ file = $Destination; content = $content; encode = 0 }
        }
        catch {
          $PSCmdlet.WriteError($_)
        }
        continue
      }

      if (-not $PSCmdlet.ShouldProcess($localPath, "Copy guest file '$Source' from $label")) {
        continue
      }
      $stream = $null
      try {
        $stream = [System.IO.File]::Open($localPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        $offset = 0
        do {
          $read = Invoke-PVEAgentRequest -Guest $guest -Command file-read -Parameters @{ file = $Source; offset = $offset; count = $chunkBytes; decode = 0 }
          $chunk = [Convert]::FromBase64String([string](Get-PVEValue $read 'content'))
          $stream.Write($chunk, 0, $chunk.Length)
          $offset += $chunk.Length
          $more = [bool][int](Get-PVEValue $read 'truncated') -and $chunk.Length -gt 0
        } while ($more)
        $stream.Dispose()
        $stream = $null
        Get-Item -LiteralPath $localPath
      }
      catch {
        if ($stream) {
          $stream.Dispose()
          Remove-Item -LiteralPath $localPath -ErrorAction SilentlyContinue
        }
        $PSCmdlet.WriteError($_)
      }
    }
  }
}
