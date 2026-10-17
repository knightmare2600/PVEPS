function Get-PVEVMCDDrive {
  <#
  .SYNOPSIS
  Gets the CD drives of QEMU virtual machines.
  .DESCRIPTION
  Reads each VM's configuration and writes one PVEPS.CDDrive object per drive with media=cdrom.
  Cloud-init drives are left out (see Get-PVEVMCloudInit). IsoImage is the inserted ISO, or $null for an
  empty drive.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed. Templates are included.
  .PARAMETER Device
  Drive(s) to return, for example ide2. All CD drives if omitted.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Get-PVEVM web01 | Get-PVEVMCDDrive
  .EXAMPLE
  Get-PVEVMCDDrive -VMName '*' | Where-Object IsoImage
  #>
  [CmdletBinding(DefaultParameterSetName = 'Id')]
  [OutputType('PVEPS.CDDrive')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [Parameter(ValueFromPipelineByPropertyName)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Device,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName -Device $Device
  }

  end {
    foreach ($selection in @(Resolve-PVEDeviceTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets -Kind CDDrive -Noun 'CD drive' -IncludeTemplate)) {
      $selection.Devices
    }
  }
}
