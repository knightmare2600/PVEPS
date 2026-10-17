function New-PVEVMCDDrive {
  <#
  .SYNOPSIS
  Adds a CD drive to QEMU virtual machines, empty or with an ISO.
  .DESCRIPTION
  Adds a drive with media=cdrom on the -Bus bus at the lowest free index (or -Index), with POST
  /nodes/{node}/qemu/{vmid}/config, and writes the new PVEPS.CDDrive object.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER IsoImage
  ISO volume to insert, for example local:iso/debian-13.1.0-amd64-netinst.iso. The drive is empty if
  omitted.
  .PARAMETER Bus
  ide (the default), sata or scsi.
  .PARAMETER Index
  Index on the bus, for example 2 for ide2. Defaults to the lowest free index.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  New-PVEVMCDDrive -VMId 100 -IsoImage local:iso/virtio-win.iso
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestChange.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.CDDrive')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [ValidateNotNullOrEmpty()]
    [string]$IsoImage,

    [ValidateSet('ide', 'sata', 'scsi')]
    [string]$Bus = 'ide',

    [ValidateRange(0, 30)]
    [int]$Index,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $slots = @{ scsi = 31; sata = 6; ide = 4 }
    if ($PSBoundParameters.ContainsKey('Index') -and $Index -ge $slots[$Bus]) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message "The $Bus bus has indexes 0 to $($slots[$Bus] - 1)." -Target $Index))
    }
    $value = '{0},media=cdrom' -f $(if ($IsoImage) { $IsoImage } else { 'none' })
    $what = if ($IsoImage) { "with $IsoImage" } else { 'empty' }
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName
  }

  end {
    foreach ($guest in @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets)) {
      $slot = if ($PSBoundParameters.ContainsKey('Index')) { $Index } else { -1 }
      Add-PVEGuestDevice -Cmdlet $PSCmdlet -Guest $guest -Prefix $Bus -Index $slot -Count $slots[$Bus] -Value $value -Kind CDDrive -Description "Add CD drive {key} ($what)"
    }
  }
}
