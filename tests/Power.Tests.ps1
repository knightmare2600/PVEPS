#Requires -Modules Pester
# Phase 2 power cmdlets. HTTP is mocked (see TestHelpers.ps1); nothing here touches a real server.
# The fake server keeps a cached status (served by /cluster/resources) separate from the live status
# (served by status/current), so the tests can prove decisions use the live status.

BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  Mock -ModuleName PVEPS Start-Sleep { }

  function Initialize-Power {
    Reset-FakeState
    $script:Guests = @(
      @{ type = 'qemu'; vmid = 100; name = 'web01'; node = 'pve'; template = 0 }
      @{ type = 'qemu'; vmid = 101; name = 'db01'; node = 'pve'; template = 0 }
      @{ type = 'qemu'; vmid = 102; name = 'db02'; node = 'pve'; template = 0 }
      @{ type = 'qemu'; vmid = 9000; name = 'tmpl-debian'; node = 'pve'; template = 1 }
      @{ type = 'lxc'; vmid = 200; name = 'dns01'; node = 'pve'; template = 0 }
      @{ type = 'lxc'; vmid = 201; name = 'proxy01'; node = 'pve'; template = 0 }
    )
    $script:Live = @{ '100' = 'running'; '101' = 'stopped'; '102' = 'stopped'; '9000' = 'stopped'; '200' = 'running'; '201' = 'stopped' }
    $script:Cached = $script:Live.Clone()
    $script:FailTasks = $false
    $script:Fake.Handler = $script:PowerHandler
    $null = Connect-PVE -Server pve -User root@pam -Password 'x'
    $script:Fake.Calls.Clear()
  }

  $script:PowerHandler = {
    param($Method, $Path, $Call)
    if ($Path -eq '/access/ticket') { return New-FakeResponse -Data @{ ticket = 'PVE:root@pam:AAAA::sig'; CSRFPreventionToken = 'AAAA:csrf'; username = 'root@pam' } }
    if ($Path -eq '/version') { return New-FakeResponse -Data @{ version = '9.2.1'; release = '9.2' } }
    if ($Path -eq '/cluster/resources') {
      $data = foreach ($g in $script:Guests) { $g + @{ status = $script:Cached[[string]$g.vmid] } }
      return New-FakeResponse -Data @($data)
    }
    if ($Path -match '^/nodes/pve/(qemu|lxc)/(\d+)/status/current$') {
      $live = $script:Live[$Matches[2]]
      return New-FakeResponse -Data @{ vmid = [int]$Matches[2]; status = $live; uptime = $(if ($live -eq 'running') { 42 } else { 0 }) }
    }
    if ($Method -eq 'POST' -and $Path -match '^/nodes/pve/(qemu|lxc)/(\d+)/status/(\w+)$') {
      $vmid = $Matches[2]
      $action = $Matches[3]
      $script:Live[$vmid] = switch ($action) {
        'start' { 'running' }
        'stop' { 'stopped' }
        'shutdown' { 'stopped' }
        'suspend' { if ($Call.Body -match 'todisk=1') { 'stopped' } else { 'running' } }
        default { 'running' }
      }
      return New-FakeResponse -Data "UPID:pve:0000A1B2:00C3D4E5:6700000$($vmid.Length):$action`:$vmid`:root@pam:"
    }
    if ($Path -match '^/nodes/pve/tasks/(.+)/status$') {
      $upid = [uri]::UnescapeDataString($Matches[1])
      $parts = $upid -split ':'
      $exit = if ($script:FailTasks) { "command failed for $($parts[6])" } else { 'OK' }
      return New-FakeResponse -Data @{ upid = $upid; node = 'pve'; status = 'stopped'; exitstatus = $exit; type = $parts[5]; id = $parts[6]; user = 'root@pam' }
    }
    New-FakeResponse -Status 501 -Reason "Unexpected $Method $Path in test" -Data $null
  }

  function Get-PowerPost {
    @($script:Fake.Calls | Where-Object { $_.Method -eq 'POST' -and $_.Path -match '/status/' })
  }

  function Invoke-Streams {
    param([scriptblock]$ScriptBlock)
    $all = @(& $ScriptBlock 2>&1 3>&1)
    [pscustomobject]@{
      Output   = @($all | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] -and $_ -isnot [System.Management.Automation.WarningRecord] })
      Errors   = @($all | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
      Warnings = @($all | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    }
  }
}

