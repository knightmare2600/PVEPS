#Requires -Modules Pester
# Phase 8 statistics and event cmdlets. HTTP is mocked (see TestHelpers.ps1); nothing here touches a real
# server.

BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

  function Initialize-Stats {
    Reset-FakeState
    $script:Fake.Handler = $script:StatsHandler
    $null = Connect-PVE -Server pve -User root@pam -Password 'x'
    $script:Fake.Calls.Clear()
  }

  $script:Samples = @(
    @{ time = 1700000000; cpu = 0.25; maxcpu = 2; mem = 1GB; maxmem = 2GB; netin = 100; netout = 50 }
    @{ time = 1700000060 }
    @{ time = 1700000120; cpu = 0.5; maxcpu = 2; mem = 1.5GB; maxmem = 2GB; netin = 200; netout = 70 }
  )

  $script:StatsHandler = {
    param($Method, $Path, $Call)
    if ($Path -eq '/access/ticket') { return New-FakeResponse -Data @{ ticket = 'PVE:root@pam:AAAA::sig'; CSRFPreventionToken = 'AAAA:csrf'; username = 'root@pam' } }
    if ($Path -eq '/version') { return New-FakeResponse -Data @{ version = '9.2.1'; release = '9.2' } }
    if ($Path -eq '/nodes') { return New-FakeResponse -Data @(@{ node = 'pve'; status = 'online' }, @{ node = 'pve2'; status = 'offline' }) }
    if ($Path -eq '/nodes/pve/status') { return New-FakeResponse -Data @{} }
    if ($Path -eq '/nodes/pve/storage') { return New-FakeResponse -Data @(@{ storage = 'local'; type = 'dir'; content = 'iso'; active = 1 }, @{ storage = 'nas'; type = 'nfs'; content = 'backup'; active = 0 }) }
    if ($Path -eq '/cluster/resources') {
      return New-FakeResponse -Data @(@{ type = 'qemu'; vmid = 100; name = 'web01'; node = 'pve'; status = 'running'; template = 0 }, @{ type = 'lxc'; vmid = 200; name = 'dns01'; node = 'pve'; status = 'running'; template = 0 })
    }
    if ($Path -match '/rrddata$') { return New-FakeResponse -Data $script:Samples }
    if ($Path -eq '/cluster/log') {
      return New-FakeResponse -Data @(
        @{ time = 1700000000; node = 'pve'; user = 'root@pam'; tag = 'pvedaemon'; pri = 6; msg = "successful auth for user 'root@pam'`n"; uid = 1 }
        @{ time = 1700000300; node = 'pve'; user = 'pveps@pve!write'; tag = 'pvedaemon'; pri = 6; msg = 'starting task UPID:pve:...:qmstart:100:'; uid = 2 }
        @{ time = 1700000100; node = 'pve'; user = 'eve@pve'; tag = 'pvedaemon'; pri = 3; msg = "authentication failure; rhost=::ffff:192.0.2.66 user=eve@pve"; uid = 3 }
      )
    }
    New-FakeResponse -Status 501 -Reason "Unexpected $Method $Path in test" -Data $null
  }

  function Get-Request {
    param([string]$Method, [string]$PathPattern)
    @($script:Fake.Calls | Where-Object { $_.Method -eq $Method -and $_.Path -match $PathPattern })
  }
}

Describe 'Get-PVEVMStat and Get-PVEContainerStat' {
  BeforeEach {
    Initialize-Stats
  }

  It 'writes one object per sample, skipping gaps, with the fields passed through' {
    $stats = @(Get-PVEVMStat -VMId 100)
    $stats.Count | Should -Be 2
    $stats[0].PSObject.TypeNames | Should -Contain 'PVEPS.Stat'
    $stats[0].Timestamp | Should -Be ([DateTimeOffset]::FromUnixTimeSeconds(1700000000).LocalDateTime)
    $stats[0].cpu | Should -Be 0.25
    $stats[0].mem | Should -Be 1GB
    $stats[0].VMName | Should -Be 'web01'
    $stats[0].Entity | Should -Be 'VM 100 (web01) on pve'
    $query = (Get-Request GET '^/nodes/pve/qemu/100/rrddata$')[0].Query
    $query | Should -Be 'timeframe=hour'
  }

  It 'sends the time frame and consolidation function, and keeps only -Metric fields' {
    $stats = @(Get-PVEVM web01 | Get-PVEVMStat -Timeframe week -Consolidation Max -Metric 'net*')
    (Get-Request GET 'rrddata$')[0].Query | Should -Be 'cf=MAX&timeframe=week'
    $names = @($stats[0].PSObject.Properties.Name)
    $names | Should -Contain 'netin'
    $names | Should -Contain 'netout'
    $names | Should -Not -Contain 'cpu'
  }

  It 'filters samples by -Start and -Finish' {
    $at = [DateTimeOffset]::FromUnixTimeSeconds(1700000120).LocalDateTime
    @(Get-PVEVMStat -VMId 100 -Start $at).Count | Should -Be 1
    @(Get-PVEVMStat -VMId 100 -Finish $at.AddSeconds(-1)).Count | Should -Be 1
  }

  It 'reads container statistics from the lxc endpoint' {
    $null = Get-PVEContainerStat -VMId 200
    (Get-Request GET '^/nodes/pve/lxc/200/rrddata$').Count | Should -Be 1
  }
}

Describe 'Get-PVENodeStat and Get-PVEStorageStat' {
  BeforeEach {
    Initialize-Stats
  }

  It 'reads every online node and warns about offline ones' {
    $warnings = $null
    $stats = @(Get-PVENodeStat -Timeframe decade -WarningVariable warnings -WarningAction SilentlyContinue)
    $stats.Count | Should -Be 2
    $stats[0].Node | Should -Be 'pve'
    (Get-Request GET '^/nodes/pve/rrddata$')[0].Query | Should -Be 'timeframe=decade'
    $warnings[0].Message | Should -BeLike '*pve2 is offline*'
  }

  It 'reads active storages and skips inactive ones with a warning' {
    $warnings = $null
    $stats = @(Get-PVEStorageStat -WarningVariable warnings -WarningAction SilentlyContinue)
    $stats[0].Storage | Should -Be 'local'
    (Get-Request GET '/storage/local/rrddata$').Count | Should -Be 1
    (Get-Request GET '/storage/nas/rrddata$').Count | Should -Be 0
    $warnings[0].Message | Should -BeLike '*nas on pve is not active*'
  }
}

Describe 'Get-PVEEvent' {
  BeforeEach {
    Initialize-Stats
  }

  It 'writes the cluster log newest first, with the fields mapped' {
    $events = @(Get-PVEEvent -MaxEntries 50)
    (Get-Request GET '^/cluster/log$')[0].Query | Should -Be 'max=50'
    $events.Count | Should -Be 3
    $events[0].PSObject.TypeNames | Should -Contain 'PVEPS.Event'
    $events[0].User | Should -Be 'pveps@pve!write'
    $events[2].Message | Should -Be "successful auth for user 'root@pam'"
    $events[1].Severity | Should -Be 3
    $events[1].Tag | Should -Be 'pvedaemon'
  }

  It 'filters by time, user and message' {
    @(Get-PVEEvent -Start ([DateTimeOffset]::FromUnixTimeSeconds(1700000100).LocalDateTime)).Count | Should -Be 2
    (Get-PVEEvent -User 'eve@*').Message | Should -BeLike 'authentication failure*'
    @(Get-PVEEvent -Message '*task*').Count | Should -Be 1
  }
}
