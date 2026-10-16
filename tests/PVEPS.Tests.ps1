#Requires -Modules Pester
# Unit tests. The HTTP layer (Invoke-WebRequest) is mocked; nothing here touches a real server.
# Run: Invoke-Pester ./tests -ExcludeTagFilter Integration

BeforeAll {
  $script:ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
  Import-Module (Join-Path $script:ModuleRoot 'PVEPS.psd1') -Force

  # Every mocked request is recorded here; $script:Fake.Handler decides the response.
  $script:Fake = @{
    Calls   = [System.Collections.Generic.List[psobject]]::new()
    Handler = $null
  }

  function New-FakeResponse {
    param(
      [int]$Status = 200,
      [string]$Reason = 'OK',
      [object]$Data,
      [hashtable]$Extra = @{}
    )
    $payload = @{ data = $Data } + $Extra
    [pscustomobject]@{
      StatusCode   = $Status
      Content      = ($payload | ConvertTo-Json -Depth 20 -Compress)
      BaseResponse = [pscustomobject]@{ ReasonPhrase = $Reason }
    }
  }

  function Get-PathOf {
    param([string]$Uri)
    ([uri]$Uri).AbsolutePath -replace '^/api2/json', ''
  }

  function Get-QueryOf {
    param([string]$Uri)
    ([uri]$Uri).Query.TrimStart('?')
  }

  function Reset-FakeState {
    $script:Fake.Calls.Clear()
    $script:Fake.Handler = $null
    InModuleScope PVEPS {
      $script:PVEConnections.Clear()
      $script:DefaultPVEConnection = $null
      $script:PVEAuthState.Clear()
    }
  }

  # Default handler: a well-behaved PVE that issues a ticket and reports version 9.2.
  $script:DefaultHandler = {
    param($Method, $Path)
    switch ($Path) {
      '/access/ticket' { New-FakeResponse -Data @{ ticket = 'PVE:root@pam:AAAA::sig'; CSRFPreventionToken = 'AAAA:csrf'; username = 'root@pam' } }
      '/version' { New-FakeResponse -Data @{ version = '9.2.1'; release = '9.2'; repoid = 'deadbeef' } }
      default { New-FakeResponse -Data $null }
    }
  }

  function New-TestCredential {
    param([string]$User = 'root@pam', [string]$Secret = 'p@ss word&=')
    [pscredential]::new($User, (ConvertTo-SecureString -String $Secret -AsPlainText -Force))
  }

  Mock -ModuleName PVEPS Invoke-WebRequest {
    $call = [pscustomobject]@{
      Method  = [string]$Method
      Uri     = [string]$Uri
      Path    = Get-PathOf $Uri
      Query   = Get-QueryOf $Uri
      Headers = $Headers
      Body    = $Body
      SkipCertificateCheck = [bool]$SkipCertificateCheck
    }
    $script:Fake.Calls.Add($call)
    $handler = if ($script:Fake.Handler) { $script:Fake.Handler } else { $script:DefaultHandler }
    & $handler $call.Method $call.Path $call
  }
}

Describe 'Module' {
  It 'has a valid manifest requiring PowerShell 7.4 Core' {
    $manifest = Test-ModuleManifest -Path (Join-Path $script:ModuleRoot 'PVEPS.psd1')
    $manifest.PowerShellVersion | Should -Be ([version]'7.4')
    $manifest.CompatiblePSEditions | Should -Be @('Core')
  }

  It 'exports exactly the functions in Public/, and the manifest lists the same set' {
    $publicFiles = (Get-ChildItem (Join-Path $script:ModuleRoot 'Public') -Filter *.ps1).BaseName | Sort-Object
    $exported = (Get-Command -Module PVEPS).Name | Sort-Object
    $manifest = Import-PowerShellDataFile (Join-Path $script:ModuleRoot 'PVEPS.psd1')
    $exported | Should -Be $publicFiles
    ($manifest.FunctionsToExport | Sort-Object) | Should -Be $publicFiles
  }

  It 'has no PSScriptAnalyzer findings' {
    if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
      Set-ItResult -Skipped -Because 'PSScriptAnalyzer is not installed'
      return
    }
    $settings = Join-Path $script:ModuleRoot 'PSScriptAnalyzerSettings.psd1'
    $findings = foreach ($folder in 'Public', 'Private') {
      Invoke-ScriptAnalyzer -Path (Join-Path $script:ModuleRoot $folder) -Recurse -Settings $settings
    }
    $findings = @($findings) + @(Invoke-ScriptAnalyzer -Path (Join-Path $script:ModuleRoot 'PVEPS.psm1') -Settings $settings)
    ($findings | Where-Object { $_ } | ForEach-Object { '{0}:{1} {2}' -f $_.ScriptName, $_.Line, $_.RuleName }) | Should -BeNullOrEmpty
  }

  It 'has comment-based help with a synopsis and an example for every public function' {
    foreach ($name in (Get-Command -Module PVEPS).Name) {
      $help = Get-Help $name -Full
      $help.Synopsis | Should -Not -BeNullOrEmpty -Because "$name needs a synopsis"
      @($help.examples.example).Count | Should -BeGreaterThan 0 -Because "$name needs an example"
    }
  }
}

