#Requires -Modules Pester
# Integration tests against a real Proxmox VE server. READ-ONLY: nothing here creates, changes or
# deletes anything on the server.
#
# Skipped unless these environment variables are set:
#   PVEPS_TEST_SERVER        host name or IP of the PVE node
#   PVEPS_TEST_TOKEN_ID      full token ID, e.g. pveps@pve!readonly
#   PVEPS_TEST_TOKEN_SECRET  token secret
# Optional:
#   PVEPS_TEST_PORT          API port (default 8006)
#   PVEPS_TEST_SKIPCERT      1 to skip TLS certificate validation
#   PVEPS_TEST_USER          user@realm for the ticket-authentication tests
#   PVEPS_TEST_PASSWORD      password for PVEPS_TEST_USER
#
# Run: Invoke-Pester ./tests -TagFilter Integration -Output Detailed

BeforeDiscovery {
  $script:HaveToken = [bool]($env:PVEPS_TEST_SERVER -and $env:PVEPS_TEST_TOKEN_ID -and $env:PVEPS_TEST_TOKEN_SECRET)
  $script:HaveUser = [bool]($env:PVEPS_TEST_SERVER -and $env:PVEPS_TEST_USER -and $env:PVEPS_TEST_PASSWORD)
}

BeforeAll {
  Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'PVEPS.psd1') -Force

  $script:Common = @{
    Server               = $env:PVEPS_TEST_SERVER
    Port                 = if ($env:PVEPS_TEST_PORT) { [int]$env:PVEPS_TEST_PORT } else { 8006 }
    SkipCertificateCheck = $env:PVEPS_TEST_SKIPCERT -eq '1'
  }
}

Describe 'API token connection' -Tag 'Integration' -Skip:(-not $script:HaveToken) {
  BeforeAll {
    $token = [pscredential]::new($env:PVEPS_TEST_TOKEN_ID, (ConvertTo-SecureString -String $env:PVEPS_TEST_TOKEN_SECRET -AsPlainText -Force))
    $script:Conn = Connect-PVE @script:Common -Credential $token -Token
  }

  AfterAll {
    Disconnect-PVE -Server * -Confirm:$false
  }

  It 'connects and reports a 9.x release' {
    $script:Conn.IsConnected | Should -BeTrue
    $script:Conn.AuthType | Should -Be 'ApiToken'
    $script:Conn.Release | Should -Match '^9\.'
  }

  It 'reads the node list through Invoke-PVEApi' {
    $nodes = @(Invoke-PVEApi -Path /nodes -ErrorAction Stop)
    $nodes.Count | Should -BeGreaterThan 0
    $nodes[0].node | Should -Not -BeNullOrEmpty
  }

  It 'lists cluster tasks as PVEPS.Task objects with a State' {
    $tasks = @(Get-PVETask -ErrorAction Stop)
    if ($tasks.Count -eq 0) {
      Set-ItResult -Inconclusive -Because 'the server has no recent tasks to list'
      return
    }
    $tasks[0].PSObject.TypeNames | Should -Contain 'PVEPS.Task'
    $tasks.State | Should -Not -Contain $null
    $tasks | ForEach-Object { $_.Upid | Should -Match '^UPID:' }
  }

  It 'reads a node task list and agrees with the status endpoint for a finished task' {
    $node = @(Invoke-PVEApi -Path /nodes -ErrorAction Stop)[0].node
    $finished = @(Get-PVETask -Node $node -Limit 20 -ErrorAction Stop | Where-Object State -EQ 'Stopped')
    if ($finished.Count -eq 0) {
      Set-ItResult -Inconclusive -Because "node $node has no finished tasks"
      return
    }
    $fromStatus = Get-PVETask -Upid $finished[0].Upid -ErrorAction Stop
    $fromStatus.State | Should -Be 'Stopped'
    $fromStatus.ExitStatus | Should -Be $finished[0].ExitStatus
    $fromStatus.Node | Should -Be $node
  }

  It 'returns at once from Wait-PVETask for a finished task' {
    $node = @(Invoke-PVEApi -Path /nodes -ErrorAction Stop)[0].node
    $ok = @(Get-PVETask -Node $node -Limit 50 -ErrorAction Stop | Where-Object { $_.State -eq 'Stopped' -and $_.ExitStatus -eq 'OK' })
    if ($ok.Count -eq 0) {
      Set-ItResult -Inconclusive -Because "node $node has no finished OK tasks"
      return
    }
    $elapsed = Measure-Command { $script:Waited = $ok[0] | Wait-PVETask -TimeoutSec 30 -ErrorAction Stop }
    $script:Waited.Succeeded | Should -BeTrue
    $elapsed.TotalSeconds | Should -BeLessThan 10
  }

  It 'raises a PVE error for a node that does not exist' {
    { Invoke-PVEApi -Path /nodes/pveps-no-such-node/status -ErrorAction Stop } | Should -Throw '*failed with HTTP*'
  }
}

Describe 'Ticket connection' -Tag 'Integration' -Skip:(-not $script:HaveUser) {
  BeforeAll {
    $credential = [pscredential]::new($env:PVEPS_TEST_USER, (ConvertTo-SecureString -String $env:PVEPS_TEST_PASSWORD -AsPlainText -Force))
    $script:Conn = Connect-PVE @script:Common -Credential $credential
  }

  AfterAll {
    Disconnect-PVE -Server * -Confirm:$false
  }

  It 'connects with a ticket' {
    $script:Conn.AuthType | Should -Be 'Ticket'
    $script:Conn.Release | Should -Match '^9\.'
  }

  It 'renews an aged ticket against the real server and keeps working' {
    $before = InModuleScope PVEPS -Parameters @{ Id = $script:Conn.Id } { $script:PVEAuthState[$Id].Ticket }
    InModuleScope PVEPS -Parameters @{ Id = $script:Conn.Id } { $script:PVEAuthState[$Id].TicketTime = (Get-Date).AddMinutes(-61) }

    $nodes = @(Invoke-PVEApi -Path /nodes -ErrorAction Stop)

    $after = InModuleScope PVEPS -Parameters @{ Id = $script:Conn.Id } { $script:PVEAuthState[$Id].Ticket }
    $nodes.Count | Should -BeGreaterThan 0
    $after | Should -Not -Be $before -Because 'renewal posts the old ticket as the password and receives a new one'
  }

  It 'recovers from a ticket the server rejects by logging in again' {
    InModuleScope PVEPS -Parameters @{ Id = $script:Conn.Id } { $script:PVEAuthState[$Id].Ticket = 'PVE:invalid' }
    $nodes = @(Invoke-PVEApi -Path /nodes -ErrorAction Stop)
    $nodes.Count | Should -BeGreaterThan 0
  }
}
