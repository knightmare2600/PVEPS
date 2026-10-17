function New-PVEContainerVolume {
  <#
  .SYNOPSIS
  Adds a mount point to LXC containers: a new volume, or a bind mount of a host directory.
  .DESCRIPTION
  Adds an mpN entry at the lowest free index (or -Index) with PUT /nodes/{node}/lxc/{vmid}/config, and
  writes the new PVEPS.ContainerVolume object. -SizeGB with -Storage creates a new volume; -HostPath
  bind-mounts a directory of the host. The API documentation restricts mount points that are not storage
  volumes (bind mounts) to root@pam.

  On a running container the mount point can be pending until the next start, and a warning says so.
  .PARAMETER VMId
  Container ID(s). Binds from piped PVEPS.Container objects.
  .PARAMETER VMName
  Container name(s). Wildcards allowed.
  .PARAMETER Path
  Mount path inside the container, for example /srv/data.
  .PARAMETER SizeGB
  Size of the new volume in GiB. Needs -Storage.
  .PARAMETER Storage
  Storage for the new volume.
  .PARAMETER HostPath
  Host directory to bind-mount instead of creating a volume.
  .PARAMETER ReadOnly
  Mount read-only.
  .PARAMETER Backup
  Include the mount point in backups. The API documentation says this applies only to volume mount
  points.
  .PARAMETER Index
  Index of the mount point, for example 1 for mp1. Defaults to the lowest free index.
  .PARAMETER Parameter
  Further mount point options by their API names, for example @{ mountoptions = 'noatime' }.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  New-PVEContainerVolume -VMId 200 -Path /srv/data -SizeGB 20 -Storage local-lvm -Backup
  .EXAMPLE
  New-PVEContainerVolume -VMId 200 -Path /mnt/media -HostPath /tank/media -ReadOnly
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestChange.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.ContainerVolume')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [Parameter(Mandatory)]
    [ValidatePattern('^/')]
    [string]$Path,

    [ValidateRange(1, [int]::MaxValue)]
    [int]$SizeGB,

    [ValidateNotNullOrEmpty()]
    [string]$Storage,

    [ValidatePattern('^/')]
    [string]$HostPath,

    [switch]$ReadOnly,

    [switch]$Backup,

    [ValidateRange(0, 255)]
    [int]$Index,

    [hashtable]$Parameter,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    if ($HostPath -and ($SizeGB -or $Storage)) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message 'Give either -HostPath, or -SizeGB with -Storage, not both.' -Target $HostPath))
    }
    if (-not $HostPath -and -not ($SizeGB -and $Storage)) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message 'Give -SizeGB with -Storage for a new volume, or -HostPath for a bind mount.' -Target $null))
    }
    $option = [ordered]@{ volume = if ($HostPath) { $HostPath } else { '{0}:{1}' -f $Storage, $SizeGB }; mp = $Path }
    if ($ReadOnly) { $option.ro = 1 }
    if ($Backup) { $option.backup = 1 }
    if ($Parameter) {
      foreach ($key in $Parameter.Keys) {
        $option[$key] = $Parameter[$key]
      }
    }
    $value = ConvertTo-PVEPropertyString -Option $option -DefaultKey volume
    $what = if ($HostPath) { "bind mount of $HostPath" } else { "$SizeGB GiB on $Storage" }
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName
  }

  end {
    foreach ($guest in @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type lxc -Target $targets)) {
      $slot = if ($PSBoundParameters.ContainsKey('Index')) { $Index } else { -1 }
      Add-PVEGuestDevice -Cmdlet $PSCmdlet -Guest $guest -Prefix mp -Index $slot -Count 256 -Value $value -Kind ContainerVolume -Description "Add mount point {key} at $Path ($what)"
    }
  }
}
