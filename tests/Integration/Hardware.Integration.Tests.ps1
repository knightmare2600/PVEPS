#Requires -Modules Pester
# Integration tests for the Phase 4 hardware cmdlets. THESE CREATE AND DELETE GUESTS: each guest is created
# by the test itself, in PVEPS_TEST_POOL, named pveps-test-hw-*, and deleted again at the end. Nothing
# that existed before the run is changed.
#
# Safety: the same layers as the lifecycle tests (write token scoped to the test pool and storage; only
# guests this run created, checked with Assert-PVETestGuest; clean-up in AfterAll).
#
# Skipped unless these are set, in addition to PVEPS_TEST_SERVER (and PVEPS_TEST_SKIPCERT if needed):
#   PVEPS_TEST_WRITE_TOKEN_ID, PVEPS_TEST_WRITE_TOKEN_SECRET, PVEPS_TEST_POOL, PVEPS_TEST_STORAGE
# Optional:
#   PVEPS_TEST_BRIDGE        enables the network adapter tests
#   PVEPS_TEST_ISO           an ISO volume, e.g. local:iso/debian-13.1.0-amd64-netinst.iso, for the CD test
#   PVEPS_TEST_CT_TEMPLATE   an LXC OS template volume, enabling the container tests
#
# Run: Invoke-Pester ./tests/Integration/Hardware.Integration.Tests.ps1 -Output Detailed

BeforeDiscovery {
  $script:HaveHardware = [bool]($env:PVEPS_TEST_SERVER -and $env:PVEPS_TEST_WRITE_TOKEN_ID -and $env:PVEPS_TEST_WRITE_TOKEN_SECRET -and $env:PVEPS_TEST_POOL -and $env:PVEPS_TEST_STORAGE)
  $script:HaveBridge = [bool]$env:PVEPS_TEST_BRIDGE
  $script:HaveIso = [bool]$env:PVEPS_TEST_ISO
  $script:HaveCt = [bool]($script:HaveHardware -and $env:PVEPS_TEST_CT_TEMPLATE)
}

BeforeAll {
  . (Join-Path $PSScriptRoot 'IntegrationHelpers.ps1')
  Connect-PVETestWrite
  $script:Created = [System.Collections.Generic.List[psobject]]::new()
  $script:RunTag = 'pveps-test-hw-{0}' -f (Get-Random -Minimum 1000 -Maximum 9999)

  function Get-TestConfig {
    param([psobject]$Guest)
    Invoke-PVEApi -Path "/nodes/$($Guest.Node)/$($Guest.Type)/$($Guest.VMId)/config" -ErrorAction Stop
  }

  function Get-StorageVolumeId {
    # Volume IDs on the test storage for this guest, straight from the storage content listing.
    param([psobject]$Guest)
    @(Invoke-PVEApi -Path "/nodes/$($Guest.Node)/storage/$($env:PVEPS_TEST_STORAGE)/content" -Parameters @{ vmid = $Guest.VMId } -ErrorAction Stop | ForEach-Object { $_.volid })
  }
}

AfterAll {
  foreach ($item in $script:Created) {
    $get = if ($item.Type -eq 'lxc') { 'Get-PVEContainer' } else { 'Get-PVEVM' }
    $guest = & $get -VMId $item.VMId -IncludeTemplate -ErrorAction SilentlyContinue
    if (-not $guest) {
      continue
    }
    try {
      Assert-PVETestGuest -Guest $guest -Kind $item.Type
    }
    catch {
      Write-Warning "Clean-up skipped: $_"
      continue
    }
    if ($item.Type -eq 'lxc') {
      if ((Get-PVETestLiveStatus -Guest $guest) -ne 'stopped') { $null = Stop-PVEContainer -VMId $item.VMId -Confirm:$false -ErrorAction Continue }
      Remove-PVEContainer -VMId $item.VMId -Purge -Confirm:$false -ErrorAction Continue
    }
    else {
      if ((Get-PVETestLiveStatus -Guest $guest) -ne 'stopped') { $null = Stop-PVEVM -VMId $item.VMId -Confirm:$false -ErrorAction Continue }
      Remove-PVEVM -VMId $item.VMId -Purge -DestroyUnreferencedDisks -Confirm:$false -ErrorAction Continue
    }
  }
  Disconnect-PVE -Server * -Confirm:$false -ErrorAction SilentlyContinue
}

