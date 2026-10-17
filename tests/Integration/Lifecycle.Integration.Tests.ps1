#Requires -Modules Pester
# Integration tests for the Phase 3 lifecycle cmdlets. THESE CREATE AND DELETE GUESTS: every guest is
# created by the test itself, in PVEPS_TEST_POOL, named pveps-test-lc-*, and deleted again at the end.
# Nothing that existed before the run is changed.
#
# Safety, in layers:
#   1. Use the write token, whose only privileges are on the test pool and the test storage (see README,
#      "Write tests"), so PVE itself refuses anything else.
#   2. Every guest acted on was created by this run (its ID is recorded), and is checked with
#      Assert-PVETestGuest (pool and name) before it is changed or deleted.
#   3. AfterAll deletes whatever this run created and is still there, even after a failure.
#
# Skipped unless these are set, in addition to PVEPS_TEST_SERVER (and PVEPS_TEST_SKIPCERT if needed):
#   PVEPS_TEST_WRITE_TOKEN_ID      e.g. pveps@pve!write
#   PVEPS_TEST_WRITE_TOKEN_SECRET
#   PVEPS_TEST_POOL                e.g. pveps-test
#   PVEPS_TEST_STORAGE             storage for test disks, with 'images' (and for containers 'rootdir')
#                                  content, e.g. local-lvm. The linked-clone test needs a storage type
#                                  that supports linked clones (for example LVM-thin, ZFS, or a
#                                  directory storage with qcow2 disks).
# Optional:
#   PVEPS_TEST_STORAGE2            a second storage, enabling the Move tests
#   PVEPS_TEST_BRIDGE              a bridge, e.g. vmbr0, to give the test guests a network device
#   PVEPS_TEST_CT_TEMPLATE         an LXC OS template volume, enabling the container tests, e.g.
#                                  local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst
#
# Run: Invoke-Pester ./tests/Integration/Lifecycle.Integration.Tests.ps1 -Output Detailed

BeforeDiscovery {
  $script:HaveLifecycle = [bool]($env:PVEPS_TEST_SERVER -and $env:PVEPS_TEST_WRITE_TOKEN_ID -and $env:PVEPS_TEST_WRITE_TOKEN_SECRET -and $env:PVEPS_TEST_POOL -and $env:PVEPS_TEST_STORAGE)
  $script:HaveStorage2 = [bool]$env:PVEPS_TEST_STORAGE2
  $script:HaveCt = [bool]($script:HaveLifecycle -and $env:PVEPS_TEST_CT_TEMPLATE)
}

BeforeAll {
  . (Join-Path $PSScriptRoot 'IntegrationHelpers.ps1')
  Connect-PVETestWrite

  # IDs this run created, by type, for the final clean-up.
  $script:Created = [System.Collections.Generic.List[psobject]]::new()
  $script:RunTag = 'pveps-test-lc-{0}' -f (Get-Random -Minimum 1000 -Maximum 9999)

  function Get-TestConfig {
    param([psobject]$Guest)
    Invoke-PVEApi -Path "/nodes/$($Guest.Node)/$($Guest.Type)/$($Guest.VMId)/config" -ErrorAction Stop
  }

  function Register-Created {
    param([psobject]$Guest)
    $script:Created.Add([pscustomobject]@{ Type = $Guest.Type; VMId = $Guest.VMId })
    Assert-PVETestGuest -Guest $Guest -Kind $Guest.Type
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
    if ((Get-PVETestLiveStatus -Guest $guest) -ne 'stopped') {
      if ($item.Type -eq 'lxc') {
        $null = Stop-PVEContainer -VMId $item.VMId -Confirm:$false -ErrorAction Continue
      }
      else {
        $null = Stop-PVEVM -VMId $item.VMId -Confirm:$false -ErrorAction Continue
      }
    }
    if ($item.Type -eq 'lxc') {
      Remove-PVEContainer -VMId $item.VMId -Purge -Confirm:$false -ErrorAction Continue
    }
    else {
      Remove-PVEVM -VMId $item.VMId -Purge -Confirm:$false -ErrorAction Continue
    }
  }
  Disconnect-PVE -Server * -Confirm:$false -ErrorAction SilentlyContinue
}

