function Connect-PVE {
  <#
  .SYNOPSIS
  Opens a connection to a Proxmox VE server or cluster node.
  .DESCRIPTION
  Authenticates, verifies the connection by reading /version, and returns a PVEPS.Connection object.
  Unless -NotDefault is given, the new connection becomes the default used by every cmdlet that is not
  passed -Server.

  Credentials can be given as -User and -Password, or as a PSCredential with -Credential. If -Password is
  left out, it is prompted for without echoing.

  By default the credentials are a user name and password (ticket authentication). The ticket is renewed
  automatically before it expires, and the credential is held in memory for the life of the connection so
  the module can log in again if renewal fails. Users with two-factor authentication enabled cannot use
  ticket authentication; use an API token.

  With -Token, the same inputs are an API token instead: the user name is the full token ID
  (user@realm!tokenname) and the password is the token secret.
  .PARAMETER Server
  Host name or IP address (IPv4 or IPv6) of the PVE node. Do not include https:// or a port.
  .PARAMETER Port
  API port. Defaults to 8006.
  .PARAMETER User
  User name with realm (for example root@pam or admin@pve), or with -Token the full token ID
  (for example automation@pve!pveps).
  .PARAMETER Password
  Password, or with -Token the token secret. Accepts a string or a SecureString. Prompted for if omitted.
  A plain string typed on the command line can end up in shell history; prefer the prompt or a
  SecureString in interactive use.
  .PARAMETER Credential
  PSCredential holding the user name and password, or with -Token the token ID and secret.
  .PARAMETER Token
  Treat the user name and password as an API token ID and secret instead of a login.
  .PARAMETER SkipCertificateCheck
  Do not validate the server's TLS certificate, for this connection only. Needed for the self-signed
  certificate a fresh PVE install uses.
  .PARAMETER NotDefault
  Do not make this connection the default.
  .EXAMPLE
  Connect-PVE -Server pve01.example.com -User root@pam
  Prompts for the password.
  .EXAMPLE
  Connect-PVE -Server pve01.example.com -User root@pam -Password 'secret' -SkipCertificateCheck
  .EXAMPLE
  Connect-PVE -Server 192.0.2.10 -User 'automation@pve!pveps' -Password $tokenSecret -Token
  .EXAMPLE
  Connect-PVE -Server pve01.example.com -Credential (Get-Credential root@pam)
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Password', Justification = 'Deliberately accepts a string or a SecureString; converted to SecureString immediately.')]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '', Justification = 'User and password parameters requested as an alternative to -Credential.')]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Converts a caller-supplied plain-string -Password into a SecureString at the earliest point.')]
  [CmdletBinding(DefaultParameterSetName = 'UserPassword')]
  [OutputType('PVEPS.Connection')]
  param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Server,

    [ValidateRange(1, 65535)]
    [int]$Port = 8006,

    [Parameter(Mandatory, ParameterSetName = 'UserPassword')]
    [Alias('Username')]
    [ValidateNotNullOrEmpty()]
    [string]$User,

    [Parameter(ParameterSetName = 'UserPassword')]
    [ValidateScript({ $_ -is [string] -or $_ -is [securestring] }, ErrorMessage = 'Password must be a string or a SecureString.')]
    [object]$Password,

    [Parameter(Mandatory, ParameterSetName = 'Credential')]
    [pscredential]
    [System.Management.Automation.Credential()]
    $Credential,

    [switch]$Token,

    [switch]$SkipCertificateCheck,

    [switch]$NotDefault
  )

  if ($Server -match '^[a-z]+://' -or $Server -match '/') {
    throw "Server must be a host name or IP address only, not a URL: '$Server'. Use -Port for a non-default port."
  }

  $hostPart = $Server
  if ($Server.Contains(':') -and -not $Server.StartsWith('[')) {
    # Bare IPv6 address.
    $hostPart = "[$Server]"
  }

  if ($PSCmdlet.ParameterSetName -eq 'UserPassword') {
    if ($null -eq $Password) {
      $prompt = if ($Token) { "Token secret for $User" } else { "Password for $User" }
      $Password = Read-Host -Prompt $prompt -AsSecureString
    }
    if ($Password -is [string]) {
      if ($Password.Length -eq 0) {
        throw 'Password is empty.'
      }
      $Password = ConvertTo-SecureString -String $Password -AsPlainText -Force
    }
    $Credential = [pscredential]::new($User, $Password)
  }

  if ((ConvertFrom-PVESecureString -SecureString $Credential.Password).Length -eq 0) {
    throw $(if ($Token) { 'Token secret is empty.' } else { 'Password is empty.' })
  }

  if (-not $Token) {
    if ($Credential.UserName.Contains('!')) {
      throw "'$($Credential.UserName)' looks like an API token ID. Add -Token to authenticate with a token."
    }
    if ($Credential.UserName -notmatch '^[^@\s]+@[^@\s]+$') {
      throw "User name must include the realm, for example root@pam or admin@pve (got '$($Credential.UserName)'). For an API token, add -Token."
    }
    $state = @{
      AuthType   = 'Ticket'
      Credential = $Credential
      Ticket     = $null
      CsrfToken  = $null
      TicketTime = [datetime]::MinValue
    }
  }
  else {
    if ($Credential.UserName -notmatch '^[^@\s]+@[^@!\s]+![A-Za-z][A-Za-z0-9.\-_]+$') {
      throw "With -Token, the user name must be the full token ID in the form user@realm!tokenname (got '$($Credential.UserName)')."
    }
    $state = @{
      AuthType    = 'ApiToken'
      TokenHeader = 'PVEAPIToken={0}={1}' -f $Credential.UserName, (ConvertFrom-PVESecureString -SecureString $Credential.Password)
    }
  }
  $user = $Credential.UserName

  $connection = [pscustomobject]@{
    PSTypeName           = 'PVEPS.Connection'
    Id                   = [guid]::NewGuid().ToString()
    Server               = $Server
    Port                 = $Port
    BaseUri              = 'https://{0}:{1}' -f $hostPart, $Port
    User                 = $user
    AuthType             = $state.AuthType
    Version              = $null
    Release              = $null
    SkipCertificateCheck = [bool]$SkipCertificateCheck
    ConnectedAt          = Get-Date
    IsConnected          = $false
  }

  $script:PVEAuthState[$connection.Id] = $state
  try {
    if ($state.AuthType -eq 'Ticket') {
      Write-Verbose "Requesting ticket from $($connection.BaseUri) for $user"
      Update-PVEAuthTicket -Connection $connection -ForceLogin
    }
    $version = Invoke-PVERequest -Connection $connection -Path '/version' -NoRetry
  }
  catch {
    $script:PVEAuthState.Remove($connection.Id)
    $PSCmdlet.ThrowTerminatingError($_)
  }

  $connection.Version = [string](Get-PVEValue $version 'version')
  $connection.Release = [string](Get-PVEValue $version 'release')
  $connection.IsConnected = $true

  $script:PVEConnections.Add($connection)
  if (-not $NotDefault) {
    $script:DefaultPVEConnection = $connection
  }

  $connection
}
