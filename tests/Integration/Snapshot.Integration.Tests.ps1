#Requires -Modules Pester
# Integration tests for the Phase 5 snapshot cmdlets. THESE CREATE AND DELETE GUESTS: each guest is created
# by the test itself, in PVEPS_TEST_POOL, named pveps-test-snap-*, and deleted again at the end.
#
# Safety: the same layers as the lifecycle tests (write token scoped to the test pool and storage; only
# guests this run created, checked with Assert-PVETestGuest; clean-up in AfterAll).
#
# Skipped unless these are set, in addition to PVEPS_TEST_SERVER (and PVEPS_TEST_SKIPCERT if needed):
#   PVEPS_TEST_WRITE_TOKEN_ID, PVEPS_TEST_WRITE_TOKEN_SECRET, PVEPS_TEST_POOL
#   PVEPS_TEST_STORAGE   must support snapshots (for example LVM-thin, ZFS, or directory storage with qcow2)
# Optional:
#   PVEPS_TEST_CT_TEMPLATE   enables the container tests
#
# Run: Invoke-Pester ./tests/Integration/Snapshot.Integration.Tests.ps1 -Output Detailed

BeforeDiscovery {
  $script:HaveSnapshot = [bool]($env:PVEPS_TEST_SERVER -and $env:PVEPS_TEST_WRITE_TOKEN_ID -and $env:PVEPS_TEST_WRITE_TOKEN_SECRET -and $env:PVEPS_TEST_POOL -and $env:PVEPS_TEST_STORAGE)
  $script:HaveCt = [bool]($script:HaveSnapshot -and $env:PVEPS_TEST_CT_TEMPLATE)
}

BeforeAll {
  . (Join-Path $PSScriptRoot 'IntegrationHelpers.ps1')
  Connect-PVETestWrite
  $script:Created = [System.Collections.Generic.List[psobject]]::new()
  $script:RunTag = 'pveps-test-snap-{0}' -f (Get-Random -Minimum 1000 -Maximum 9999)

  function Get-TestConfig {
    param([psobject]$Guest)
    Invoke-PVEApi -Path "/nodes/$($Guest.Node)/$($Guest.Type)/$($Guest.VMId)/config" -ErrorAction Stop
  }
}

AfterAll {
  foreach ($item in $script:Created) {
    $get = if ($item.Type -eq 'lxc') { 'Get-PVEContainer' } else { 'Get-PVEVM' }
    $guest = & $get -VMId $item.VMId -ErrorAction SilentlyContinue
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
      Get-PVEContainerSnapshot -VMId $item.VMId -ErrorAction SilentlyContinue | Remove-PVEContainerSnapshot -Confirm:$false -ErrorAction Continue
      Remove-PVEContainer -VMId $item.VMId -Purge -Confirm:$false -ErrorAction Continue
    }
    else {
      if ((Get-PVETestLiveStatus -Guest $guest) -ne 'stopped') { $null = Stop-PVEVM -VMId $item.VMId -Confirm:$false -ErrorAction Continue }
      Get-PVEVMSnapshot -VMId $item.VMId -ErrorAction SilentlyContinue | Remove-PVEVMSnapshot -Confirm:$false -ErrorAction Continue
      Remove-PVEVM -VMId $item.VMId -Purge -Confirm:$false -ErrorAction Continue
    }
  }
  Disconnect-PVE -Server * -Confirm:$false -ErrorAction SilentlyContinue
}