Describe 'VM hardware against a real server' -Tag 'Integration', 'Hardware' -Skip:(-not $script:HaveHardware) {
  BeforeAll {
    $script:VM = New-PVEVM -Name "$($script:RunTag)-vm" -Pool $env:PVEPS_TEST_POOL -MemoryGB 0.5 -DiskGB 1 -Storage $env:PVEPS_TEST_STORAGE -ErrorAction Stop
    $script:Created.Add([pscustomobject]@{ Type = 'qemu'; VMId = $script:VM.VMId })
    Assert-PVETestGuest -Guest $script:VM -Kind 'VM'
  }

  It 'lists the disk New-PVEVM created' {
    $disk = Get-PVEVMHardDisk -VMId $script:VM.VMId -ErrorAction Stop
    $disk.Device | Should -Be 'scsi0'
    $disk.Storage | Should -Be $env:PVEPS_TEST_STORAGE
    $disk.SizeGB | Should -Be 1
  }

  It 'adds a second disk at the next free index' {
    $disk = New-PVEVMHardDisk -VMId $script:VM.VMId -SizeGB 1 -Storage $env:PVEPS_TEST_STORAGE -Discard -ErrorAction Stop
    $disk.Device | Should -Be 'scsi1'
    $disk.Discard | Should -BeTrue
    (Get-TestConfig -Guest $script:VM).scsi1 | Should -BeLike '*discard=on*'
  }

  It 'grows the disk, and refuses to shrink it' {
    (Set-PVEVMHardDisk -VMId $script:VM.VMId -Device scsi1 -SizeGB 2 -ErrorAction Stop).SizeGB | Should -Be 2
    $errors = $null
    Set-PVEVMHardDisk -VMId $script:VM.VMId -Device scsi1 -SizeGB 1 -ErrorAction SilentlyContinue -ErrorVariable errors
    @($errors | Where-Object { $_.FullyQualifiedErrorId -like 'PVEShrinkNotSupported*' }).Count | Should -Be 1
  }

  It 'changes disk options and keeps the others' {
    $disk = Set-PVEVMHardDisk -VMId $script:VM.VMId -Device scsi1 -SSD $true -ErrorAction Stop
    $disk.SSD | Should -BeTrue
    $disk.Discard | Should -BeTrue
  }

  It 'detaches the disk to an unused entry, attaches it again, then deletes it permanently' {
    $volume = (Get-PVEVMHardDisk -VMId $script:VM.VMId -Device scsi1 -ErrorAction Stop).Volume
    Remove-PVEVMHardDisk -VMId $script:VM.VMId -Device scsi1 -Confirm:$false -ErrorAction Stop
    $config = Get-TestConfig -Guest $script:VM
    $config.PSObject.Properties.Name | Should -Not -Contain 'scsi1'
    @($config.PSObject.Properties | Where-Object { $_.Name -like 'unused*' -and $_.Value -eq $volume }).Count | Should -Be 1

    (New-PVEVMHardDisk -VMId $script:VM.VMId -Volume $volume -Index 1 -ErrorAction Stop).Volume | Should -Be $volume

    Remove-PVEVMHardDisk -VMId $script:VM.VMId -Device scsi1 -DeletePermanently -Confirm:$false -ErrorAction Stop
    $config = Get-TestConfig -Guest $script:VM
    @($config.PSObject.Properties | Where-Object { $_.Value -like "$volume*" }).Count | Should -Be 0
    Get-StorageVolumeId -Guest $script:VM | Should -Not -Contain $volume
  }

  It 'adds, changes and removes a network adapter' -Skip:(-not $script:HaveBridge) {
    $nic = New-PVEVMNetworkAdapter -VMId $script:VM.VMId -Bridge $env:PVEPS_TEST_BRIDGE -VlanTag 99 -ErrorAction Stop
    $nic.Device | Should -Be 'net0'
    $nic.MacAddress | Should -Match '^([0-9A-F]{2}:){5}[0-9A-F]{2}$'
    $mac = $nic.MacAddress

    $nic = Set-PVEVMNetworkAdapter -VMId $script:VM.VMId -Device net0 -Model e1000 -VlanTag 0 -Connected $false -ErrorAction Stop
    $nic.Model | Should -Be 'e1000'
    $nic.MacAddress | Should -Be $mac
    $nic.VlanTag | Should -BeNullOrEmpty
    $nic.Connected | Should -BeFalse

    Remove-PVEVMNetworkAdapter -VMId $script:VM.VMId -Device net0 -Confirm:$false -ErrorAction Stop
    Get-PVEVMNetworkAdapter -VMId $script:VM.VMId | Should -BeNullOrEmpty
  }

  It 'adds an empty CD drive and removes it' {
    $drive = New-PVEVMCDDrive -VMId $script:VM.VMId -ErrorAction Stop
    $drive.IsoImage | Should -BeNullOrEmpty
    $script:CDDevice = $drive.Device
    Remove-PVEVMCDDrive -VMId $script:VM.VMId -Device $script:CDDevice -Confirm:$false -ErrorAction Stop
    Get-PVEVMCDDrive -VMId $script:VM.VMId | Should -BeNullOrEmpty
  }

  It 'inserts and ejects an ISO' -Skip:(-not $script:HaveIso) {
    $drive = New-PVEVMCDDrive -VMId $script:VM.VMId -IsoImage $env:PVEPS_TEST_ISO -ErrorAction Stop
    $drive.IsoImage | Should -Be $env:PVEPS_TEST_ISO
    (Set-PVEVMCDDrive -VMId $script:VM.VMId -Device $drive.Device -NoMedia -ErrorAction Stop).IsoImage | Should -BeNullOrEmpty
    (Set-PVEVMCDDrive -VMId $script:VM.VMId -Device $drive.Device -IsoImage $env:PVEPS_TEST_ISO -ErrorAction Stop).IsoImage | Should -Be $env:PVEPS_TEST_ISO
    Remove-PVEVMCDDrive -VMId $script:VM.VMId -Device $drive.Device -Confirm:$false -ErrorAction Stop
  }

  It 'adds a cloud-init drive and settings, with SSH keys that survive the URL-encoding' {
    $keys = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPvepsTestKeyOne pveps@test', 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPvepsTestKeyTwo+/= other@test'
    $ci = Set-PVEVMCloudInit -VMId $script:VM.VMId -User pveps -SshPublicKey $keys -IPAddress 192.0.2.10/24 -Gateway 192.0.2.1 -Nameserver 192.0.2.53 -Storage $env:PVEPS_TEST_STORAGE -ErrorAction Stop
    $ci.Drive | Should -Not -BeNullOrEmpty
    $ci.User | Should -Be 'pveps'
    $ci.SshPublicKey | Should -Be $keys
    $ci.IPConfig[0].IPAddress | Should -Be '192.0.2.10/24'
    $ci.IPConfig[0].Gateway | Should -Be '192.0.2.1'
    $ci.Nameserver | Should -Be @('192.0.2.53')
  }

  It 'merges an IP change into the existing settings and regenerates the drive' {
    $ci = Set-PVEVMCloudInit -VMId $script:VM.VMId -IPAddress 192.0.2.11/24 -Regenerate -ErrorAction Stop
    $ci.IPConfig[0].IPAddress | Should -Be '192.0.2.11/24'
    $ci.IPConfig[0].Gateway | Should -Be '192.0.2.1'
    $ci.IsPending | Should -BeFalse
  }

  It 'does not list the cloud-init drive as a CD drive' {
    Get-PVEVMCDDrive -VMId $script:VM.VMId | Should -BeNullOrEmpty
  }
}