Describe 'Format-PVEPath' {
  It 'escapes values into the template' {
    InModuleScope PVEPS {
      Format-PVEPath '/nodes/{node}/tasks/{upid}/status' @{ node = 'pve01'; upid = 'UPID:pve01:00A:0B:0C:qmstart:100:root@pam:' } |
        Should -Be '/nodes/pve01/tasks/UPID%3Apve01%3A00A%3A0B%3A0C%3Aqmstart%3A100%3Aroot%40pam%3A/status'
    }
  }

  It 'throws when a placeholder has no value' {
    InModuleScope PVEPS {
      { Format-PVEPath '/nodes/{node}/qemu/{vmid}' @{ node = 'pve01' } } | Should -Throw '*{vmid}*'
    }
  }

  It 'throws when a value is empty' {
    InModuleScope PVEPS {
      { Format-PVEPath '/nodes/{node}' @{ node = '' } } | Should -Throw '*empty*'
    }
  }
}

Describe 'Get-PVEValue' {
  It 'returns $null for a missing member, a $null object, or a missing key, without tripping strict mode' {
    InModuleScope PVEPS {
      Set-StrictMode -Version 3.0
      Get-PVEValue ([pscustomobject]@{ a = 1 }) 'b' | Should -BeNullOrEmpty
      Get-PVEValue $null 'b' | Should -BeNullOrEmpty
      Get-PVEValue @{ a = 1 } 'b' | Should -BeNullOrEmpty
    }
  }

  It 'returns scalars and keeps arrays intact' {
    InModuleScope PVEPS {
      Get-PVEValue ([pscustomobject]@{ a = 'x' }) 'a' | Should -Be 'x'
      $one = Get-PVEValue ([pscustomobject]@{ a = @('only') }) 'a'
      , $one | Should -BeOfType [object[]]
      $many = Get-PVEValue ([pscustomobject]@{ a = @(1, 2, 3) }) 'a'
      $many.Count | Should -Be 3
      Get-PVEValue @{ k = 5 } 'k' | Should -Be 5
    }
  }
}

Describe 'ConvertTo-PVEFormData' {
  It 'sends booleans and switches as 1/0, skips nulls, escapes, sorts keys and repeats arrays' {
    InModuleScope PVEPS {
      $form = ConvertTo-PVEFormData @{
        zeta    = 'a b&c=d'
        alpha   = $true
        beta    = $false
        gamma   = [switch]::new($true)
        skipped = $null
        multi   = @('x', 'y')
      }
      $form | Should -Be 'alpha=1&beta=0&gamma=1&multi=x&multi=y&zeta=a%20b%26c%3Dd'
    }
  }

  It 'returns an empty string for no parameters' {
    InModuleScope PVEPS {
      ConvertTo-PVEFormData @{} | Should -Be ''
      ConvertTo-PVEFormData $null | Should -Be ''
    }
  }
}

