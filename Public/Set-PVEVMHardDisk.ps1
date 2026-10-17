function Set-PVEVMHardDisk {
  <#
  .SYNOPSIS
  Grows QEMU hard disks or changes their options.
  .DESCRIPTION
  -SizeGB grows the disk with PUT /nodes/{node}/qemu/{vmid}/resize. PVE does not shrink disks, so a
  size below the current one is an error and nothing is sent; the current size is skipped with a warning.
  Growing the disk does not grow the partitions or file systems inside the guest.

  The other parameters rewrite the disk's entry with POST .../config, keeping every option not named.
  On a running VM some option changes are pending until the next start, and a warning says so.
  .PARAMETER VMId
  VM ID. Binds from piped PVEPS.HardDisk or PVEPS.VM objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER Device
  Disk(s) to change, for example scsi0. Binds from piped PVEPS.HardDisk objects.
  .PARAMETER SizeGB
  New size in GiB, larger than the current size. Fractions are allowed (the API accepts them).
  .PARAMETER Cache
  Cache mode: none, writethrough, writeback, unsafe or directsync.
  .PARAMETER SSD
  Whether the disk is presented to the guest as an SSD.
  .PARAMETER Discard
  Whether discard/TRIM requests are passed to the storage.
  .PARAMETER IOThread
  Whether the disk has its own I/O thread.
  .PARAMETER Backup
  Whether the disk is included in backups.
  .PARAMETER Parameter
  Further drive options by their API names. A $null value removes the option, for example
  @{ iops_rd = $null }.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Set-PVEVMHardDisk -VMId 100 -Device scsi0 -SizeGB 64
  .EXAMPLE
  Get-PVEVM db* | Get-PVEVMHardDisk -Device scsi1 | Set-PVEVMHardDisk -Discard $true -SSD $true
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestChange.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.HardDisk')]
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

    [ValidateSet('none', 'writethrough', 'writeback', 'unsafe', 'directsync')]
    [string]$Cache,

    [bool]$SSD,

    [bool]$Discard,

    [bool]$IOThread,

    [bool]$Backup,

    [hashtable]$Parameter,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $changes = [ordered]@{}
    if ($Cache) { $changes.cache = $Cache }
    if ($PSBoundParameters.ContainsKey('SSD')) { $changes.ssd = [int]$SSD }
    if ($PSBoundParameters.ContainsKey('Discard')) { $changes.discard = if ($Discard) { 'on' } else { 'ignore' } }
    if ($PSBoundParameters.ContainsKey('IOThread')) { $changes.iothread = [int]$IOThread }
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
    foreach ($selection in @(Resolve-PVEDeviceTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets -Kind HardDisk -Noun 'hard disk')) {
      $guest = $selection.Guest
      foreach ($disk in $selection.Devices) {
        $label = '{0} {1}' -f (Get-PVEGuestLabel -Guest $guest), $disk.Device
        $changed = $false

        if ($resize) {
          if ($null -ne $disk.SizeGB -and $SizeGB -lt $disk.SizeGB) {
            $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new("$label is $($disk.SizeGB) GiB; PVE cannot shrink a disk to $SizeGB GiB."),
                'PVEShrinkNotSupported',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $disk))
            continue
          }
          if ($null -ne $disk.SizeGB -and $SizeGB -eq $disk.SizeGB) {
            Write-Warning "$label is already $SizeGB GiB; skipped the resize."
          }
          else {
            $size = '{0}G' -f $SizeGB.ToString([cultureinfo]::InvariantCulture)
            $from = if ($null -ne $disk.SizeGB) { " from $($disk.SizeGB) GiB" } else { '' }
            $body = @{ disk = $disk.Device; size = $size }
            if (-not (Invoke-PVEGuestChange -Cmdlet $PSCmdlet -Guest $guest -Description "Grow hard disk $($disk.Device)$from to $SizeGB GiB" -Body $body -Endpoint resize)) {
              continue
            }
            $changed = $true
          }
        }

        if ($changes.Count -gt 0) {
          $action = 'Set hard disk {0} options: {1}' -f $disk.Device, (@($changes.Keys) -join ', ')
          if (Set-PVEGuestDeviceOption -Cmdlet $PSCmdlet -Guest $guest -Device $disk.Device -Kind HardDisk -Change $changes -Description $action) {
            $changed = $true
          }
        }

        if ($changed -or ($resize -and $changes.Count -eq 0)) {
          Write-PVEDeviceResult -Cmdlet $PSCmdlet -Guest $guest -Kind HardDisk -Device $disk.Device
        }
      }
    }
  }
}