Describe 'VM snapshots against a real server' -Tag 'Integration', 'Snapshot' -Skip:(-not $script:HaveSnapshot) {
  BeforeAll {
    $script:VM = New-PVEVM -Name "$($script:RunTag)-vm" -Pool $env:PVEPS_TEST_POOL -Cores 1 -MemoryGB 0.5 -DiskGB 1 -Storage $env:PVEPS_TEST_STORAGE -ErrorAction Stop
    $script:Created.Add([pscustomobject]@{ Type = 'qemu'; VMId = $script:VM.VMId })
    Assert-PVETestGuest -Guest $script:VM -Kind 'VM'
  }

  It 'starts with no snapshots' {
    Get-PVEVMSnapshot -VMId $script:VM.VMId -ErrorAction Stop | Should -BeNullOrEmpty
  }

  It 'takes a snapshot and lists it as current' {
    $snap = New-PVEVMSnapshot -VMId $script:VM.VMId -Snapshot one -Description 'First' -ErrorAction Stop
    $snap.Snapshot | Should -Be 'one'
    $snap.Description | Should -Be 'First'
    $snap.IsCurrent | Should -BeTrue
    $snap.Created | Should -BeGreaterThan (Get-Date).AddMinutes(-10)
  }

  It 'changes the description' {
    (Set-PVEVMSnapshot -VMId $script:VM.VMId -Snapshot one -Description 'Renamed' -ErrorAction Stop).Description | Should -Be 'Renamed'
  }

  It 'takes a second snapshot after a configuration change, with the first as its parent' {
    $null = Set-PVEVM -VMId $script:VM.VMId -Cores 2 -ErrorAction Stop
    $snap = New-PVEVMSnapshot -VMId $script:VM.VMId -Snapshot two -ErrorAction Stop
    $snap.Parent | Should -Be 'one'
    @(Get-PVEVMSnapshot -VMId $script:VM.VMId | Where-Object IsCurrent).Snapshot | Should -Be 'two'
  }

  It 'rolls back to the first snapshot, which restores the configuration' {
    $vm = Restore-PVEVMSnapshot -VMId $script:VM.VMId -Snapshot one -Confirm:$false -ErrorAction Stop
    $vm.Status | Should -Be 'stopped'
    [int](Get-TestConfig -Guest $script:VM).cores | Should -Be 1
    @(Get-PVEVMSnapshot -VMId $script:VM.VMId | Where-Object IsCurrent).Snapshot | Should -Be 'one'
  }

  It 'takes a snapshot with RAM of a running VM' {
    $null = Start-PVEVM -VMId $script:VM.VMId -ErrorAction Stop
    $snap = New-PVEVMSnapshot -VMId $script:VM.VMId -Snapshot withram -IncludeMemory -ErrorAction Stop
    $snap.IncludesMemory | Should -BeTrue
    $null = Stop-PVEVM -VMId $script:VM.VMId -Confirm:$false -ErrorAction Stop
  }

  It 'rolls back to the snapshot with RAM, which the API documents as starting the VM' {
    $vm = Restore-PVEVMSnapshot -VMId $script:VM.VMId -Snapshot withram -Confirm:$false -ErrorAction Stop
    $vm.Status | Should -Be 'running'
    $null = Stop-PVEVM -VMId $script:VM.VMId -Confirm:$false -ErrorAction Stop
  }

  It 'deletes the snapshots' {
    Get-PVEVMSnapshot -VMId $script:VM.VMId | Remove-PVEVMSnapshot -Confirm:$false -ErrorAction Stop
    Get-PVEVMSnapshot -VMId $script:VM.VMId | Should -BeNullOrEmpty
  }
}

Describe 'Container snapshots against a real server' -Tag 'Integration', 'Snapshot' -Skip:(-not $script:HaveCt) {
  BeforeAll {
    $script:CT = New-PVEContainer -Name "$($script:RunTag)-ct" -OSTemplate $env:PVEPS_TEST_CT_TEMPLATE -Storage $env:PVEPS_TEST_STORAGE -DiskGB 2 -MemoryGB 0.25 -Pool $env:PVEPS_TEST_POOL -ErrorAction Stop
    $script:Created.Add([pscustomobject]@{ Type = 'lxc'; VMId = $script:CT.VMId })
    Assert-PVETestGuest -Guest $script:CT -Kind 'container'
  }

  It 'takes, rolls back to, and deletes a snapshot' {
    $null = New-PVEContainerSnapshot -VMId $script:CT.VMId -Snapshot clean -ErrorAction Stop
    $null = Set-PVEContainer -VMId $script:CT.VMId -Cores 2 -ErrorAction Stop
    $ct = Restore-PVEContainerSnapshot -VMId $script:CT.VMId -Snapshot clean -Confirm:$false -ErrorAction Stop
    $ct.Status | Should -Be 'stopped'
    (Get-TestConfig -Guest $script:CT).PSObject.Properties.Name | Should -Not -Contain 'cores'
    Remove-PVEContainerSnapshot -VMId $script:CT.VMId -Snapshot clean -Confirm:$false -ErrorAction Stop
    Get-PVEContainerSnapshot -VMId $script:CT.VMId | Should -BeNullOrEmpty
  }
}
