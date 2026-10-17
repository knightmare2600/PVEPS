#Requires -Modules Pester
# Phase 5 snapshot cmdlets. HTTP is mocked (see TestHelpers.ps1); nothing here touches a real server.
# The fake server keeps a snapshot list per guest, including the 'current' entry PVE returns.

BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  Mock -ModuleName PVEPS Start-Sleep { }

  function Initialize-Snapshot {
    Reset-FakeState
    $script:State = @{
      Guests    = [ordered]@{
        '100' = @{ type = 'qemu'; vmid = 100; name = 'web01'; status = 'running' }
        '101' = @{ type = 'qemu'; vmid = 101; name = 'db01'; status = 'stopped' }
        '200' = @{ type = 'lxc'; vmid = 200; name = 'dns01'; status = 'stopped' }
      }
      Snapshots = @{
        '100' = [System.Collections.Generic.List[hashtable]]@(
          @{ name = 'base'; description = "Fresh install`n"; snaptime = 1700000000 }
          @{ name = 'before-upgrade'; description = ''; snaptime = 1700100000; parent = 'base'; vmstate = 1 }
          @{ name = 'current'; description = 'You are here!'; parent = 'before-upgrade' }
        )
        '101' = [System.Collections.Generic.List[hashtable]]@(@{ name = 'current'; description = 'You are here!' })
        '200' = [System.Collections.Generic.List[hashtable]]@(
          @{ name = 'clean'; description = ''; snaptime = 1700000000 }
          @{ name = 'current'; description = 'You are here!'; parent = 'clean' }
        )
      }
      FailTasks = $false
    }
    $script:Fake.Handler = $script:SnapshotHandler
    $null = Connect-PVE -Server pve -User root@pam -Password 'x'
    $script:Fake.Calls.Clear()
  }

  function ConvertFrom-Body {
    param([string]$Body)
    $result = @{}
    foreach ($pair in ($Body -split '&' | Where-Object { $_ })) {
      $key, $value = $pair -split '=', 2
      $result[[uri]::UnescapeDataString($key)] = [uri]::UnescapeDataString($value)
    }
    $result
  }

  $script:SnapshotHandler = {
    param($Method, $Path, $Call)
    $state = $script:State
    $body = ConvertFrom-Body $Call.Body
    if ($Path -eq '/access/ticket') { return New-FakeResponse -Data @{ ticket = 'PVE:root@pam:AAAA::sig'; CSRFPreventionToken = 'AAAA:csrf'; username = 'root@pam' } }
    if ($Path -eq '/version') { return New-FakeResponse -Data @{ version = '9.2.1'; release = '9.2' } }
    if ($Path -eq '/cluster/resources') {
      return New-FakeResponse -Data @($state.Guests.Values | ForEach-Object { @{ type = $_.type; vmid = $_.vmid; name = $_.name; node = 'pve'; status = $_.status; template = 0 } })
    }
    if ($Path -match '^/nodes/pve/tasks/(.+)/status$') {
      $upid = [uri]::UnescapeDataString($Matches[1])
      $parts = $upid -split ':'
      $exit = if ($state.FailTasks) { 'snapshot feature is not available' } else { 'OK' }
      return New-FakeResponse -Data @{ upid = $upid; node = 'pve'; status = 'stopped'; exitstatus = $exit; type = $parts[5]; id = $parts[6]; user = 'root@pam' }
    }
    if ($Path -notmatch '^/nodes/pve/(qemu|lxc)/(\d+)/(status/current|snapshot)(?:/([^/]+))?(?:/(rollback|config))?$') {
      return New-FakeResponse -Status 501 -Reason "Unexpected $Method $Path in test" -Data $null
    }
    $id = $Matches[2]
    $what = $Matches[3]
    $snap = if ($Matches[4]) { [uri]::UnescapeDataString($Matches[4]) } else { $null }
    $action = $Matches[5]
    $list = $state.Snapshots[$id]
    $upid = "UPID:pve:0000A1B2:00C3D4E5:67000000:qmsnapshot:$id`:root@pam:"
    if ($what -eq 'status/current') { return New-FakeResponse -Data @{ vmid = [int]$id; status = $state.Guests[$id].status; name = $state.Guests[$id].name } }

    $current = $list | Where-Object { $_.name -eq 'current' }
    if ($Method -eq 'GET' -and -not $snap) { return New-FakeResponse -Data @($list) }
    if ($Method -eq 'POST' -and -not $snap) {
      $list.Insert($list.Count - 1, @{ name = $body.snapname; description = [string]$body.description; snaptime = 1700200000; parent = $current.parent; vmstate = [int]$body.vmstate })
      $current.parent = $body.snapname
      return New-FakeResponse -Data $upid
    }
    $entry = $list | Where-Object { $_.name -eq $snap }
    if ($Method -eq 'DELETE') {
      $null = $list.Remove($entry)
      return New-FakeResponse -Data $upid
    }
    if ($action -eq 'rollback') {
      $current.parent = $snap
      if ($body.start -eq '1') { $state.Guests[$id].status = 'running' }
      return New-FakeResponse -Data $upid
    }
    if ($action -eq 'config' -and $Method -eq 'PUT') {
      $entry.description = $body.description
      return New-FakeResponse -Data $null
    }
    New-FakeResponse -Status 501 -Reason "Unexpected $Method $Path in test" -Data $null
  }

  function Get-Request {
    param([string]$Method, [string]$PathPattern)
    @($script:Fake.Calls | Where-Object { $_.Method -eq $Method -and $_.Path -match $PathPattern })
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
    @{ Command = 'New-PVEVMSnapshot'; Impact = 'Medium' }
    @{ Command = 'Set-PVEVMSnapshot'; Impact = 'Medium' }
    @{ Command = 'Remove-PVEVMSnapshot'; Impact = 'High' }
    @{ Command = 'Restore-PVEVMSnapshot'; Impact = 'High' }
    @{ Command = 'New-PVEContainerSnapshot'; Impact = 'Medium' }
    @{ Command = 'Set-PVEContainerSnapshot'; Impact = 'Medium' }
    @{ Command = 'Remove-PVEContainerSnapshot'; Impact = 'High' }
    @{ Command = 'Restore-PVEContainerSnapshot'; Impact = 'High' }
  ) {
    $metadata = [System.Management.Automation.CommandMetadata]::new((Get-Command $Command))
    $metadata.SupportsShouldProcess | Should -BeTrue
    [string]$metadata.ConfirmImpact | Should -Be $Impact
  }
}