Describe 'Confirmation level' {
  It '<Command> has ConfirmImpact <Impact>' -ForEach @(
    @{ Command = 'Start-PVEVM'; Impact = 'Medium' }
    @{ Command = 'Resume-PVEVM'; Impact = 'Medium' }
    @{ Command = 'Start-PVEContainer'; Impact = 'Medium' }
    @{ Command = 'Stop-PVEVM'; Impact = 'High' }
    @{ Command = 'Stop-PVEVMGuest'; Impact = 'High' }
    @{ Command = 'Restart-PVEVM'; Impact = 'High' }
    @{ Command = 'Restart-PVEVMGuest'; Impact = 'High' }
    @{ Command = 'Suspend-PVEVM'; Impact = 'High' }
    @{ Command = 'Stop-PVEContainer'; Impact = 'High' }
    @{ Command = 'Stop-PVEContainerGuest'; Impact = 'High' }
    @{ Command = 'Restart-PVEContainer'; Impact = 'High' }
  ) {
    $metadata = [System.Management.Automation.CommandMetadata]::new((Get-Command $Command))
    $metadata.SupportsShouldProcess | Should -BeTrue
    [string]$metadata.ConfirmImpact | Should -Be $Impact
  }
}

Describe 'Action mapping' {
  BeforeEach {
    Initialize-Power
  }

  It '<Command> -VMId <VMId> POSTs <Expected>' -ForEach @(
    @{ Command = 'Start-PVEVM'; VMId = 101; Expected = '/nodes/pve/qemu/101/status/start' }
    @{ Command = 'Stop-PVEVM'; VMId = 100; Expected = '/nodes/pve/qemu/100/status/stop' }
    @{ Command = 'Stop-PVEVMGuest'; VMId = 100; Expected = '/nodes/pve/qemu/100/status/shutdown' }
    @{ Command = 'Restart-PVEVM'; VMId = 100; Expected = '/nodes/pve/qemu/100/status/reset' }
    @{ Command = 'Restart-PVEVMGuest'; VMId = 100; Expected = '/nodes/pve/qemu/100/status/reboot' }
    @{ Command = 'Suspend-PVEVM'; VMId = 100; Expected = '/nodes/pve/qemu/100/status/suspend' }
    @{ Command = 'Resume-PVEVM'; VMId = 100; Expected = '/nodes/pve/qemu/100/status/resume' }
    @{ Command = 'Start-PVEContainer'; VMId = 201; Expected = '/nodes/pve/lxc/201/status/start' }
    @{ Command = 'Stop-PVEContainer'; VMId = 200; Expected = '/nodes/pve/lxc/200/status/stop' }
    @{ Command = 'Stop-PVEContainerGuest'; VMId = 200; Expected = '/nodes/pve/lxc/200/status/shutdown' }
    @{ Command = 'Restart-PVEContainer'; VMId = 200; Expected = '/nodes/pve/lxc/200/status/reboot' }
  ) {
    $null = & $Command -VMId $VMId -Confirm:$false
    $posts = Get-PowerPost
    $posts.Count | Should -Be 1
    $posts[0].Path | Should -Be $Expected
    $posts[0].Headers['CSRFPreventionToken'] | Should -Be 'AAAA:csrf'
  }
}

