#Requires -Modules Pester
# Integration tests for the Phase 8 statistics and event cmdlets. READ-ONLY.
# They check that the RRD samples and cluster log entries have the fields the module reads, which the API
# schema does not describe. Needs the same environment variables as Connection.Integration.Tests.ps1
# (token variables only).

BeforeDiscovery {
  $script:HaveToken = [bool]($env:PVEPS_TEST_SERVER -and $env:PVEPS_TEST_TOKEN_ID -and $env:PVEPS_TEST_TOKEN_SECRET)
}

BeforeAll {
  Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'PVEPS.psd1') -Force
  if ($env:PVEPS_TEST_SERVER -and $env:PVEPS_TEST_TOKEN_ID -and $env:PVEPS_TEST_TOKEN_SECRET) {
    $token = [pscredential]::new($env:PVEPS_TEST_TOKEN_ID, (ConvertTo-SecureString -String $env:PVEPS_TEST_TOKEN_SECRET -AsPlainText -Force))
    $connect = @{
      Server               = $env:PVEPS_TEST_SERVER
      Port                 = if ($env:PVEPS_TEST_PORT) { [int]$env:PVEPS_TEST_PORT } else { 8006 }
      SkipCertificateCheck = $env:PVEPS_TEST_SKIPCERT -eq '1'
      Credential           = $token
      Token                = $true
    }
    $null = Connect-PVE @connect
  }
}

AfterAll {
  Disconnect-PVE -Server * -Confirm:$false -ErrorAction SilentlyContinue
}

Describe 'Statistics and events against a real server' -Tag 'Integration' -Skip:(-not $script:HaveToken) {
  It 'Get-PVENodeStat returns recent samples with CPU and memory fields' {
    $stats = @(Get-PVENodeStat -ErrorAction Stop)
    $stats.Count | Should -BeGreaterThan 0
    $latest = $stats[-1]
    $latest.Timestamp | Should -BeGreaterThan (Get-Date).AddHours(-2)
    $latest.PSObject.Properties.Name | Should -Contain 'cpu'
    @($latest.PSObject.Properties.Name | Where-Object { $_ -like 'mem*' }).Count | Should -BeGreaterThan 0
  }

  It 'Get-PVEVMStat returns samples for a running VM, if there is one' {
    $vm = Get-PVEVM | Where-Object Status -EQ 'running' | Select-Object -First 1
    if (-not $vm) {
      Set-ItResult -Skipped -Because 'no running VM'
      return
    }
    $stats = @($vm | Get-PVEVMStat -Metric cpu -ErrorAction Stop)
    $stats.Count | Should -BeGreaterThan 0
    $stats[-1].PSObject.Properties.Name | Should -Contain 'cpu'
  }

  It 'Get-PVEStorageStat returns samples for an active storage' {
    $stats = @(Get-PVEStorageStat -ErrorAction Stop -WarningAction SilentlyContinue)
    $stats.Count | Should -BeGreaterThan 0
    $stats[0].Storage | Should -Not -BeNullOrEmpty
  }

  It 'Get-PVEEvent returns cluster log entries with time, node and message' {
    $events = @(Get-PVEEvent -MaxEntries 20 -ErrorAction Stop)
    $events.Count | Should -BeGreaterThan 0
    @($events | Where-Object { $_.Time -and $_.Node -and $_.Message }).Count | Should -Be $events.Count
  }
}