Describe 'ConvertTo-PVETask' {
  BeforeAll {
    $script:Conn = [pscustomobject]@{ PSTypeName = 'PVEPS.Connection'; Id = 'x'; Server = 's' }
  }

  It 'maps the status endpoint: running' {
    $task = InModuleScope PVEPS -Parameters @{ C = $script:Conn } {
      [pscustomobject]@{ upid = 'UPID:pve01:1:2:3:qmstart:100:root@pam:'; node = 'pve01'; status = 'running'; type = 'qmstart'; id = '100'; user = 'root@pam'; starttime = 1700000000 } |
        ConvertTo-PVETask -Connection $C
    }
    $task.State | Should -Be 'Running'
    $task.Succeeded | Should -BeNullOrEmpty
    $task.StartTime | Should -Be ([DateTimeOffset]::FromUnixTimeSeconds(1700000000).LocalDateTime)
  }

  It 'maps the status endpoint: stopped with OK' {
    $task = InModuleScope PVEPS -Parameters @{ C = $script:Conn } {
      [pscustomobject]@{ upid = 'UPID:pve01:1:2:3:qmstart:100:root@pam:'; status = 'stopped'; exitstatus = 'OK' } | ConvertTo-PVETask -Connection $C
    }
    $task.State | Should -Be 'Stopped'
    $task.ExitStatus | Should -Be 'OK'
    $task.Succeeded | Should -BeTrue
    $task.Node | Should -Be 'pve01' -Because 'the node is parsed from the UPID when the record has none'
  }

  It 'maps list endpoints, where status is the exit status and endtime marks completion' {
    $tasks = InModuleScope PVEPS -Parameters @{ C = $script:Conn } {
      @(
        [pscustomobject]@{ upid = 'UPID:a:1:2:3:vzdump::root@pam:'; node = 'a'; status = 'job errors'; starttime = 1; endtime = 2 }
        [pscustomobject]@{ upid = 'UPID:a:1:2:4:qmstart:1:root@pam:'; node = 'a'; status = 'WARNINGS: 2'; starttime = 1; endtime = 2 }
        [pscustomobject]@{ upid = 'UPID:a:1:2:5:qmstart:2:root@pam:'; node = 'a'; starttime = 1 }
      ) | ConvertTo-PVETask -Connection $C
    }
    $tasks[0].State | Should -Be 'Stopped'
    $tasks[0].ExitStatus | Should -Be 'job errors'
    $tasks[0].Succeeded | Should -BeFalse
    $tasks[1].Succeeded | Should -BeTrue
    $tasks[2].State | Should -Be 'Running'
  }

  It 'carries its connection' {
    $task = InModuleScope PVEPS -Parameters @{ C = $script:Conn } {
      [pscustomobject]@{ upid = 'UPID:a:1:2:3:x::u:'; status = 'running' } | ConvertTo-PVETask -Connection $C
    }
    $task.Connection.Id | Should -Be 'x'
    $task.PSObject.TypeNames | Should -Contain 'PVEPS.Task'
  }
}