Describe 'Start-PVEVM' {
  BeforeEach {
    Initialize-Power
  }

  It 'starts, waits for the task, and writes the VM with its live status' {
    $vm = Start-PVEVM -VMId 101
    $vm.VMId | Should -Be 101
    $vm.Status | Should -Be 'running'
    $vm.Uptime | Should -Be ([timespan]::FromSeconds(42))
    $vm.PSObject.TypeNames | Should -Contain 'PVEPS.VM'
    @($script:Fake.Calls | Where-Object Path -Like '/nodes/pve/tasks/*').Count | Should -BeGreaterThan 0
  }

  It 'decides on the live status, not the cached /cluster/resources status' {
    $script:Cached['101'] = 'running'
    $vm = Start-PVEVM -VMId 101
    (Get-PowerPost).Count | Should -Be 1
    $vm.Status | Should -Be 'running'
  }

  It 'skips a running VM with a warning, makes no POST, and writes the VM unchanged' {
    $r = Invoke-Streams { Start-PVEVM -VMId 100 }
    (Get-PowerPost).Count | Should -Be 0
    $r.Warnings.Count | Should -Be 1
    $r.Warnings[0].Message | Should -Be 'VM 100 (web01) on pve is already running; skipped start.'
    $r.Output.VMId | Should -Be 100
  }

  It 'makes no POST under -WhatIf' {
    Start-PVEVM -VMId 101 -WhatIf
    (Get-PowerPost).Count | Should -Be 0
  }

  It 'resolves names with wildcards, in VMId order' {
    $vms = @(Start-PVEVM -Name 'db*')
    (Get-PowerPost).Path | Should -Be @('/nodes/pve/qemu/101/status/start', '/nodes/pve/qemu/102/status/start')
    $vms.VMId | Should -Be @(101, 102)
  }

  It 'acts once on a guest named twice' {
    $null = Start-PVEVM -VMId 101, 101
    (Get-PowerPost).Count | Should -Be 1
  }

  It 'refuses a container ID with a hint and makes no POST' {
    $r = Invoke-Streams { Start-PVEVM -VMId 201 }
    (Get-PowerPost).Count | Should -Be 0
    $r.Errors[0].Exception.Message | Should -Be "VM with ID '201' was not found on pve. It is a container; use the *-PVEContainer cmdlets."
  }

  It 'refuses a container name with a hint' {
    $r = Invoke-Streams { Start-PVEVM -Name 'proxy01' }
    $r.Errors[0].Exception.Message | Should -BeLike '*It is a container; use the *-PVEContainer cmdlets.'
  }

  It 'refuses a template' {
    $r = Invoke-Streams { Start-PVEVM -VMId 9000 }
    (Get-PowerPost).Count | Should -Be 0
    $r.Errors[0].FullyQualifiedErrorId | Should -Be 'PVEGuestIsTemplate,Start-PVEVM'
  }

  It 'reports an unknown ID and still acts on the known one' {
    $r = Invoke-Streams { Start-PVEVM -VMId 555, 101 }
    $r.Errors.Count | Should -Be 1
    $r.Errors[0].Exception.Message | Should -Be "VM with ID '555' was not found on pve."
    (Get-PowerPost).Count | Should -Be 1
  }

  It 'returns tasks without waiting with -RunAsync' {
    $tasks = @(Start-PVEVM -VMId 101, 102 -RunAsync)
    $tasks.Count | Should -Be 2
    $tasks | ForEach-Object { $_.PSObject.TypeNames | Should -Contain 'PVEPS.Task' }
    $tasks[0].Upid | Should -BeLike 'UPID:pve:*:start:101:*'
    $tasks[0].Connection.Server | Should -Be 'pve'
  }

  It 'reports a failed task as an error and writes no VM for it' {
    $script:FailTasks = $true
    $r = Invoke-Streams { Start-PVEVM -VMId 101 }
    $r.Output.Count | Should -Be 0
    $r.Errors.Count | Should -Be 1
    $r.Errors[0].Exception.Message | Should -BeLike '*failed: command failed for 101'
  }

  It 'waits for several VMs together and writes each' {
    $vms = @(Start-PVEVM -VMId 101, 102)
    $vms.VMId | Should -Be @(101, 102)
    $vms.Status | Should -Be @('running', 'running')
  }
}

