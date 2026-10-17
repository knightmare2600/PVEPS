function Get-PVEVMCloudInit {
  <#
  .SYNOPSIS
  Gets the cloud-init settings of QEMU virtual machines.
  .DESCRIPTION
  Writes one PVEPS.CloudInit object per VM: the cloud-init drive (if any), user, whether a password is
  set, SSH keys, per-adapter IP configuration, DNS settings, and IsPending, which says whether the drive
  still holds older settings than the configuration.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed. Templates are included.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Get-PVEVM web01 | Get-PVEVMCloudInit
  .EXAMPLE
  (Get-PVEVMCloudInit -VMId 100).IPConfig
  #>
  [CmdletBinding(DefaultParameterSetName = 'Id')]
  [OutputType('PVEPS.CloudInit')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName
  }

  end {
    foreach ($guest in @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets -IncludeTemplate)) {
      try {
        ConvertTo-PVECloudInit -Guest $guest -Config (Get-PVEGuestConfig -Guest $guest)
      }
      catch {
        $PSCmdlet.WriteError($_)
      }
    }
  }
}
