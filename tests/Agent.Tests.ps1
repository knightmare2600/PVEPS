#Requires -Modules Pester
# Phase 6 guest agent and console cmdlets. HTTP is mocked (see TestHelpers.ps1); nothing here touches a
# real server. Agent replies follow the QEMU guest agent protocol shapes inside PVE's 'result' wrapper.

BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  Mock -ModuleName PVEPS Start-Sleep { }

  function Initialize-Agent {
    Reset-FakeState
    $script:State = @{
      Guests       = [ordered]@{
        '100' = @{ type = 'qemu'; vmid = 100; name = 'web01'; status = 'running'; agent = $true }
        '101' = @{ type = 'qemu'; vmid = 101; name = 'db01'; status = 'running'; agent = $false }
        '102' = @{ type = 'qemu'; vmid = 102; name = 'off01'; status = 'stopped'; agent = $false }
        '200' = @{ type = 'lxc'; vmid = 200; name = 'dns01'; status = 'running'; agent = $false }
      }
      ExecPolls    = 0
      ExitAfter    = 2
      GuestFile    = [byte[]](0..255 + 0..255)
      Written      = $null
    }
    $script:Fake.Handler = $script:AgentHandler
    $null = Connect-PVE -Server pve -User root@pam -Password 'x'
    $script:Fake.Calls.Clear()
  }

  function ConvertFrom-Body {
    param([string]$Body)
    $result = @{}
    foreach ($pair in ($Body -split '&' | Where-Object { $_ })) {
      $key, $value = $pair -split '=', 2
      $key = [uri]::UnescapeDataString($key)
      $value = [uri]::UnescapeDataString($value)
      if ($result.ContainsKey($key)) { $result[$key] = @($result[$key]) + $value } else { $result[$key] = $value }
    }
    $result
  }

  $script:AgentHandler = {
    param($Method, $Path, $Call)
    $state = $script:State
    if ($Path -eq '/access/ticket') { return New-FakeResponse -Data @{ ticket = 'PVE:root@pam:AAAA::sig'; CSRFPreventionToken = 'AAAA:csrf'; username = 'root@pam' } }
    if ($Path -eq '/version') { return New-FakeResponse -Data @{ version = '9.2.1'; release = '9.2' } }
    if ($Path -eq '/cluster/resources') {
      return New-FakeResponse -Data @($state.Guests.Values | ForEach-Object { @{ type = $_.type; vmid = $_.vmid; name = $_.name; node = 'pve'; status = $_.status; template = 0 } })
    }
    if ($Path -match '^/nodes/pve/(qemu|lxc)/(\d+)/status/current$') {
      $g = $state.Guests[$Matches[2]]
      return New-FakeResponse -Data @{ vmid = $g.vmid; status = $g.status; name = $g.name }
    }
    if ($Path -notmatch '^/nodes/pve/qemu/(\d+)/agent/(.+)$') {
      return New-FakeResponse -Status 501 -Reason "Unexpected $Method $Path in test" -Data $null
    }
    $g = $state.Guests[$Matches[1]]
    $command = $Matches[2]
    if (-not $g.agent) { return New-FakeResponse -Status 500 -Reason 'QEMU guest agent is not running' -Data $null }
    $query = ConvertFrom-Body $Call.Query
    switch ($command) {
      'ping' { return New-FakeResponse -Data @{ result = @{} } }
      'get-osinfo' { return New-FakeResponse -Data @{ result = @{ name = 'Debian GNU/Linux'; 'pretty-name' = 'Debian GNU/Linux 13 (trixie)'; version = '13 (trixie)'; 'kernel-release' = '6.12.0-1-amd64' } } }
      'get-host-name' { return New-FakeResponse -Data @{ result = @{ 'host-name' = 'web01.example.com' } } }
      'info' { return New-FakeResponse -Data @{ result = @{ version = '9.2.0' } } }
      'network-get-interfaces' {
        return New-FakeResponse -Data @{ result = @(
            @{ name = 'lo'; 'hardware-address' = '00:00:00:00:00:00'; 'ip-addresses' = @(@{ 'ip-address' = '127.0.0.1'; 'ip-address-type' = 'ipv4'; prefix = 8 }, @{ 'ip-address' = '::1'; 'ip-address-type' = 'ipv6'; prefix = 128 }) }
            @{ name = 'eth0'; 'hardware-address' = 'bc:24:11:00:00:01'; 'ip-addresses' = @(@{ 'ip-address' = '192.0.2.10'; 'ip-address-type' = 'ipv4'; prefix = 24 }, @{ 'ip-address' = 'fe80::1'; 'ip-address-type' = 'ipv6'; prefix = 64 }) }
          )
        }
      }
      'exec' { return New-FakeResponse -Data @{ pid = 4242 } }
      'exec-status' {
        $state.ExecPolls++
        if ($state.ExecPolls -lt $state.ExitAfter) { return New-FakeResponse -Data @{ exited = 0 } }
        return New-FakeResponse -Data @{ exited = 1; exitcode = 3; 'out-data' = "hello`n"; 'err-data' = 'warn'; 'out-truncated' = 0 }
      }
      'file-write' {
        $state.Written = ConvertFrom-Body $Call.Body
        return New-FakeResponse -Data $null
      }
      'file-read' {
        $offset = [int]$query.offset
        $count = [int]$query.count
        $bytes = $state.GuestFile
        $take = [math]::Min($count, $bytes.Length - $offset)
        $chunk = [byte[]]$bytes[$offset..($offset + $take - 1)]
        $data = @{ content = [Convert]::ToBase64String($chunk) }
        if ($offset + $take -lt $bytes.Length) { $data.truncated = 1 }
        return New-FakeResponse -Data $data
      }
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

Describe 'Get-PVEVMGuest' {
  BeforeEach {
    Initialize-Agent
  }

  It 'reads OS, host name, agent version and addresses, leaving out loopback addresses' {
    $g = Get-PVEVMGuest -VMId 100
    $g.PSObject.TypeNames | Should -Contain 'PVEPS.VMGuest'
    $g.State | Should -Be 'Running'
    $g.OSName | Should -Be 'Debian GNU/Linux 13 (trixie)'
    $g.OSVersion | Should -Be '13 (trixie)'
    $g.KernelRelease | Should -Be '6.12.0-1-amd64'
    $g.HostName | Should -Be 'web01.example.com'
    $g.AgentVersion | Should -Be '9.2.0'
    $g.IPAddress | Should -Be @('192.0.2.10', 'fe80::1')
    $g.Interfaces.Count | Should -Be 2
    $g.Interfaces[1].Name | Should -Be 'eth0'
    $g.Interfaces[1].IPAddress | Should -Be @('192.0.2.10/24', 'fe80::1/64')
  }

  It 'reports AgentNotRunning without an error when the agent does not answer' {
    $r = Invoke-Streams { Get-PVEVMGuest -VMId 101 }
    $r.Errors.Count | Should -Be 0
    $r.Output[0].State | Should -Be 'AgentNotRunning'
    $r.Output[0].IPAddress.Count | Should -Be 0
  }

  It 'reports VMNotRunning for a stopped VM without calling the agent' {
    (Get-PVEVMGuest -VMId 102).State | Should -Be 'VMNotRunning'
    (Get-Request POST '/agent/').Count | Should -Be 0
  }
}

Describe 'Invoke-PVEVMScript' {
  BeforeEach {
    Initialize-Agent
  }

  It 'runs a script through bash, polls until it exits, and returns the output' {
    $r = Invoke-PVEVMScript -VMId 100 -ScriptText 'echo hello; exit 3' -InputData 'in'
    $exec = Get-Request POST '/agent/exec$'
    $exec.Count | Should -Be 1
    $body = ConvertFrom-Body $exec[0].Body
    $body.command | Should -Be @('/bin/bash', '-c', 'echo hello; exit 3')
    $body['input-data'] | Should -Be 'in'
    (ConvertFrom-Body (Get-Request GET '/agent/exec-status$')[0].Query).pid | Should -Be '4242'
    $r.PSObject.TypeNames | Should -Contain 'PVEPS.VMScriptResult'
    $r.ExitCode | Should -Be 3
    $r.StdOut | Should -Be "hello`n"
    $r.StdErr | Should -Be 'warn'
    $r.OutTruncated | Should -BeFalse
  }

  It 'sends -Command as the program and its arguments, one form value each' {
    $null = Invoke-PVEVMScript -VMId 100 -Command ls, '-l', '/etc dir'
    $exec = (Get-Request POST '/agent/exec$')[0]
    $exec.Body | Should -Be 'command=ls&command=-l&command=%2Fetc%20dir'
  }

  It 'builds the <ScriptType> command line' -ForEach @(
    @{ ScriptType = 'Sh'; Expected = @('/bin/sh', '-c', 'x') }
    @{ ScriptType = 'PowerShell'; Expected = @('powershell.exe', '-NoProfile', '-NonInteractive', '-Command', 'x') }
    @{ ScriptType = 'Pwsh'; Expected = @('pwsh', '-NoProfile', '-NonInteractive', '-Command', 'x') }
    @{ ScriptType = 'Cmd'; Expected = @('cmd.exe', '/c', 'x') }
  ) {
    $null = Invoke-PVEVMScript -VMId 100 -ScriptText x -ScriptType $ScriptType
    (ConvertFrom-Body (Get-Request POST '/agent/exec$')[0].Body).command | Should -Be $Expected
  }

  It 'times out with an error when the command keeps running' {
    $script:State.ExitAfter = 1000000
    # Each call to Get-Date moves the clock on 10 seconds, so the 5-second timeout passes after one poll.
    $script:Clock = [datetime]'2030-01-01'
    Mock -ModuleName PVEPS Get-Date { $script:Clock = $script:Clock.AddSeconds(10); $script:Clock }
    $r = Invoke-Streams { Invoke-PVEVMScript -VMId 100 -Command sleep, 999 -TimeoutSec 5 }
    $r.Errors[0].FullyQualifiedErrorId | Should -BeLike 'PVEGuestCommandTimeout*'
    $r.Output.Count | Should -Be 0
  }

  It 'refuses a stopped VM, and sends nothing under -WhatIf' {
    $r = Invoke-Streams { Invoke-PVEVMScript -VMId 102 -Command true }
    $r.Errors[0].FullyQualifiedErrorId | Should -BeLike 'PVEGuestNotRunning*'
    Invoke-PVEVMScript -VMId 100 -Command true -WhatIf
    (Get-Request POST '/agent/exec').Count | Should -Be 0
  }
}

Describe 'Copy-PVEVMGuestFile' {
  BeforeEach {
    Initialize-Agent
    $script:Dir = Join-Path ([System.IO.Path]::GetTempPath()) ("pveps-test-" + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path $script:Dir
  }

  AfterEach {
    Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'writes a local file into the guest base64-encoded, so any bytes copy unchanged' {
    $file = Join-Path $script:Dir 'blob.bin'
    $bytes = [byte[]](0..255)
    [System.IO.File]::WriteAllBytes($file, $bytes)
    Copy-PVEVMGuestFile -VMId 100 -LocalToGuest -Source $file -Destination /tmp/blob.bin
    $script:State.Written.file | Should -Be '/tmp/blob.bin'
    $script:State.Written.encode | Should -Be '0'
    [Convert]::FromBase64String($script:State.Written.content) | Should -Be $bytes
  }

  It 'refuses a local file above the file-write limit before sending anything' {
    $file = Join-Path $script:Dir 'big.bin'
    [System.IO.File]::WriteAllBytes($file, [byte[]]::new(46081))
    { Copy-PVEVMGuestFile -VMId 100 -LocalToGuest -Source $file -Destination /tmp/x } | Should -Throw '*at most 46080 bytes*'
    (Get-Request POST '/agent/').Count | Should -Be 0
  }

  It 'reads a guest file in chunks and writes it locally' {
    $file = Join-Path $script:Dir 'out.bin'
    $info = Copy-PVEVMGuestFile -VMId 100 -GuestToLocal -Source /etc/blob -Destination $file
    $info | Should -BeOfType [System.IO.FileInfo]
    [System.IO.File]::ReadAllBytes($file) | Should -Be $script:State.GuestFile
  }

  It 'needs -Force to replace an existing local file' {
    $file = Join-Path $script:Dir 'exists.txt'
    Set-Content -LiteralPath $file -Value 'old'
    { Copy-PVEVMGuestFile -VMId 100 -GuestToLocal -Source /etc/blob -Destination $file } | Should -Throw '*add -Force*'
    $null = Copy-PVEVMGuestFile -VMId 100 -GuestToLocal -Source /etc/blob -Destination $file -Force
    (Get-Item -LiteralPath $file).Length | Should -Be 512
  }

  It 'copies from exactly one VM with -GuestToLocal' {
    { Copy-PVEVMGuestFile -VMId 100, 101 -GuestToLocal -Source /x -Destination (Join-Path $script:Dir 'y') } | Should -Throw '*exactly one VM*'
  }

  It 'removes the partial local file when the read fails' {
    $file = Join-Path $script:Dir 'partial.bin'
    $r = Invoke-Streams { Copy-PVEVMGuestFile -VMId 101 -GuestToLocal -Source /x -Destination $file }
    $r.Errors.Count | Should -Be 1
    Test-Path -LiteralPath $file | Should -BeFalse
  }
}

Describe 'Open-PVEVMConsole and Open-PVEContainerConsole' {
  BeforeEach {
    Initialize-Agent
    Mock -ModuleName PVEPS Start-Process { }
  }

  It 'builds the noVNC URL the web interface uses' {
    Open-PVEVMConsole -VMId 100 -UrlOnly | Should -Be 'https://pve:8006/?console=kvm&novnc=1&vmid=100&vmname=web01&node=pve&resize=off&cmd='
    Open-PVEContainerConsole -VMId 200 -UrlOnly | Should -Be 'https://pve:8006/?console=lxc&novnc=1&vmid=200&vmname=dns01&node=pve&resize=off&cmd='
  }

  It 'hands the URL to Start-Process without -UrlOnly' {
    Open-PVEVMConsole web01
    Should -Invoke -ModuleName PVEPS Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -like 'https://pve:8006/?console=kvm*' }
  }
}