Describe 'Stop and other actions' {
  BeforeEach {
    Initialize-Power
  }

  It 'acts on piped VMs, skipping those already stopped' {
    $r = Invoke-Streams { Get-PVEVM | Stop-PVEVM -Confirm:$false }
    (Get-PowerPost).Path | Should -Be @('/nodes/pve/qemu/100/status/stop')
    $r.Warnings.Count | Should -Be 2
    @($r.Output | Where-Object VMId -EQ 100)[0].Status | Should -Be 'stopped'
  }

  It 'sends overrule-shutdown with Stop-PVEVM -OverruleShutdown' {
    $null = Stop-PVEVM -VMId 100 -OverruleShutdown -Confirm:$false
    (Get-PowerPost)[0].Body | Should -Be 'overrule-shutdown=1'
  }

  It 'sends timeout and forceStop with Stop-PVEVMGuest' {
    $null = Stop-PVEVMGuest -VMId 100 -TimeoutSec 30 -ForceStop -Confirm:$false
    (Get-PowerPost)[0].Body | Should -Be 'forceStop=1&timeout=30'
  }

  It 'sends no body for Stop-PVEVMGuest without options' {
    $null = Stop-PVEVMGuest -VMId 100 -Confirm:$false
    (Get-PowerPost)[0].Body | Should -BeNullOrEmpty
  }

  It 'sends timeout with Restart-PVEVMGuest' {
    $null = Restart-PVEVMGuest -VMId 100 -TimeoutSec 90 -Confirm:$false
    (Get-PowerPost)[0].Body | Should -Be 'timeout=90'
  }

  It 'hibernates with Suspend-PVEVM -ToDisk -StateStorage' {
    $vm = Suspend-PVEVM -VMId 100 -ToDisk -StateStorage local-lvm -Confirm:$false
    (Get-PowerPost)[0].Body | Should -Be 'statestorage=local-lvm&todisk=1'
    $vm.Status | Should -Be 'stopped'
  }

  It 'rejects -StateStorage without -ToDisk before doing anything' {
    { Suspend-PVEVM -VMId 100 -StateStorage local-lvm -Confirm:$false } | Should -Throw '*only applies with -ToDisk*'
    $script:Fake.Calls.Count | Should -Be 0
  }

  It 'skips stopping a stopped VM with a warning' {
    $r = Invoke-Streams { Stop-PVEVMGuest -VMId 101 -Confirm:$false }
    (Get-PowerPost).Count | Should -Be 0
    $r.Warnings[0].Message | Should -Be 'VM 101 (db01) on pve is stopped; skipped shut down guest os.'
  }

  It 'sends Resume-PVEVM regardless of status and lets PVE decide' {
    $null = Resume-PVEVM -VMId 101 -Confirm:$false
    (Get-PowerPost).Count | Should -Be 1
  }
}

Describe 'Container power' {
  BeforeEach {
    Initialize-Power
  }

  It 'starts a container and writes it with its live status' {
    $ct = Start-PVEContainer -Name proxy01
    $ct.PSObject.TypeNames | Should -Contain 'PVEPS.Container'
    $ct.Status | Should -Be 'running'
  }

  It 'refuses a VM ID with a hint' {
    $r = Invoke-Streams { Stop-PVEContainer -VMId 100 -Confirm:$false }
    (Get-PowerPost).Count | Should -Be 0
    $r.Errors[0].Exception.Message | Should -Be "Container with ID '100' was not found on pve. It is a VM; use the *-PVEVM cmdlets."
  }

  It 'sends timeout and forceStop with Stop-PVEContainerGuest' {
    $null = Stop-PVEContainerGuest -VMId 200 -TimeoutSec 15 -ForceStop -Confirm:$false
    (Get-PowerPost)[0].Body | Should -Be 'forceStop=1&timeout=15'
  }

  It 'accepts piped container objects' {
    $null = Get-PVEContainer -Name dns01 | Restart-PVEContainer -Confirm:$false
    (Get-PowerPost).Path | Should -Be @('/nodes/pve/lxc/200/status/reboot')
  }
}
