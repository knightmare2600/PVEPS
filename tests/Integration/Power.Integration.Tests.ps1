#Requires -Modules Pester
# Integration tests for the Phase 2 power cmdlets. THESE CHANGE POWER STATE on one dedicated test VM
# (and optionally one test container). Nothing else on the server is touched.
#
# Safety, in layers:
#   1. Use a token whose only privileges are on a dedicated pool (see README, "Write tests"), so PVE
#      itself refuses anything outside that pool.
#   2. Before acting, these tests refuse to run unless the target is in PVEPS_TEST_POOL and its name
#      starts with 'pveps-test'.
#   3. The guest's power state at the start is restored at the end.
#
# Skipped unless these are set, in addition to PVEPS_TEST_SERVER (and PVEPS_TEST_SKIPCERT if needed):
#   PVEPS_TEST_WRITE_TOKEN_ID      e.g. pveps@pve!write
#   PVEPS_TEST_WRITE_TOKEN_SECRET
#   PVEPS_TEST_POOL                e.g. pveps-test
#   PVEPS_TEST_POWER_VMID          ID of the test VM (name must start with pveps-test)
# Optional:
#   PVEPS_TEST_POWER_CTID          ID of a test container (name must start with pveps-test)
#   PVEPS_TEST_POWER_GUESTOS       1 if the test VM has an OS that answers ACPI shutdown, enabling the
#                                  clean shutdown and reboot tests
#
# Run: Invoke-Pester ./tests/Integration/Power.Integration.Tests.ps1 -Output Detailed

BeforeDiscovery {
  $script:HavePower = [bool]($env:PVEPS_TEST_SERVER -and $env:PVEPS_TEST_WRITE_TOKEN_ID -and $env:PVEPS_TEST_WRITE_TOKEN_SECRET -and $env:PVEPS_TEST_POOL -and $env:PVEPS_TEST_POWER_VMID)
  $script:HaveCt = [bool]($script:HavePower -and $env:PVEPS_TEST_POWER_CTID)
  $script:HaveGuestOs = $env:PVEPS_TEST_POWER_GUESTOS -eq '1'
}

BeforeAll {
  . (Join-Path $PSScriptRoot 'IntegrationHelpers.ps1')
  Connect-PVETestWrite
}

AfterAll {
  Disconnect-PVE -Server * -Confirm:$false -ErrorAction SilentlyContinue
}