Describe 'VM lifecycle against a real server' -Tag 'Integration', 'Lifecycle' -Skip:(-not $script:HaveLifecycle) {
  It 'creates a VM in the test pool with a disk on the test storage' {
    $params = @{
      Name     = "$($script:RunTag)-vm"
      Pool     = $env:PVEPS_TEST_POOL
      Cores    = 1
      MemoryGB = 0.5
      DiskGB   = 1
      Storage  = $env:PVEPS_TEST_STORAGE
      OSType   = 'l26'
      Tags     = 'pveps-test'
    }
    if ($env:PVEPS_TEST_BRIDGE) {
      $params.NetworkBridge = $env:PVEPS_TEST_BRIDGE
    }
    $vm = New-PVEVM @params -ErrorAction Stop
    Register-Created -Guest $vm
    $script:VM = $vm

    $vm.PSObject.TypeNames | Should -Contain 'PVEPS.VM'
    $vm.Status | Should -Be 'stopped'
    $vm.Pool | Should -Be $env:PVEPS_TEST_POOL
    $vm.Tags | Should -Contain 'pveps-test'
    $config = Get-TestConfig -Guest $vm
    $config.scsi0 | Should -BeLike "$($env:PVEPS_TEST_STORAGE):*"
    $config.scsihw | Should -Be 'virtio-scsi-single'
    [string]$config.memory | Should -Be '512'
    $config.boot | Should -BeLike 'order=scsi0*'
  }

  It 'is listed by Get-PVEVM' {
    (Get-PVEVM -VMId $script:VM.VMId -ErrorAction Stop).Name | Should -Be $script:VM.Name
  }

  It 'changes settings with Set-PVEVM' {
    $vm = Set-PVEVM -VMId $script:VM.VMId -Cores 2 -MemoryGB 1 -Tags pveps-test, changed -Description 'PVEPS lifecycle test' -ErrorAction Stop
    $vm.Tags | Should -Contain 'changed'
    $config = Get-TestConfig -Guest $vm
    [int]$config.cores | Should -Be 2
    [string]$config.memory | Should -Be '1024'
    $config.description | Should -BeLike 'PVEPS lifecycle test*'
  }

  It 'removes options with -Delete and empty values' {
    $null = Set-PVEVM -VMId $script:VM.VMId -Description '' -Delete cores -ErrorAction Stop
    $config = Get-TestConfig -Guest $script:VM
    $config.PSObject.Properties.Name | Should -Not -Contain 'description'
    $config.PSObject.Properties.Name | Should -Not -Contain 'cores'
  }

  It 'renames the VM' {
    $newName = "$($script:RunTag)-vm2"
    (Set-PVEVM -VMId $script:VM.VMId -NewName $newName -ErrorAction Stop).Name | Should -Be $newName
    $script:VM.Name = $newName
  }

  It 'moves the disk to the second storage, then back while running with -DeleteSource' -Skip:(-not $script:HaveStorage2) {
    $null = Move-PVEVM -VMId $script:VM.VMId -Storage $env:PVEPS_TEST_STORAGE2 -Confirm:$false -ErrorAction Stop
    (Get-TestConfig -Guest $script:VM).scsi0 | Should -BeLike "$($env:PVEPS_TEST_STORAGE2):*"

    $null = Start-PVEVM -VMId $script:VM.VMId -ErrorAction Stop
    $null = Move-PVEVM -VMId $script:VM.VMId -Storage $env:PVEPS_TEST_STORAGE -DeleteSource -Confirm:$false -ErrorAction Stop
    $config = Get-TestConfig -Guest $script:VM
    $config.scsi0 | Should -BeLike "$($env:PVEPS_TEST_STORAGE):*"
    $config.PSObject.Properties.Name | Where-Object { $_ -like 'unused*' } | Should -BeNullOrEmpty
    $null = Stop-PVEVM -VMId $script:VM.VMId -Confirm:$false -ErrorAction Stop
  }

  It 'refuses to remove or convert the VM while it is running' {
    $null = Start-PVEVM -VMId $script:VM.VMId -ErrorAction Stop
    $errors = $null
    Remove-PVEVM -VMId $script:VM.VMId -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable errors
    ConvertTo-PVEVMTemplate -VMId $script:VM.VMId -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable +errors
    @($errors | Where-Object { $_.FullyQualifiedErrorId -like 'PVEGuestRunning*' }).Count | Should -Be 2
    Get-PVETestLiveStatus -Guest $script:VM | Should -Be 'running'
    $null = Stop-PVEVM -VMId $script:VM.VMId -Confirm:$false -ErrorAction Stop
  }

  It 'converts the VM to a template' {
    $template = ConvertTo-PVEVMTemplate -VMId $script:VM.VMId -Confirm:$false -ErrorAction Stop
    $template.IsTemplate | Should -BeTrue
    (Get-PVEVM -VMId $script:VM.VMId -IncludeTemplate -ErrorAction Stop).IsTemplate | Should -BeTrue
  }

  It 'makes a linked clone of the template' {
    $clone = Copy-PVEVM -VMId $script:VM.VMId -NewName "$($script:RunTag)-linked" -Pool $env:PVEPS_TEST_POOL -ErrorAction Stop
    Register-Created -Guest $clone
    $clone.IsTemplate | Should -BeFalse
    (Get-TestConfig -Guest $clone).scsi0 | Should -BeLike "*base-$($script:VM.VMId)-disk-*"
  }

  It 'makes a full clone of the template' {
    $clone = Copy-PVEVM -VMId $script:VM.VMId -NewName "$($script:RunTag)-full" -Full -Storage $env:PVEPS_TEST_STORAGE -Pool $env:PVEPS_TEST_POOL -ErrorAction Stop
    Register-Created -Guest $clone
    (Get-TestConfig -Guest $clone).scsi0 | Should -Not -BeLike '*base-*'
  }

  It 'removes the clones and the template' {
    $ids = @($script:Created | Where-Object Type -EQ 'qemu' | ForEach-Object { $_.VMId })
    foreach ($id in $ids) {
      Assert-PVETestGuest -Guest (Get-PVEVM -VMId $id -IncludeTemplate -ErrorAction Stop) -Kind 'VM'
    }
    # Clones first: a template with linked clones cannot be deleted.
    $templateId = $script:VM.VMId
    $clones = @($ids | Where-Object { $_ -ne $templateId })
    if ($clones.Count -gt 0) {
      Remove-PVEVM -VMId $clones -Purge -Confirm:$false -ErrorAction Stop
    }
    Remove-PVEVM -VMId $templateId -Purge -Confirm:$false -ErrorAction Stop
    foreach ($id in $ids) {
      Get-PVEVM -VMId $id -IncludeTemplate -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
  }
}

Describe 'Container lifecycle against a real server' -Tag 'Integration', 'Lifecycle' -Skip:(-not $script:HaveCt) {
  It 'creates a container in the test pool' {
    $params = @{
      Name       = "$($script:RunTag)-ct"
      OSTemplate = $env:PVEPS_TEST_CT_TEMPLATE
      Storage    = $env:PVEPS_TEST_STORAGE
      DiskGB     = 2
      MemoryGB   = 0.25
      Pool       = $env:PVEPS_TEST_POOL
      Password   = (New-Guid).Guid
      Tags       = 'pveps-test'
    }
    if ($env:PVEPS_TEST_BRIDGE) {
      $params.NetworkBridge = $env:PVEPS_TEST_BRIDGE
    }
    $ct = New-PVEContainer @params -ErrorAction Stop
    Register-Created -Guest $ct
    $script:CT = $ct

    $ct.PSObject.TypeNames | Should -Contain 'PVEPS.Container'
    $config = Get-TestConfig -Guest $ct
    $config.rootfs | Should -BeLike "$($env:PVEPS_TEST_STORAGE):*"
    [int]$config.unprivileged | Should -Be 1
    [string]$config.memory | Should -Be '256'
  }

  It 'starts it and changes settings while running, warning about anything pending' {
    $null = Start-PVEContainer -VMId $script:CT.VMId -ErrorAction Stop
    $ct = Set-PVEContainer -VMId $script:CT.VMId -MemoryGB 0.5 -Tags pveps-test, changed -WarningVariable warnings -ErrorAction Stop
    $ct.Tags | Should -Contain 'changed'
    $pending = @(Invoke-PVEApi -Path "/nodes/$($ct.Node)/lxc/$($ct.VMId)/pending" | Where-Object { $_.PSObject.Properties.Name -contains 'pending' })
    if ($pending.Count -gt 0) {
      $warnings.Count | Should -Be 1
    }
    else {
      $warnings.Count | Should -Be 0
    }
    $null = Stop-PVEContainer -VMId $script:CT.VMId -Confirm:$false -ErrorAction Stop
  }

  It 'moves the root file system to the second storage' -Skip:(-not $script:HaveStorage2) {
    $null = Move-PVEContainer -VMId $script:CT.VMId -Storage $env:PVEPS_TEST_STORAGE2 -DeleteSource -Confirm:$false -ErrorAction Stop
    (Get-TestConfig -Guest $script:CT).rootfs | Should -BeLike "$($env:PVEPS_TEST_STORAGE2):*"
  }

  It 'converts it to a template and clones it' {
    (ConvertTo-PVEContainerTemplate -VMId $script:CT.VMId -Confirm:$false -ErrorAction Stop).IsTemplate | Should -BeTrue
    $storage = if ($script:HaveStorage2) { $env:PVEPS_TEST_STORAGE2 } else { $env:PVEPS_TEST_STORAGE }
    $clone = Copy-PVEContainer -VMId $script:CT.VMId -NewName "$($script:RunTag)-ctclone" -Full -Storage $storage -Pool $env:PVEPS_TEST_POOL -ErrorAction Stop
    Register-Created -Guest $clone
    $clone.Name | Should -Be "$($script:RunTag)-ctclone"
  }

  It 'removes the clone and the template' {
    $ids = @($script:Created | Where-Object Type -EQ 'lxc' | ForEach-Object { $_.VMId })
    foreach ($id in $ids) {
      Assert-PVETestGuest -Guest (Get-PVEContainer -VMId $id -IncludeTemplate -ErrorAction Stop) -Kind 'container'
    }
    $templateId = $script:CT.VMId
    $clones = @($ids | Where-Object { $_ -ne $templateId })
    if ($clones.Count -gt 0) {
      Remove-PVEContainer -VMId $clones -Purge -Confirm:$false -ErrorAction Stop
    }
    Remove-PVEContainer -VMId $templateId -Purge -Confirm:$false -ErrorAction Stop
    foreach ($id in $ids) {
      Get-PVEContainer -VMId $id -IncludeTemplate -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
  }
}
