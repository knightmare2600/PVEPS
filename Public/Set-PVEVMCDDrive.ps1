function Set-PVEVMCDDrive {
  <#
  .SYNOPSIS
  Inserts an ISO into, or ejects the media from, QEMU CD drives.
  .DESCRIPTION
  Rewrites each drive's entry with POST /nodes/{node}/qemu/{vmid}/config, keeping its other options, and
  writes the drive as now configured.
  .PARAMETER VMId
  VM ID. Binds from piped PVEPS.CDDrive or PVEPS.VM objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER Device
  Drive(s) to change, for example ide2. Binds from piped PVEPS.CDDrive objects.
  .PARAMETER IsoImage
  ISO volume to insert, for example local:iso/debian-13.1.0-amd64-netinst.iso.
  .PARAMETER NoMedia
  Eject the media, leaving the drive empty.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Set-PVEVMCDDrive -VMId 100 -Device ide2 -IsoImage local:iso/virtio-win.iso
  .EXAMPLE
  Get-PVEVMCDDrive -VMName '*' | Where-Object IsoImage | Set-PVEVMCDDrive -NoMedia
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestChange.')]
  [CmdletBinding(DefaultParameterSetName = 'IdIso', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.CDDrive')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'IdIso', ValueFromPipelineByPropertyName)]
    [Parameter(Mandatory, ParameterSetName = 'IdEject', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'NameIso', Position = 0)]
    [Parameter(Mandatory, ParameterSetName = 'NameEject', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Device,

    [Parameter(Mandatory, ParameterSetName = 'IdIso')]
    [Parameter(Mandatory, ParameterSetName = 'NameIso')]
    [ValidateNotNullOrEmpty()]
    [string]$IsoImage,

    [Parameter(Mandatory, ParameterSetName = 'IdEject')]
    [Parameter(Mandatory, ParameterSetName = 'NameEject')]
    [switch]$NoMedia,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $file = if ($NoMedia) { 'none' } else { $IsoImage }
    $action = if ($NoMedia) { 'Eject media from CD drive' } else { "Insert $IsoImage into CD drive" }
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName -Device $Device
  }

  end {
    foreach ($selection in @(Resolve-PVEDeviceTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets -Kind CDDrive -Noun 'CD drive')) {
      foreach ($drive in $selection.Devices) {
        if (Set-PVEGuestDeviceOption -Cmdlet $PSCmdlet -Guest $selection.Guest -Device $drive.Device -Kind CDDrive -Change ([ordered]@{ file = $file }) -Description "$action $($drive.Device)") {
          Write-PVEDeviceResult -Cmdlet $PSCmdlet -Guest $selection.Guest -Kind CDDrive -Device $drive.Device
        }
      }
    }
  }
}
