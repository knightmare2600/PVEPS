function Set-PVEVMCloudInit {
  <#
  .SYNOPSIS
  Changes the cloud-init settings of QEMU virtual machines, and adds a cloud-init drive if needed.
  .DESCRIPTION
  Sends the settings with POST /nodes/{node}/qemu/{vmid}/config and writes the VM's PVEPS.CloudInit
  object. Only the settings given are changed. An empty value ('' or @()) removes a setting.

  The IP settings apply to one network adapter, -NetworkIndex (net0 by default), and are merged with
  that adapter's current ipconfigN: -Gateway alone keeps the current address.

  cloud-init needs a cloud-init drive. With -Storage, a VM without one gets one (on -DriveBus, at the
  lowest free index); without -Storage, such a VM gets a warning, because the settings are saved but
  unused until a drive is added. -Regenerate rewrites the drive's contents at once
  (PUT /nodes/{node}/qemu/{vmid}/cloudinit); Get-PVEVMCloudInit shows in IsPending whether the drive is
  out of date.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER User
  User whose password and SSH keys cloud-init sets, instead of the image's default user.
  .PARAMETER Password
  Password for that user. Accepts a string or a SecureString. The API documentation advises SSH keys
  instead, and notes that older cloud-init versions do not support hashed passwords.
  .PARAMETER SshPublicKey
  Public SSH keys (OpenSSH format), one per element. Replaces the current keys.
  .PARAMETER NetworkIndex
  Index of the network adapter the IP settings are for. Defaults to 0 (net0).
  .PARAMETER IPAddress
  IPv4 address in CIDR notation (192.0.2.10/24), or dhcp.
  .PARAMETER Gateway
  IPv4 gateway.
  .PARAMETER IPv6Address
  IPv6 address in CIDR notation, dhcp, or auto (stateless autoconfiguration; needs cloud-init 19.4 or
  newer according to the API documentation).
  .PARAMETER Gateway6
  IPv6 gateway.
  .PARAMETER Nameserver
  DNS server addresses.
  .PARAMETER SearchDomain
  DNS search domains.
  .PARAMETER Upgrade
  Whether cloud-init upgrades packages after the first boot.
  .PARAMETER Type
  cloud-init data format: nocloud, configdrive2 or opennebula. By default PVE picks it from the OS type.
  .PARAMETER Storage
  Storage for a cloud-init drive, added if the VM has none.
  .PARAMETER DriveBus
  Bus for an added cloud-init drive: ide (the default), sata or scsi.
  .PARAMETER Regenerate
  Rewrite the cloud-init drive's contents after the change.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Set-PVEVMCloudInit -VMId 100 -User debian -SshPublicKey (Get-Content ~/.ssh/id_ed25519.pub) -IPAddress dhcp -Storage local-lvm
  .EXAMPLE
  Set-PVEVMCloudInit -VMId 100 -IPAddress 192.0.2.10/24 -Gateway 192.0.2.1 -Nameserver 192.0.2.53 -Regenerate
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestChange.')]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Password', Justification = 'Deliberately accepts a string or a SecureString, as Connect-PVE does.')]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '', Justification = '-User and -Password are the separate ciuser and cipassword options; either can be set alone.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.CloudInit')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [AllowEmptyString()]
    [string]$User,

    [ValidateScript({ $_ -is [string] -or $_ -is [securestring] }, ErrorMessage = 'Password must be a string or a SecureString.')]
    [object]$Password,

    [AllowEmptyCollection()]
    [string[]]$SshPublicKey,

    [ValidateRange(0, [int]::MaxValue)]
    [int]$NetworkIndex = 0,

    [AllowEmptyString()]
    [string]$IPAddress,

    [AllowEmptyString()]
    [string]$Gateway,

    [AllowEmptyString()]
    [string]$IPv6Address,

    [AllowEmptyString()]
    [string]$Gateway6,

    [AllowEmptyCollection()]
    [string[]]$Nameserver,

    [AllowEmptyCollection()]
    [string[]]$SearchDomain,

    [bool]$Upgrade,

    [ValidateSet('nocloud', 'configdrive2', 'opennebula')]
    [string]$Type,

    [ValidateNotNullOrEmpty()]
    [string]$Storage,

    [ValidateSet('ide', 'sata', 'scsi')]
    [string]$DriveBus = 'ide',

    [switch]$Regenerate,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    # Settings that are the same for every VM: option name -> value, $null to delete.
    $settings = [ordered]@{}
    if ($PSBoundParameters.ContainsKey('User')) { $settings.ciuser = if ($User) { $User } else { $null } }
    if ($null -ne $Password) {
      $settings.cipassword = if ($Password -is [securestring]) { ConvertFrom-PVESecureString -SecureString $Password } else { $Password }
    }
    if ($PSBoundParameters.ContainsKey('SshPublicKey')) {
      # The sshkeys option has the schema format 'urlencoded': PVE expects the value already URL-encoded.
      $settings.sshkeys = if ($SshPublicKey) { [uri]::EscapeDataString(($SshPublicKey -join "`n")) } else { $null }
    }
    if ($PSBoundParameters.ContainsKey('Nameserver')) { $settings.nameserver = if ($Nameserver) { $Nameserver -join ' ' } else { $null } }
    if ($PSBoundParameters.ContainsKey('SearchDomain')) { $settings.searchdomain = if ($SearchDomain) { $SearchDomain -join ' ' } else { $null } }
    if ($PSBoundParameters.ContainsKey('Upgrade')) { $settings.ciupgrade = [int]$Upgrade }
    if ($Type) { $settings.citype = $Type }

    $ip = [ordered]@{}
    foreach ($pair in @(@('IPAddress', 'ip'), @('Gateway', 'gw'), @('IPv6Address', 'ip6'), @('Gateway6', 'gw6'))) {
      if ($PSBoundParameters.ContainsKey($pair[0])) {
        $value = $PSBoundParameters[$pair[0]]
        $ip[$pair[1]] = if ($value) { $value } else { $null }
      }
    }
    if ($settings.Count -eq 0 -and $ip.Count -eq 0 -and -not $Storage -and -not $Regenerate) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message 'No change given; specify at least one setting, -Storage or -Regenerate.' -Target $null))
    }
    $slots = @{ scsi = 31; sata = 6; ide = 4 }
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName
  }

  end {
    foreach ($guest in @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets)) {
      $label = Get-PVEGuestLabel -Guest $guest
      try {
        $config = Get-PVEGuestConfig -Guest $guest
        $drive = @(Get-PVEGuestDevice -Guest $guest -Kind CloudInitDrive -Config $config) | Select-Object -First 1
      }
      catch {
        $PSCmdlet.WriteError($_)
        continue
      }

      $body = @{}
      $remove = [System.Collections.Generic.List[string]]::new()
      foreach ($key in $settings.Keys) {
        if ($null -eq $settings[$key]) { $remove.Add($key) } else { $body[$key] = $settings[$key] }
      }
      if ($ip.Count -gt 0) {
        $key = "ipconfig$NetworkIndex"
        $option = ConvertFrom-PVEPropertyString -Value ([string](Get-PVEValue $config $key))
        foreach ($part in $ip.Keys) {
          $option[$part] = $ip[$part]
        }
        $value = ConvertTo-PVEPropertyString -Option $option
        if ($value) { $body[$key] = $value } else { $remove.Add($key) }
      }
      $what = @($body.Keys) + @($remove)

      if (-not $drive) {
        if ($Storage) {
          try {
            $slot = Get-PVEFreeDeviceIndex -Prefix $DriveBus -Used @(Get-PVEConfigKey -Config $config) -Count $slots[$DriveBus]
          }
          catch {
            $PSCmdlet.WriteError($_)
            continue
          }
          $body["$DriveBus$slot"] = '{0}:cloudinit' -f $Storage
          $what += "cloud-init drive $DriveBus$slot on $Storage"
        }
        else {
          Write-Warning "$label has no cloud-init drive; the settings are saved but not used until one is added (-Storage)."
        }
      }

      if ($body.Count -gt 0 -or $remove.Count -gt 0) {
        if ($remove.Count -gt 0) {
          $body.delete = $remove -join ','
        }
        $body.digest = Get-PVEValue $config 'digest'
        if (-not (Invoke-PVEGuestChange -Cmdlet $PSCmdlet -Guest $guest -Description "Set cloud-init: $($what -join ', ')" -Body $body)) {
          continue
        }
      }

      if ($Regenerate) {
        if (-not (Invoke-PVEGuestChange -Cmdlet $PSCmdlet -Guest $guest -Description 'Regenerate the cloud-init drive' -Body @{} -Endpoint cloudinit)) {
          continue
        }
      }

      try {
        $null = Update-PVEGuestStatus -Guest $guest
        Write-PVEPendingWarning -Guest $guest
        ConvertTo-PVECloudInit -Guest $guest -Config (Get-PVEGuestConfig -Guest $guest)
      }
      catch {
        $PSCmdlet.WriteError($_)
      }
    }
  }
}
