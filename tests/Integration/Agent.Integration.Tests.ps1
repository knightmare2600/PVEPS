#Requires -Modules Pester
# Integration tests for the Phase 6 guest agent and console cmdlets. They run commands in, and write one
# file to /tmp of, one test VM that already exists: a Linux guest with the QEMU guest agent installed and
# running, the agent option enabled, in PVEPS_TEST_POOL and named pveps-test*. Its power state is not
# changed; the tests skip if it is not running.
#
# Skipped unless these are set, in addition to PVEPS_TEST_SERVER (and PVEPS_TEST_SKIPCERT if needed):
#   PVEPS_TEST_WRITE_TOKEN_ID, PVEPS_TEST_WRITE_TOKEN_SECRET, PVEPS_TEST_POOL
#   PVEPS_TEST_AGENT_VMID    ID of the test VM described above
#
# Run: Invoke-Pester ./tests/Integration/Agent.Integration.Tests.ps1 -Output Detailed

BeforeDiscovery {
  $script:HaveAgent = [bool]($env:PVEPS_TEST_SERVER -and $env:PVEPS_TEST_WRITE_TOKEN_ID -and $env:PVEPS_TEST_WRITE_TOKEN_SECRET -and $env:PVEPS_TEST_POOL -and $env:PVEPS_TEST_AGENT_VMID)
}

BeforeAll {
  . (Join-Path $PSScriptRoot 'IntegrationHelpers.ps1')
  Connect-PVETestWrite
}

AfterAll {
  Disconnect-PVE -Server * -Confirm:$false -ErrorAction SilentlyContinue
}

Describe 'Guest agent against a real server' -Tag 'Integration', 'Agent' -Skip:(-not $script:HaveAgent) {
  BeforeAll {
    $script:VMId = [int]$env:PVEPS_TEST_AGENT_VMID
    $vm = Get-PVEVM -VMId $script:VMId -ErrorAction Stop
    Assert-PVETestGuest -Guest $vm -Kind 'VM'
    if ((Get-PVETestLiveStatus -Guest $vm) -ne 'running') {
      throw "Test VM $script:VMId is not running; start it (with its guest agent) before running these tests."
    }
    $script:Local = Join-Path ([System.IO.Path]::GetTempPath()) ('pveps-agent-' + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path $script:Local
  }

  AfterAll {
    Remove-Item -LiteralPath $script:Local -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'reports the guest OS and addresses' {
    $guest = Get-PVEVMGuest -VMId $script:VMId -ErrorAction Stop
    $guest.State | Should -Be 'Running'
    $guest.OSName | Should -Not -BeNullOrEmpty
    $guest.HostName | Should -Not -BeNullOrEmpty
    $guest.Interfaces.Count | Should -BeGreaterThan 0
  }

  It 'runs a command with arguments and returns its output and exit code' {
    $result = Invoke-PVEVMScript -VMId $script:VMId -Command '/bin/echo', 'hello world' -ErrorAction Stop
    $result.ExitCode | Should -Be 0
    $result.StdOut | Should -Be "hello world`n"
  }

  It 'runs a script with standard input and a non-zero exit code' {
    $result = Invoke-PVEVMScript -VMId $script:VMId -ScriptText 'read line; echo "got $line"; echo oops >&2; exit 7' -ScriptType Sh -InputData "abc`n" -ErrorAction Stop
    $result.ExitCode | Should -Be 7
    $result.StdOut | Should -Be "got abc`n"
    $result.StdErr | Should -Be "oops`n"
  }

  It 'copies a binary file into the guest and back unchanged' {
    $source = Join-Path $script:Local 'in.bin'
    $bytes = [byte[]]::new(40000)
    [System.Random]::new(42).NextBytes($bytes)
    [System.IO.File]::WriteAllBytes($source, $bytes)
    $guestPath = '/tmp/pveps-agent-test.bin'
    Copy-PVEVMGuestFile -VMId $script:VMId -LocalToGuest -Source $source -Destination $guestPath -ErrorAction Stop
    $back = Join-Path $script:Local 'out.bin'
    $null = Copy-PVEVMGuestFile -VMId $script:VMId -GuestToLocal -Source $guestPath -Destination $back -ErrorAction Stop
    [System.IO.File]::ReadAllBytes($back) | Should -Be $bytes
    $null = Invoke-PVEVMScript -VMId $script:VMId -Command '/bin/rm', '-f', $guestPath -ErrorAction Stop
  }

  It 'builds a console URL for the VM' {
    $url = Open-PVEVMConsole -VMId $script:VMId -UrlOnly
    $url | Should -BeLike "https://*:*/?console=kvm&novnc=1&vmid=$($script:VMId)&*"
  }
}