Describe 'Container hardware against a real server' -Tag 'Integration', 'Hardware' -Skip:(-not $script:HaveCt) {
  BeforeAll {
    $script:CT = New-PVEContainer -Name "$($script:RunTag)-ct" -OSTemplate $env:PVEPS_TEST_CT_TEMPLATE -Storage $env:PVEPS_TEST_STORAGE -DiskGB 2 -MemoryGB 0.25 -Pool $env:PVEPS_TEST_POOL -ErrorAction Stop
    $script:Created.Add([pscustomobject]@{ Type = 'lxc'; VMId = $script:CT.VMId })
    Assert-PVETestGuest -Guest $script:CT -Kind 'container'
  }

  It 'grows the root file system' {
    (Set-PVEContainerVolume -VMId $script:CT.VMId -Device rootfs -SizeGB 3 -ErrorAction Stop).SizeGB | Should -Be 3
  }

  It 'adds a mount point volume and changes its options' {
    $volume = New-PVEContainerVolume -VMId $script:CT.VMId -Path /srv/pveps -SizeGB 1 -Storage $env:PVEPS_TEST_STORAGE -ErrorAction Stop
    $volume.Device | Should -Be 'mp0'
    $volume.Path | Should -Be '/srv/pveps'
    $volume = Set-PVEContainerVolume -VMId $script:CT.VMId -Device mp0 -Backup $true -ErrorAction Stop
    $volume.Options.backup | Should -Be '1'
  }

  It 'deletes the mount point volume permanently, and the volume is gone from the storage' {
    $volume = (Get-PVEContainerVolume -VMId $script:CT.VMId -Device mp0 -ErrorAction Stop).Volume
    Get-StorageVolumeId -Guest $script:CT | Should -Contain $volume
    Remove-PVEContainerVolume -VMId $script:CT.VMId -Device mp0 -DeletePermanently -Confirm:$false -ErrorAction Stop
    $config = Get-TestConfig -Guest $script:CT
    @($config.PSObject.Properties | Where-Object { $_.Name -like 'unused*' -or $_.Name -eq 'mp0' }).Count | Should -Be 0
    Get-StorageVolumeId -Guest $script:CT | Should -Not -Contain $volume
  }

  It 'adds, changes and removes a network adapter' -Skip:(-not $script:HaveBridge) {
    $nic = New-PVEContainerNetworkAdapter -VMId $script:CT.VMId -Bridge $env:PVEPS_TEST_BRIDGE -ErrorAction Stop
    $nic.InterfaceName | Should -Be "eth$($nic.Device -replace '^net', '')"
    $nic.IPAddress | Should -Be 'dhcp'
    $nic = Set-PVEContainerNetworkAdapter -VMId $script:CT.VMId -Device $nic.Device -IPAddress 192.0.2.30/24 -Gateway 192.0.2.1 -ErrorAction Stop
    $nic.IPAddress | Should -Be '192.0.2.30/24'
    $nic.Gateway | Should -Be '192.0.2.1'
    Remove-PVEContainerNetworkAdapter -VMId $script:CT.VMId -Device $nic.Device -Confirm:$false -ErrorAction Stop
    Get-PVEContainerNetworkAdapter -VMId $script:CT.VMId -Device $nic.Device -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
  }
}
