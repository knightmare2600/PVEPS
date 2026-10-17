function Set-PVEContainerVolume {
  <#
  .SYNOPSIS
  Grows LXC container volumes or changes their mount options.
  .DESCRIPTION
  -SizeGB grows the root file system or a mount point volume with PUT /nodes/{node}/lxc/{vmid}/resize.
  PVE does not shrink volumes, so a size below the current one is an error and nothing is sent; the
  current size is skipped with a warning.

  The other parameters rewrite the entry with PUT .../config, keeping every option not named.
  .PARAMETER VMId
  Container ID. Binds from piped PVEPS.ContainerVolume or PVEPS.Container objects.
  .PARAMETER VMName
  Container name(s). Wildcards allowed.
  .PARAMETER Device
  Volume(s) to change: rootfs or mpN. Binds from piped PVEPS.ContainerVolume objects.
  .PARAMETER SizeGB
  New size in GiB, larger than the current size. Fractions are allowed (the API accepts them).
  .PARAMETER Path
  New mount path inside the container (mount points only).
  .PARAMETER ReadOnly
  Whether the volume is mounted read-only.
  .PARAMETER Backup
  Whether the mount point is included in backups.
  .PARAMETER Parameter
  Further options by their API names; a $null value removes the option.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Set-PVEContainerVolume -VMId 200 -Device rootfs -SizeGB 16
  .EXAMPLE
  Get-PVEContainerVolume -VMId 200 -Device mp0 | Set-PVEContainerVolume -Backup $true
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

    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Device,

    [ValidateRange(0.001, [double]::MaxValue)]
    [double]$SizeGB,

    [ValidatePattern('^/')]
    [string]$Path,

    [bool]$ReadOnly,

    [bool]$Backup,

    [hashtable]$Parameter,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $changes = [ordered]@{}
    if ($Path) { $changes.mp = $Path }
    if ($PSBoundParameters.ContainsKey('ReadOnly')) { $changes.ro = [int]$ReadOnly }
    if ($PSBoundParameters.ContainsKey('Backup')) { $changes.backup = [int]$Backup }
    if ($Parameter) {
      foreach ($key in $Parameter.Keys) {
        $changes[$key] = $Parameter[$key]
      }
    }
    $resize = $PSBoundParameters.ContainsKey('SizeGB')
    if (-not $resize -and $changes.Count -eq 0) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message 'No change given; specify -SizeGB or an option to change.' -Target $null))
    }
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName -Device $Device
  }

  end {
    foreach ($selection in @(Resolve-PVEDeviceTarget -Cmdlet $PSCmdlet -Type lxc -Target $targets -Kind ContainerVolume -Noun 'volume')) {
      $guest = $selection.Guest
      foreach ($volume in $selection.Devices) {
        $label = '{0} {1}' -f (Get-PVEGuestLabel -Guest $guest), $volume.Device
        if ($Path -and $volume.Device -eq 'rootfs') {
          $PSCmdlet.WriteError((New-PVEArgumentError -Message "$label is the root file system; its mount path is always /." -Target $volume))
          continue
        }
        $changed = $false

        if ($resize) {
          if ($volume.IsBindMount) {
            $PSCmdlet.WriteError((New-PVEArgumentError -Message "$label is a bind mount of $($volume.Volume); it has no size to change." -Target $volume))
            continue
          }
          if ($null -ne $volume.SizeGB -and $SizeGB -lt $volume.SizeGB) {
            $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new("$label is $($volume.SizeGB) GiB; PVE cannot shrink a volume to $SizeGB GiB."),
                'PVEShrinkNotSupported',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $volume))
            continue
          }
          if ($null -ne $volume.SizeGB -and $SizeGB -eq $volume.SizeGB) {
            Write-Warning "$label is already $SizeGB GiB; skipped the resize."
          }
          else {
            $size = '{0}G' -f $SizeGB.ToString([cultureinfo]::InvariantCulture)
            $from = if ($null -ne $volume.SizeGB) { " from $($volume.SizeGB) GiB" } else { '' }
            $body = @{ disk = $volume.Device; size = $size }
            if (-not (Invoke-PVEGuestChange -Cmdlet $PSCmdlet -Guest $guest -Description "Grow volume $($volume.Device)$from to $SizeGB GiB" -Body $body -Endpoint resize)) {
              continue
            }
            $changed = $true
          }
        }

        if ($changes.Count -gt 0) {
          $action = 'Set volume {0} options: {1}' -f $volume.Device, (@($changes.Keys) -join ', ')
          if (Set-PVEGuestDeviceOption -Cmdlet $PSCmdlet -Guest $guest -Device $volume.Device -Kind ContainerVolume -Change $changes -Description $action) {
            $changed = $true
          }
        }

        if ($changed -or ($resize -and $changes.Count -eq 0)) {
          Write-PVEDeviceResult -Cmdlet $PSCmdlet -Guest $guest -Kind ContainerVolume -Device $volume.Device
        }
      }
    }
  }
}