Describe 'VM power against a real server' -Tag 'Integration', 'Power' -Skip:(-not $script:HavePower) {
  BeforeAll {
    $script:VMId = [int]$env:PVEPS_TEST_POWER_VMID
    $vm = Get-PVEVM -VMId $script:VMId -ErrorAction Stop
    Assert-PVETestGuest -Guest $vm -Kind 'VM'
    $script:InitialStatus = (Invoke-PVEApi -Path "/nodes/$($vm.Node)/qemu/$($script:VMId)/status/current" -ErrorAction Stop).status
    if ($script:InitialStatus -eq 'running') {
      $null = Stop-PVEVM -VMId $script:VMId -Confirm:$false -ErrorAction Stop
    }
  }

  AfterAll {
    if ($script:InitialStatus -eq 'running') {
      $null = Start-PVEVM -VMId $script:VMId -ErrorAction Continue
    }
    else {
      $null = Stop-PVEVM -VMId $script:VMId -Confirm:$false -WarningAction SilentlyContinue -ErrorAction Continue
    }
  }

  It 'starts the VM and reports it running' {
    $vm = Start-PVEVM -VMId $script:VMId -ErrorAction Stop
    $vm.Status | Should -Be 'running'
  }

  It 'warns and skips when starting a VM that is already running' {
    $warnings = $null
    $vm = Start-PVEVM -VMId $script:VMId -WarningVariable warnings -WarningAction SilentlyContinue -ErrorAction Stop
    $warnings.Count | Should -Be 1
    $vm.Status | Should -Be 'running'
  }

  It 'makes no change under -WhatIf' {
    Stop-PVEVM -VMId $script:VMId -WhatIf
    (Get-PVEVM -VMId $script:VMId | ForEach-Object { Invoke-PVEApi -Path "/nodes/$($_.Node)/qemu/$($_.VMId)/status/current" }).status | Should -Be 'running'
  }

  It 'suspends and resumes the VM' {
    $null = Suspend-PVEVM -VMId $script:VMId -Confirm:$false -ErrorAction Stop
    $node = (Get-PVEVM -VMId $script:VMId).Node
    (Invoke-PVEApi -Path "/nodes/$node/qemu/$($script:VMId)/status/current").qmpstatus | Should -Be 'paused'
    $null = Resume-PVEVM -VMId $script:VMId -ErrorAction Stop
    (Invoke-PVEApi -Path "/nodes/$node/qemu/$($script:VMId)/status/current").qmpstatus | Should -Be 'running'
  }

  It 'resets the VM and it stays running' {
    $vm = Restart-PVEVM -VMId $script:VMId -Confirm:$false -ErrorAction Stop
    $vm.Status | Should -Be 'running'
  }

  It 'reboots the guest cleanly' -Skip:(-not $script:HaveGuestOs) {
    $vm = Restart-PVEVMGuest -VMId $script:VMId -TimeoutSec 180 -Confirm:$false -ErrorAction Stop
    $vm.Status | Should -Be 'running'
  }

  It 'shuts the guest down cleanly' -Skip:(-not $script:HaveGuestOs) {
    $vm = Stop-PVEVMGuest -VMId $script:VMId -TimeoutSec 180 -Confirm:$false -ErrorAction Stop
    $vm.Status | Should -Be 'stopped'
    $null = Start-PVEVM -VMId $script:VMId -ErrorAction Stop
  }

  It 'returns a task with -RunAsync that Wait-PVETask completes' {
    $task = Stop-PVEVM -VMId $script:VMId -Confirm:$false -RunAsync -ErrorAction Stop
    $task.PSObject.TypeNames | Should -Contain 'PVEPS.Task'
    $done = $task | Wait-PVETask -TimeoutSec 120 -ErrorAction Stop
    $done.ExitStatus | Should -Be 'OK'
  }

  It 'warns and skips when stopping a VM that is already stopped' {
    $warnings = $null
    $vm = Stop-PVEVM -VMId $script:VMId -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue -ErrorAction Stop
    $warnings.Count | Should -Be 1
    $vm.Status | Should -Be 'stopped'
  }
}

Describe 'Container power against a real server' -Tag 'Integration', 'Power' -Skip:(-not $script:HaveCt) {
  BeforeAll {
    $script:CtId = [int]$env:PVEPS_TEST_POWER_CTID
    $ct = Get-PVEContainer -VMId $script:CtId -ErrorAction Stop
    Assert-PVETestGuest -Guest $ct -Kind 'container'
    $script:CtInitialStatus = (Invoke-PVEApi -Path "/nodes/$($ct.Node)/lxc/$($script:CtId)/status/current" -ErrorAction Stop).status
    if ($script:CtInitialStatus -eq 'running') {
      $null = Stop-PVEContainer -VMId $script:CtId -Confirm:$false -ErrorAction Stop
    }
  }

  AfterAll {
    if ($script:CtInitialStatus -eq 'running') {
      $null = Start-PVEContainer -VMId $script:CtId -ErrorAction Continue
    }
    else {
      $null = Stop-PVEContainer -VMId $script:CtId -Confirm:$false -WarningAction SilentlyContinue -ErrorAction Continue
    }
  }

  It 'starts the container' {
    (Start-PVEContainer -VMId $script:CtId -ErrorAction Stop).Status | Should -Be 'running'
  }

  It 'reboots the container' {
    (Restart-PVEContainer -VMId $script:CtId -TimeoutSec 120 -Confirm:$false -ErrorAction Stop).Status | Should -Be 'running'
  }

  It 'shuts the container down cleanly' {
    (Stop-PVEContainerGuest -VMId $script:CtId -TimeoutSec 120 -ForceStop -Confirm:$false -ErrorAction Stop).Status | Should -Be 'stopped'
  }

  It 'starts and hard-stops the container' {
    $null = Start-PVEContainer -VMId $script:CtId -ErrorAction Stop
    (Stop-PVEContainer -VMId $script:CtId -Confirm:$false -ErrorAction Stop).Status | Should -Be 'stopped'
  }
}