Describe 'Connect-PVE' {
  BeforeEach {
    Reset-FakeState
  }

  It 'logs in with a credential, sends no auth on the ticket request, then verifies with /version' {
    $conn = Connect-PVE -Server pve01 -Credential (New-TestCredential)

    $script:Fake.Calls.Count | Should -Be 2
    $login = $script:Fake.Calls[0]
    $login.Method | Should -Be 'POST'
    $login.Path | Should -Be '/access/ticket'
    $login.Headers.ContainsKey('Cookie') | Should -BeFalse
    $login.Headers.ContainsKey('Authorization') | Should -BeFalse
    $login.Body | Should -Be 'password=p%40ss%20word%26%3D&username=root%40pam'

    $version = $script:Fake.Calls[1]
    $version.Method | Should -Be 'GET'
    $version.Uri | Should -Be 'https://pve01:8006/api2/json/version'
    $version.Headers['Cookie'] | Should -Be 'PVEAuthCookie=PVE:root@pam:AAAA::sig'
    $version.Headers.ContainsKey('CSRFPreventionToken') | Should -BeFalse -Because 'CSRF is only required for non-GET'

    $conn.Release | Should -Be '9.2'
    $conn.Version | Should -Be '9.2.1'
    $conn.AuthType | Should -Be 'Ticket'
    $conn.IsConnected | Should -BeTrue
    (Get-PVEConnection -Default).Id | Should -Be $conn.Id
  }

  It 'never exposes secrets on the connection object' {
    $conn = Connect-PVE -Server pve01 -Credential (New-TestCredential)
    $json = $conn | ConvertTo-Json -Depth 5
    $json | Should -Not -Match 'AAAA'
    $json | Should -Not -Match 'p@ss'
  }

  It 'authenticates with an API token header and makes no ticket request' {
    $token = New-TestCredential -User 'automation@pve!pveps' -Secret '0b1c2d3e-aaaa-bbbb-cccc-123456789abc'
    $conn = Connect-PVE -Server pve01 -ApiToken $token -SkipCertificateCheck

    $script:Fake.Calls.Count | Should -Be 1
    $script:Fake.Calls[0].Path | Should -Be '/version'
    $script:Fake.Calls[0].Headers['Authorization'] | Should -Be 'PVEAPIToken=automation@pve!pveps=0b1c2d3e-aaaa-bbbb-cccc-123456789abc'
    $script:Fake.Calls[0].SkipCertificateCheck | Should -BeTrue
    $conn.AuthType | Should -Be 'ApiToken'
  }

  It 'brackets a bare IPv6 address and honours -Port' {
    $conn = Connect-PVE -Server '2001:db8::10' -Port 8443 -Credential (New-TestCredential)
    $conn.BaseUri | Should -Be 'https://[2001:db8::10]:8443'
    $script:Fake.Calls[0].Uri | Should -Be 'https://[2001:db8::10]:8443/api2/json/access/ticket'
  }

  It 'rejects a URL as -Server' {
    { Connect-PVE -Server 'https://pve01:8006' -Credential (New-TestCredential) } | Should -Throw '*not a URL*'
    $script:Fake.Calls.Count | Should -Be 0
  }

  It 'rejects a user name without a realm' {
    { Connect-PVE -Server pve01 -Credential (New-TestCredential -User 'root') } | Should -Throw '*realm*'
  }

  It 'rejects a malformed token ID' {
    { Connect-PVE -Server pve01 -ApiToken (New-TestCredential -User 'automation@pve') } | Should -Throw '*user@realm!tokenname*'
  }

  It 'leaves the default alone with -NotDefault' {
    $first = Connect-PVE -Server pve01 -Credential (New-TestCredential)
    $null = Connect-PVE -Server pve02 -Credential (New-TestCredential) -NotDefault
    (Get-PVEConnection -Default).Id | Should -Be $first.Id
    @(Get-PVEConnection).Count | Should -Be 2
    @(Get-PVEConnection -Server 'pve02').Count | Should -Be 1
  }

  It 'fails with PVE''s message on bad credentials and registers nothing' {
    $script:Fake.Handler = { param($Method, $Path) New-FakeResponse -Status 401 -Reason 'authentication failure' -Data $null }
    { Connect-PVE -Server pve01 -Credential (New-TestCredential) } | Should -Throw '*HTTP 401*authentication failure*'
    @(Get-PVEConnection).Count | Should -Be 0
    InModuleScope PVEPS { $script:PVEAuthState.Count } | Should -Be 0
  }

  It 'fails clearly when the user has two-factor authentication enabled' {
    $script:Fake.Handler = {
      param($Method, $Path)
      New-FakeResponse -Data @{ ticket = 'PVE:!tfa!root@pam:AAAA::sig'; CSRFPreventionToken = 'x'; username = 'root@pam'; NeedTFA = 1 }
    }
    { Connect-PVE -Server pve01 -Credential (New-TestCredential) } | Should -Throw '*two-factor*API token*'
    @(Get-PVEConnection).Count | Should -Be 0
  }

  It 'copes with a /version response that omits optional fields (module runs under strict mode)' {
    $script:Fake.Handler = {
      param($Method, $Path)
      if ($Path -eq '/access/ticket') { New-FakeResponse -Data @{ ticket = 'PVE:root@pam:AAAA::sig'; CSRFPreventionToken = 'AAAA:csrf'; username = 'root@pam' } }
      else { New-FakeResponse -Data @{} }
    }
    $conn = Connect-PVE -Server pve01 -Credential (New-TestCredential)
    $conn.IsConnected | Should -BeTrue
    $conn.Release | Should -Be ''
  }

  It 'fails clearly when the ticket response has no CSRF token' {
    $script:Fake.Handler = { param($Method, $Path) New-FakeResponse -Data @{ ticket = 'PVE:root@pam:AAAA::sig'; username = 'root@pam' } }
    { Connect-PVE -Server pve01 -Credential (New-TestCredential) } | Should -Throw '*did not return a ticket and CSRF token*'
  }

  It 'fails clearly when the ticket response has no data at all' {
    $script:Fake.Handler = { param($Method, $Path) New-FakeResponse -Data $null }
    { Connect-PVE -Server pve01 -Credential (New-TestCredential) } | Should -Throw '*did not return a ticket and CSRF token*'
  }

  It 'reports an unreachable server as a connection error' {
    $script:Fake.Handler = { throw [System.Net.Http.HttpRequestException]::new('Name or service not known') }
    $err = $null
    try {
      Connect-PVE -Server nowhere -Credential (New-TestCredential)
    }
    catch {
      $err = $_
    }
    $err.FullyQualifiedErrorId | Should -Match '^PVEConnectionFailed'
    $err.Exception.Message | Should -Match 'Unable to reach https://nowhere:8006.*Name or service not known'
  }
}