Describe 'Get-PVEVMSnapshot' {
  BeforeEach {
    Initialize-Snapshot
  }

  It 'lists snapshots oldest first, without the current entry, and marks the one the VM runs from' {
    $snaps = @(Get-PVEVMSnapshot -VMId 100)
    @($snaps | ForEach-Object { $_.Snapshot }) | Should -Be @('base', 'before-upgrade')
    $snaps[0].PSObject.TypeNames | Should -Contain 'PVEPS.Snapshot'
    $snaps[0].Description | Should -Be 'Fresh install'
    $snaps[0].Created | Should -Be ([DateTimeOffset]::FromUnixTimeSeconds(1700000000).LocalDateTime)
    $snaps[0].IsCurrent | Should -BeFalse
    $snaps[1].IsCurrent | Should -BeTrue
    $snaps[1].Parent | Should -Be 'base'
    $snaps[1].IncludesMemory | Should -BeTrue
    $snaps[0].IncludesMemory | Should -BeFalse
  }

  It 'returns nothing for a VM without snapshots, and filters by name' {
    Get-PVEVMSnapshot -VMId 101 | Should -BeNullOrEmpty
    (Get-PVEVM web01 | Get-PVEVMSnapshot -Snapshot 'before*').Snapshot | Should -Be 'before-upgrade'
  }

  It 'reports a named snapshot that does not exist' {
    $r = Invoke-Streams { Get-PVEVMSnapshot -VMId 100 -Snapshot nope }
    $r.Errors[0].Exception.Message | Should -Be "VM 100 (web01) on pve snapshot 'nope' was not found on pve."
  }

  It 'gets container snapshots with Get-PVEContainerSnapshot' {
    (Get-PVEContainerSnapshot -VMId 200).Snapshot | Should -Be 'clean'
  }
}

