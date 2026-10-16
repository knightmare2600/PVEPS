# Shared fixtures for unit tests. Dot-source inside BeforeAll: . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
# Imports the module, defines the fake PVE server and mocks Invoke-WebRequest inside PVEPS.

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
