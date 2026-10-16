function Connect-PVE {
  <#
  .SYNOPSIS
  Opens a connection to a Proxmox VE server or cluster node.
  .DESCRIPTION
  Authenticates with either a user credential (ticket authentication) or an API token, verifies the
  connection by reading /version, and returns a PVEPS.Connection object. Unless -NotDefault is given, the
  new connection becomes the default used by every cmdlet that is not passed -Server.

  Ticket authentication: the ticket is renewed automatically before it expires, and the credential is held
  in memory for the life of the connection so the module can log in again if renewal fails. Users with
  two-factor authentication enabled cannot use ticket authentication; use an API token.

  API token authentication: pass a PSCredential whose UserName is the full token ID
  (user@realm!tokenname) and whose password is the token secret.
  .PARAMETER Server
  Host name or IP address (IPv4 or IPv6) of the PVE node. Do not include https:// or a port.
  .PARAMETER Port
  API port. Defaults to 8006.
  .PARAMETER Credential
  User credential, with the realm included in the user name (for example root@pam or admin@pve).
  .PARAMETER ApiToken
  API token as a PSCredential: UserName = 'user@realm!tokenname', Password = the token secret.
  .PARAMETER SkipCertificateCheck
  Do not validate the server's TLS certificate, for this connection only. Needed for the self-signed
  certificate a fresh PVE install uses.
  .PARAMETER NotDefault
  Do not make this connection the default.
  .EXAMPLE
  Connect-PVE -Server pve01.example.com -Credential (Get-Credential root@pam)
  .EXAMPLE
  $token = Get-Credential -UserName 'automation@pve!pveps' -Message 'Token secret'
  Connect-PVE -Server 192.0.2.10 -ApiToken $token -SkipCertificateCheck
  #>
  [CmdletBinding(DefaultParameterSetName = 'Credential')]
  [OutputType('PVEPS.Connection')]
  param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Server,

    [ValidateRange(1, 65535)]
    [int]$Port = 8006,

    [Parameter(Mandatory, ParameterSetName = 'Credential')]
    [pscredential]
    [System.Management.Automation.Credential()]
    $Credential,

    [Parameter(Mandatory, ParameterSetName = 'ApiToken')]
    [pscredential]$ApiToken,

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

  if ($PSCmdlet.ParameterSetName -eq 'Credential') {
    if ($Credential.UserName -notmatch '^[^@\s]+@[^@\s]+$') {
      throw "Credential user name must include the realm, for example root@pam or admin@pve (got '$($Credential.UserName)')."
    }
    $state = @{
      AuthType   = 'Ticket'
      Credential = $Credential
      Ticket     = $null
      CsrfToken  = $null
      TicketTime = [datetime]::MinValue
    }
    $user = $Credential.UserName
  }
  else {
    if ($ApiToken.UserName -notmatch '^[^@\s]+@[^@!\s]+![A-Za-z][A-Za-z0-9.\-_]+$') {
      throw "ApiToken user name must be the full token ID in the form user@realm!tokenname (got '$($ApiToken.UserName)')."
    }
    $secret = ConvertFrom-PVESecureString -SecureString $ApiToken.Password
    if ([string]::IsNullOrWhiteSpace($secret)) {
      throw 'ApiToken password (the token secret) is empty.'
    }
    $state = @{
      AuthType    = 'ApiToken'
      TokenHeader = 'PVEAPIToken={0}={1}' -f $ApiToken.UserName, $secret
    }
    $user = $ApiToken.UserName
  }

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