Describe 'New-PVEVMSnapshot' {
  BeforeEach {
    Initialize-Snapshot
  }

  It 'takes a snapshot with the options, waits, and writes it' {
    $snap = New-PVEVMSnapshot -VMId 100 -Snapshot nightly -Description 'Nightly' -IncludeMemory
    $calls = Get-Request POST '^/nodes/pve/qemu/100/snapshot$'
    $calls.Count | Should -Be 1
    $body = ConvertFrom-Body $calls[0].Body
    $body.snapname | Should -Be 'nightly'
    $body.description | Should -Be 'Nightly'
    $body.vmstate | Should -Be '1'
    $snap.Snapshot | Should -Be 'nightly'
    $snap.IsCurrent | Should -BeTrue
    (Get-Request GET '/tasks/').Count | Should -BeGreaterThan 0
  }

  It 'snapshots several VMs at once' {
    $snaps = @(Get-PVEVM 'web01', 'db01' | New-PVEVMSnapshot -Snapshot pre-patch)
    $snaps.Count | Should -Be 2
    (Get-Request POST '/snapshot$').Count | Should -Be 2
  }

  It 'writes an error and no snapshot when the task fails' {
    $script:State.FailTasks = $true
    $r = Invoke-Streams { New-PVEVMSnapshot -VMId 101 -Snapshot x }
    $r.Errors[0].FullyQualifiedErrorId | Should -BeLike 'PVETaskFailed*'
    $r.Output.Count | Should -Be 0
  }

  It 'takes a container snapshot without vmstate' {
    $null = New-PVEContainerSnapshot -VMId 200 -Snapshot x
    (ConvertFrom-Body (Get-Request POST '^/nodes/pve/lxc/200/snapshot$')[0].Body).ContainsKey('vmstate') | Should -BeFalse
  }

  It 'returns the task with -RunAsync, and sends nothing under -WhatIf' {
    (New-PVEVMSnapshot -VMId 101 -Snapshot x -RunAsync).PSObject.TypeNames | Should -Contain 'PVEPS.Task'
    $script:Fake.Calls.Clear()
    New-PVEVMSnapshot -VMId 101 -Snapshot y -WhatIf
    (Get-Request POST '.*').Count | Should -Be 0
  }
}

Describe 'Set-, Remove- and Restore-PVEVMSnapshot' {
  BeforeEach {
    Initialize-Snapshot
  }

  It 'Set-PVEVMSnapshot changes the description with PUT .../config' {
    $snap = Set-PVEVMSnapshot -VMId 100 -Snapshot base -Description 'Golden'
    $calls = Get-Request PUT '^/nodes/pve/qemu/100/snapshot/base/config$'
    $calls.Count | Should -Be 1
    (ConvertFrom-Body $calls[0].Body).description | Should -Be 'Golden'
    $snap.Description | Should -Be 'Golden'
  }

  It 'Remove-PVEVMSnapshot deletes piped snapshots and writes nothing' {
    $out = Get-PVEVMSnapshot -VMId 100 | Remove-PVEVMSnapshot -Confirm:$false
    $out | Should -BeNullOrEmpty
    @(Get-Request DELETE '^/nodes/pve/qemu/100/snapshot/').Count | Should -Be 2
    Get-PVEVMSnapshot -VMId 100 | Should -BeNullOrEmpty
  }

  It 'Remove-PVEVMSnapshot -Force sends force=1, and -WhatIf sends nothing' {
    Remove-PVEVMSnapshot -VMId 100 -Snapshot base -WhatIf
    (Get-Request DELETE '.*').Count | Should -Be 0
    Remove-PVEVMSnapshot -VMId 100 -Snapshot base -Force -Confirm:$false
    (ConvertFrom-Body (Get-Request DELETE '/snapshot/base$')[0].Query).force | Should -Be '1'
  }

  It 'Restore-PVEVMSnapshot rolls back and writes the VM with its live status' {
    $vm = Restore-PVEVMSnapshot -VMId 101 -Snapshot x -Confirm:$false -ErrorAction SilentlyContinue
    $vm | Should -BeNullOrEmpty
    Initialize-Snapshot
    $vm = Restore-PVEVMSnapshot -VMId 100 -Snapshot base -Confirm:$false
    (Get-Request POST '^/nodes/pve/qemu/100/snapshot/base/rollback$').Count | Should -Be 1
    $vm.PSObject.TypeNames | Should -Contain 'PVEPS.VM'
    (Get-PVEVMSnapshot -VMId 100 | Where-Object IsCurrent).Snapshot | Should -Be 'base'
  }

  It 'Restore-PVEContainerSnapshot -PowerOn sends start=1' {
    $ct = Restore-PVEContainerSnapshot -VMId 200 -Snapshot clean -PowerOn -Confirm:$false
    (ConvertFrom-Body (Get-Request POST 'rollback$')[0].Body).start | Should -Be '1'
    $ct.Status | Should -Be 'running'
  }

  It 'Restore refuses a pattern that matches several snapshots of one VM' {
    $r = Invoke-Streams { Restore-PVEVMSnapshot -VMId 100 -Snapshot '*' -Confirm:$false }
    $r.Errors[0].Exception.Message | Should -BeLike '*2 snapshots match (base, before-upgrade); roll back to exactly one.*'
    (Get-Request POST '.*').Count | Should -Be 0
  }

  It 'escapes the snapshot name in the path' {
    $script:State.Snapshots['101'].Insert(0, @{ name = 'a_b-c'; description = ''; snaptime = 1 })
    Remove-PVEVMSnapshot -VMId 101 -Snapshot a_b-c -Confirm:$false
    (Get-Request DELETE '.*')[0].Path | Should -Be '/nodes/pve/qemu/101/snapshot/a_b-c'
  }
}