Describe 'Invoke-PVERequest behaviour (through Invoke-PVEApi)' {
  BeforeEach {
    Reset-FakeState
    $script:Conn = Connect-PVE -Server pve01 -Credential (New-TestCredential)
    $script:Fake.Calls.Clear()
  }

  It 'puts GET parameters in the query string and returns data' {
    $script:Fake.Handler = { param($Method, $Path) New-FakeResponse -Data @(@{ vmid = 100 }, @{ vmid = 101 }) }
    $result = Invoke-PVEApi -Path /cluster/resources -Parameters @{ type = 'vm' }
    $script:Fake.Calls[0].Query | Should -Be 'type=vm'
    $script:Fake.Calls[0].Body | Should -BeNullOrEmpty
    $result.vmid | Should -Be @(100, 101)
  }

  It 'puts POST parameters in a form body and sends the CSRF token' {
    $null = Invoke-PVEApi -Method POST -Path /nodes/pve01/qemu/100/config -Parameters @{ memory = 2048; onboot = $true } -Confirm:$false
    $call = $script:Fake.Calls[0]
    $call.Body | Should -Be 'memory=2048&onboot=1'
    $call.Query | Should -BeNullOrEmpty
    $call.Headers['CSRFPreventionToken'] | Should -Be 'AAAA:csrf'
    $call.Headers['Cookie'] | Should -Be 'PVEAuthCookie=PVE:root@pam:AAAA::sig'
  }

  It 'puts DELETE parameters in the query string and sends the CSRF token' {
    $null = Invoke-PVEApi -Method DELETE -Path /nodes/pve01/qemu/100 -Parameters @{ purge = $true } -Confirm:$false
    $script:Fake.Calls[0].Query | Should -Be 'purge=1'
    $script:Fake.Calls[0].Headers['CSRFPreventionToken'] | Should -Be 'AAAA:csrf'
  }

  It 'makes no request for a non-GET call under -WhatIf' {
    Invoke-PVEApi -Method POST -Path /nodes/pve01/qemu/100/status/start -WhatIf
    $script:Fake.Calls.Count | Should -Be 0
  }

  It 'turns an HTTP error into an error carrying the PVE reason phrase' {
    $script:Fake.Handler = { param($Method, $Path) New-FakeResponse -Status 500 -Reason 'VM 100 not running' -Data $null }
    { Invoke-PVEApi -Method POST -Path /nodes/pve01/qemu/100/status/shutdown -Confirm:$false -ErrorAction Stop } |
      Should -Throw '*HTTP 500: VM 100 not running*'
  }

  It 'includes per-parameter validation errors' {
    $script:Fake.Handler = {
      param($Method, $Path)
      New-FakeResponse -Status 400 -Reason 'Parameter verification failed.' -Data $null -Extra @{ errors = @{ memory = "value must have a minimum value of 16`n" } }
    }
    { Invoke-PVEApi -Method POST -Path /nodes/pve01/qemu/100/config -Parameters @{ memory = 1 } -Confirm:$false -ErrorAction Stop } |
      Should -Throw '*Parameter verification failed. (memory: value must have a minimum value of 16)*'
  }

  It 'writes exactly one non-terminating error to the error stream' {
    $script:Fake.Handler = { param($Method, $Path) New-FakeResponse -Status 403 -Reason 'Permission check failed' -Data $null }
    # -ErrorVariable would also collect PowerShell's records of the nested private call; the error
    # stream is what a user sees, so assert on that.
    $streamed = @(Invoke-PVEApi -Path /nodes 2>&1)
    $streamed.Count | Should -Be 1
    $streamed[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
    $streamed[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
    $streamed[0].FullyQualifiedErrorId | Should -Be 'PVEHttp403,Invoke-PVEApi'
  }

  It 'renews a ticket older than 60 minutes using the ticket as the password' {
    InModuleScope PVEPS -Parameters @{ Id = $script:Conn.Id } { $script:PVEAuthState[$Id].TicketTime = (Get-Date).AddMinutes(-61) }
    $script:Fake.Handler = {
      param($Method, $Path)
      if ($Path -eq '/access/ticket') { New-FakeResponse -Data @{ ticket = 'PVE:root@pam:BBBB::new'; CSRFPreventionToken = 'BBBB:csrf'; username = 'root@pam' } }
      else { New-FakeResponse -Data @() }
    }
    $null = Invoke-PVEApi -Path /nodes

    $script:Fake.Calls.Count | Should -Be 2
    $script:Fake.Calls[0].Path | Should -Be '/access/ticket'
    $script:Fake.Calls[0].Body | Should -Be 'password=PVE%3Aroot%40pam%3AAAAA%3A%3Asig&username=root%40pam'
    $script:Fake.Calls[1].Headers['Cookie'] | Should -Be 'PVEAuthCookie=PVE:root@pam:BBBB::new'
  }

  It 'logs in with the stored credential when renewal is refused' {
    InModuleScope PVEPS -Parameters @{ Id = $script:Conn.Id } { $script:PVEAuthState[$Id].TicketTime = (Get-Date).AddHours(-3) }
    $script:Fake.Handler = {
      param($Method, $Path, $Call)
      if ($Path -eq '/access/ticket' -and $Call.Body -match 'password=PVE') { New-FakeResponse -Status 401 -Reason 'authentication failure' -Data $null }
      elseif ($Path -eq '/access/ticket') { New-FakeResponse -Data @{ ticket = 'PVE:root@pam:CCCC::fresh'; CSRFPreventionToken = 'CCCC:csrf'; username = 'root@pam' } }
      else { New-FakeResponse -Data @() }
    }
    $null = Invoke-PVEApi -Path /nodes

    $script:Fake.Calls.Path | Should -Be @('/access/ticket', '/access/ticket', '/nodes')
    $script:Fake.Calls[1].Body | Should -Match 'password=p%40ss'
    $script:Fake.Calls[2].Headers['Cookie'] | Should -Be 'PVEAuthCookie=PVE:root@pam:CCCC::fresh'
  }

  It 'logs in again and retries once on HTTP 401, then gives up' {
    $script:Fake.Handler = {
      param($Method, $Path)
      if ($Path -eq '/access/ticket') { New-FakeResponse -Data @{ ticket = 'PVE:root@pam:DDDD::x'; CSRFPreventionToken = 'DDDD:csrf'; username = 'root@pam' } }
      else { New-FakeResponse -Status 401 -Reason 'invalid ticket' -Data $null }
    }
    { Invoke-PVEApi -Path /nodes -ErrorAction Stop } | Should -Throw '*HTTP 401*invalid ticket*'
    $script:Fake.Calls.Path | Should -Be @('/nodes', '/access/ticket', '/nodes')
  }

  It 'does not retry API token requests on 401' {
    Reset-FakeState
    $null = Connect-PVE -Server pve01 -ApiToken (New-TestCredential -User 'a@pve!t1' -Secret 's')
    $script:Fake.Calls.Clear()
    $script:Fake.Handler = { param($Method, $Path) New-FakeResponse -Status 401 -Reason 'invalid token value' -Data $null }
    { Invoke-PVEApi -Path /nodes -ErrorAction Stop } | Should -Throw '*invalid token value*'
    $script:Fake.Calls.Count | Should -Be 1
  }
}

Describe 'Disconnect-PVE and Resolve-PVEConnection' {
  BeforeEach {
    Reset-FakeState
  }

  It 'throws a clear error when no connection is open' {
    { Invoke-PVEApi -Path /nodes } | Should -Throw '*Run Connect-PVE*'
  }

  It 'removes the connection, discards its secrets and moves the default to the remaining connection' {
    $a = Connect-PVE -Server pve01 -Credential (New-TestCredential)
    $b = Connect-PVE -Server pve02 -Credential (New-TestCredential)
    Disconnect-PVE -Confirm:$false

    $b.IsConnected | Should -BeFalse
    (Get-PVEConnection -Default).Id | Should -Be $a.Id
    InModuleScope PVEPS -Parameters @{ Id = $b.Id } { $script:PVEAuthState.ContainsKey($Id) } | Should -BeFalse
    { Invoke-PVEApi -Path /nodes -Server $b -ErrorAction Stop } | Should -Throw '*disconnected*'
  }

  It 'disconnects everything with -Server *' {
    $null = Connect-PVE -Server pve01 -Credential (New-TestCredential)
    $null = Connect-PVE -Server pve02 -Credential (New-TestCredential)
    Disconnect-PVE -Server * -Confirm:$false
    @(Get-PVEConnection).Count | Should -Be 0
    Get-PVEConnection -Default | Should -BeNullOrEmpty
  }

  It 'targets a named server' {
    $null = Connect-PVE -Server pve01 -Credential (New-TestCredential)
    $null = Connect-PVE -Server pve02 -Credential (New-TestCredential)
    $script:Fake.Calls.Clear()
    $null = Invoke-PVEApi -Path /nodes -Server pve01
    $script:Fake.Calls[0].Uri | Should -BeLike 'https://pve01:8006/*'
  }
}

Describe 'Get-PVETask' {
  BeforeEach {
    Reset-FakeState
    $null = Connect-PVE -Server pve01 -Credential (New-TestCredential)
    $script:Fake.Calls.Clear()
  }

  It 'reads /cluster/tasks with no arguments' {
    $script:Fake.Handler = { param($Method, $Path) New-FakeResponse -Data @(@{ upid = 'UPID:pve01:1:2:3:qmstart:100:root@pam:'; node = 'pve01'; status = 'OK'; starttime = 1; endtime = 2; type = 'qmstart'; id = '100'; user = 'root@pam' }) }
    $task = Get-PVETask
    $script:Fake.Calls[0].Path | Should -Be '/cluster/tasks'
    $task.Succeeded | Should -BeTrue
  }

  It 'reads a node task list with filters' {
    $script:Fake.Handler = { param($Method, $Path) New-FakeResponse -Data @() }
    $null = Get-PVETask -Node pve01 -VMId 9001 -ErrorsOnly -Source all -Limit 5
    $script:Fake.Calls[0].Path | Should -Be '/nodes/pve01/tasks'
    $script:Fake.Calls[0].Query | Should -Be 'errors=1&limit=5&source=all&vmid=9001'
  }

  It 'reads a single task status, taking the node from the UPID' {
    $upid = 'UPID:pve02:000A1B2C:00112233:65000000:qmstart:100:root@pam:'
    $script:Fake.Handler = { param($Method, $Path) New-FakeResponse -Data @{ upid = 'UPID:pve02:000A1B2C:00112233:65000000:qmstart:100:root@pam:'; node = 'pve02'; status = 'running'; type = 'qmstart'; id = '100'; user = 'root@pam'; starttime = 1 } }
    $task = Get-PVETask -Upid $upid
    $script:Fake.Calls[0].Uri | Should -BeLike 'https://pve01:8006/api2/json/nodes/pve02/tasks/UPID%3Apve02%3A*/status'
    $task.State | Should -Be 'Running'
  }

  It 'rejects a value that is not a UPID' {
    { Get-PVETask -Upid 'not-a-upid' } | Should -Throw
  }
}

Describe 'Wait-PVETask' {
  BeforeEach {
    Reset-FakeState
    $null = Connect-PVE -Server pve01 -Credential (New-TestCredential)
    $script:Fake.Calls.Clear()
    Mock -ModuleName PVEPS Start-Sleep { }
    $script:Polls = @{}
  }

  It 'polls until the task stops and outputs it on success' {
    $script:Fake.Handler = {
      param($Method, $Path)
      $script:Polls.n = 1 + [int]$script:Polls.n
      $status = if ($script:Polls.n -lt 3) { @{ status = 'running' } } else { @{ status = 'stopped'; exitstatus = 'OK' } }
      New-FakeResponse -Data (@{ upid = 'UPID:pve01:1:2:3:qmstart:100:root@pam:'; type = 'qmstart'; id = '100' } + $status)
    }
    $task = Wait-PVETask -Upid 'UPID:pve01:1:2:3:qmstart:100:root@pam:'
    $script:Polls.n | Should -Be 3
    $task.ExitStatus | Should -Be 'OK'
    Should -Invoke -ModuleName PVEPS Start-Sleep -Times 2 -Exactly
  }

  It 'accepts task objects from the pipeline' {
    $script:Fake.Handler = { param($Method, $Path) New-FakeResponse -Data @{ upid = 'UPID:pve01:1:2:3:qmstart:100:root@pam:'; status = 'stopped'; exitstatus = 'OK' } }
    $task = Get-PVETask -Upid 'UPID:pve01:1:2:3:qmstart:100:root@pam:' | Wait-PVETask
    $task.Upid | Should -Be 'UPID:pve01:1:2:3:qmstart:100:root@pam:'
  }

  It 'writes an error and no output for a failed task' {
    $script:Fake.Handler = { param($Method, $Path) New-FakeResponse -Data @{ upid = 'UPID:pve01:1:2:3:qmstart:100:root@pam:'; status = 'stopped'; exitstatus = "can't lock file"; type = 'qmstart'; id = '100'; node = 'pve01' } }
    $errors = $null
    $out = Wait-PVETask -Upid 'UPID:pve01:1:2:3:qmstart:100:root@pam:' -ErrorVariable errors -ErrorAction SilentlyContinue
    $out | Should -BeNullOrEmpty
    $errors.Count | Should -Be 1
    $errors[0].Exception.Message | Should -Be "Task qmstart 100 on pve01 failed: can't lock file"
    $errors[0].TargetObject.ExitStatus | Should -Be "can't lock file"
  }

  It 'warns but outputs a task that finished with warnings' {
    $script:Fake.Handler = { param($Method, $Path) New-FakeResponse -Data @{ upid = 'UPID:pve01:1:2:3:vzdump::root@pam:'; status = 'stopped'; exitstatus = 'WARNINGS: 1' } }
    $warnings = $null
    $out = Wait-PVETask -Upid 'UPID:pve01:1:2:3:vzdump::root@pam:' -WarningVariable warnings -WarningAction SilentlyContinue
    $out | Should -Not -BeNullOrEmpty
    $warnings.Count | Should -Be 1
  }

  It 'times out with an error and does not cancel the task' {
    $script:Fake.Handler = { param($Method, $Path) New-FakeResponse -Data @{ upid = 'UPID:pve01:1:2:3:qmstart:100:root@pam:'; status = 'running' } }
    Mock -ModuleName PVEPS Start-Sleep { [System.Threading.Thread]::Sleep(300) }
    $errors = $null
    $out = Wait-PVETask -Upid 'UPID:pve01:1:2:3:qmstart:100:root@pam:' -TimeoutSec 1 -ErrorVariable errors -ErrorAction SilentlyContinue
    $out | Should -BeNullOrEmpty
    $errors[-1].FullyQualifiedErrorId | Should -Match '^PVETaskTimeout'
    $script:Fake.Calls.Method | Should -Not -Contain 'DELETE'
  }
}
