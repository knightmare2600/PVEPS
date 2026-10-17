function ConvertTo-PVECloudInit {
  <#
  .SYNOPSIS
  Builds a PVEPS.CloudInit object from a VM configuration.
  .DESCRIPTION
  - Drive: the cloud-init drive (for example ide2), or $null if the VM has none.
  - PasswordSet: whether cipassword is set; the password itself is not shown.
  - SshPublicKey: the keys, one per element. PVE stores them URL-encoded; they are decoded here.
  - Upgrade: ciupgrade, with the schema's default of 1 when unset.
  - IPConfig: one object per ipconfigN, with its index.
  - IsPending: whether the drive's contents are out of date, from GET .../cloudinit (an option with a
    pending value or a pending delete). $null without a drive.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [psobject]$Guest,

    [AllowNull()]
    [object]$Config
  )

  $drive = @(Get-PVEGuestDevice -Guest $Guest -Kind CloudInitDrive -Config $Config) | Select-Object -First 1
  $keys = @(Get-PVEConfigKey -Config $Config)

  $sshkeys = [string](Get-PVEValue $Config 'sshkeys')
  $upgrade = Get-PVEValue $Config 'ciupgrade'
  $ipconfig = @(
    $keys | Where-Object { $_ -match '^ipconfig\d+$' } | Sort-Object -Property { [int]($_ -replace '^ipconfig', '') } | ForEach-Object {
      $option = ConvertFrom-PVEPropertyString -Value ([string](Get-PVEValue $Config $_))
      [pscustomobject]@{
        PSTypeName  = 'PVEPS.CloudInitIPConfig'
        Index       = [int]($_ -replace '^ipconfig', '')
        IPAddress   = $option['ip']
        Gateway     = $option['gw']
        IPv6Address = $option['ip6']
        Gateway6    = $option['gw6']
      }
    }
  )

  $pending = $null
  if ($drive) {
    $path = Format-PVEPath '/nodes/{node}/qemu/{vmid}/cloudinit' @{ node = $Guest.Node; vmid = $Guest.VMId }
    $items = @(Invoke-PVERequest -Connection $Guest.Connection -Path $path)
    $pending = @($items | Where-Object { $null -ne (Get-PVEValue $_ 'pending') -or [int](Get-PVEValue $_ 'delete') -gt 0 }).Count -gt 0
  }

  [pscustomobject]@{
    PSTypeName   = 'PVEPS.CloudInit'
    VMId         = $Guest.VMId
    VMName       = $Guest.Name
    Node         = $Guest.Node
    Drive        = if ($drive) { $drive.Device } else { $null }
    DriveStorage = if ($drive) { $drive.Storage } else { $null }
    User         = Get-PVEValue $Config 'ciuser'
    PasswordSet  = $keys -contains 'cipassword'
    SshPublicKey = [string[]]@([uri]::UnescapeDataString($sshkeys) -split '\r?\n' | Where-Object { $_ })
    IPConfig     = $ipconfig
    Nameserver   = [string[]]@([string](Get-PVEValue $Config 'nameserver') -split '[,;\s]+' | Where-Object { $_ })
    SearchDomain = [string[]]@([string](Get-PVEValue $Config 'searchdomain') -split '[,;\s]+' | Where-Object { $_ })
    Upgrade      = if ($null -ne $upgrade) { [bool][int]$upgrade } else { $true }
    Type         = Get-PVEValue $Config 'citype'
    Custom       = Get-PVEValue $Config 'cicustom'
    IsPending    = $pending
    Connection   = $Guest.Connection
  }
}
