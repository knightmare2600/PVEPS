#Requires -Modules Pester
# Integration tests for the Phase 1 inventory cmdlets. READ-ONLY.
# Each cmdlet's result is cross-checked against a second API source (the per-node endpoints), so the
# tests do not depend on what guests exist on the server.
# Needs the same environment variables as Connection.Integration.Tests.ps1 (token variables only).

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
    $script:NodeNames = @(Invoke-PVEApi -Path /nodes -ErrorAction Stop | Where-Object status -EQ 'online' | ForEach-Object node)
  }
}

AfterAll {
  Disconnect-PVE -Server * -Confirm:$false -ErrorAction SilentlyContinue
}

Describe 'Inventory against a real server' -Tag 'Integration' -Skip:(-not $script:HaveToken) {
  It 'Get-PVENode returns every online node with version details' {
    $nodes = @(Get-PVENode -ErrorAction Stop | Where-Object Status -EQ 'online')
    @($nodes.Name | Sort-Object) | Should -Be @($script:NodeNames | Sort-Object)
    foreach ($node in $nodes) {
      $node.Version | Should -Match '^pve-manager/9\.'
      $node.Kernel | Should -Not -BeNullOrEmpty
      $node.Cpus | Should -BeGreaterThan 0
      $node.MemoryTotalGB | Should -BeGreaterThan 0
    }
  }

  It 'Get-PVEVM (from /cluster/resources) agrees with /nodes/{node}/qemu' {
    $expected = foreach ($node in $script:NodeNames) {
      Invoke-PVEApi -Path "/nodes/$node/qemu" -ErrorAction Stop | ForEach-Object { [int]$_.vmid }
    }
    $actual = @(Get-PVEVM -IncludeTemplate -ErrorAction Stop | ForEach-Object VMId)
    @($actual | Sort-Object) | Should -Be @($expected | Sort-Object)
  }

  It 'Get-PVEVM leaves out exactly the templates' {
    $all = @(Get-PVEVM -IncludeTemplate -ErrorAction Stop)
    $plain = @(Get-PVEVM -ErrorAction Stop)
    $plain.Count | Should -Be @($all | Where-Object { -not $_.IsTemplate }).Count
  }

  It 'Get-PVEContainer agrees with /nodes/{node}/lxc' {
    $expected = foreach ($node in $script:NodeNames) {
      Invoke-PVEApi -Path "/nodes/$node/lxc" -ErrorAction Stop | ForEach-Object { [int]$_.vmid }
    }
    $actual = @(Get-PVEContainer -IncludeTemplate -ErrorAction Stop | ForEach-Object VMId)
    @($actual | Sort-Object) | Should -Be @($expected | Sort-Object)
  }

  It 'Get-PVEVM by ID returns the same object as the full listing' {
    $first = Get-PVEVM -IncludeTemplate -ErrorAction Stop | Select-Object -First 1
    if (-not $first) {
      Set-ItResult -Inconclusive -Because 'the server has no VMs'
      return
    }
    $byId = Get-PVEVM -VMId $first.VMId -IncludeTemplate -ErrorAction Stop
    $byId.Name | Should -Be $first.Name
    $byId.Node | Should -Be $first.Node
  }

  It 'Get-PVEVM writes not-found for an ID that does not exist' {
    $used = @(Invoke-PVEApi -Path /cluster/resources -Parameters @{ type = 'vm' } -ErrorAction Stop | ForEach-Object { [int]$_.vmid })
    $unused = 999999999
    while ($unused -in $used) {
      $unused--
    }
    $errors = @(Get-PVEVM -VMId $unused 2>&1 | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    $errors.Count | Should -Be 1
    $errors[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
  }

  It 'Get-PVEStorage lists active storage with capacity, matching /storage' {
    $storage = @(Get-PVEStorage -ErrorAction Stop)
    $storage.Count | Should -BeGreaterThan 0
    $configured = @(Invoke-PVEApi -Path /storage -ErrorAction Stop | ForEach-Object storage)
    foreach ($item in $storage) {
      $item.Name | Should -BeIn $configured
      if ($item.Active) {
        $item.CapacityGB | Should -BeGreaterThan 0
        $item.FreeGB | Should -Not -BeNullOrEmpty
      }
    }
  }

  It 'Get-PVEStorage -Content images only returns storage that accepts VM disks' {
    $storage = @(Get-PVEStorage -Content images -ErrorAction Stop)
    foreach ($item in $storage) {
      $item.Content | Should -Contain 'images'
    }
  }

  It 'Get-PVEPool runs and its members agree with the pool API' {
    $pools = @(Get-PVEPool -ErrorAction Stop)
    foreach ($pool in $pools) {
      $raw = @(Invoke-PVEApi -Path /pools -Parameters @{ poolid = $pool.Name } -ErrorAction Stop)[0]
      $rawMembers = if ($raw.PSObject.Properties['members']) { @($raw.members) } else { @() }
      @($pool.Members).Count | Should -Be $rawMembers.Count
    }
  }
}
