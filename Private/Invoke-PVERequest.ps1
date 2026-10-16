function Invoke-PVERequest {
  <#
  .SYNOPSIS
  Single entry point for every call to the Proxmox VE REST API.
  .DESCRIPTION
  - Uses the /api2/json formatter.
  - Adds authentication: an API token header, or the PVEAuthCookie ticket plus a CSRFPreventionToken
    header on non-GET requests.
  - Renews a ticket that is older than $script:PVETicketRenewAfter, and on HTTP 401 logs in again once
    with the stored credential and retries.
  - Parameters are sent as a query string for GET/DELETE and as a form-encoded body for POST/PUT.
  - Any HTTP status >= 400 becomes a terminating error carrying PVE's own message (taken from the HTTP
    reason phrase, plus any per-parameter "errors" in the body).
  Returns the "data" member of the response.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [psobject]$Connection,

    [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
    [string]$Method = 'GET',

    [Parameter(Mandatory)]
    [string]$Path,

    [hashtable]$Parameters,

    # Send no authentication (used for the ticket request itself).
    [switch]$NoAuth,

    # Do not attempt a re-login and retry on HTTP 401.
    [switch]$NoRetry
  )

  if (-not $Path.StartsWith('/')) {
    $Path = "/$Path"
  }

  $state = $null
  if (-not $NoAuth) {
    $state = $script:PVEAuthState[$Connection.Id]
    if ($null -eq $state) {
      throw "The connection to $($Connection.Server) is not open. Run Connect-PVE first."
    }
    if ($state.AuthType -eq 'Ticket' -and ((Get-Date) - $state.TicketTime) -gt $script:PVETicketRenewAfter) {
      Write-Verbose "Ticket for $($Connection.Server) is older than $($script:PVETicketRenewAfter); renewing."
      Update-PVEAuthTicket -Connection $Connection
      $state = $script:PVEAuthState[$Connection.Id]
    }
  }

  $uri = '{0}/api2/json{1}' -f $Connection.BaseUri, $Path
  $form = ConvertTo-PVEFormData -Parameters $Parameters

  $request = @{
    Method               = $Method
    Headers              = @{}
    SkipHttpErrorCheck   = $true
    SkipCertificateCheck = [bool]$Connection.SkipCertificateCheck
    ErrorAction          = 'Stop'
    Verbose              = $false
    Debug                = $false
  }

  if ($Method -in 'GET', 'DELETE') {
    if ($form) {
      $uri = '{0}?{1}' -f $uri, $form
    }
  }
  elseif ($form) {
    $request.Body = $form
    $request.ContentType = 'application/x-www-form-urlencoded'
  }
  $request.Uri = $uri

  if (-not $NoAuth) {
    if ($state.AuthType -eq 'ApiToken') {
      $request.Headers['Authorization'] = $state.TokenHeader
    }
    else {
      $request.Headers['Cookie'] = 'PVEAuthCookie={0}' -f $state.Ticket
      if ($Method -ne 'GET') {
        $request.Headers['CSRFPreventionToken'] = $state.CsrfToken
      }
    }
  }

  # Never log the body: it carries passwords on /access/ticket.
  Write-Verbose ('{0} {1}{2}' -f $Method, ($Connection.BaseUri + '/api2/json' + $Path), $(if ($Method -in 'GET', 'DELETE' -and $form) { '?' + $form } else { '' }))

  try {
    $response = Invoke-WebRequest @request
  }
  catch {
    $record = [System.Management.Automation.ErrorRecord]::new(
      [System.Net.Http.HttpRequestException]::new("Unable to reach $($Connection.BaseUri): $($_.Exception.Message)", $_.Exception),
      'PVEConnectionFailed',
      [System.Management.Automation.ErrorCategory]::ConnectionError,
      $Connection.BaseUri
    )
    $PSCmdlet.ThrowTerminatingError($record)
  }

  $status = [int]$response.StatusCode
  $reason = $response.BaseResponse.ReasonPhrase

  $content = $response.Content
  if ($content -is [byte[]]) {
    $content = [System.Text.Encoding]::UTF8.GetString($content)
  }
  $body = $null
  if (-not [string]::IsNullOrWhiteSpace($content)) {
    try {
      $body = $content | ConvertFrom-Json -Depth 100
    }
    catch {
      $body = $null
    }
  }

  if ($status -eq 401 -and -not $NoAuth -and -not $NoRetry -and $state.AuthType -eq 'Ticket' -and $state.Credential) {
    Write-Verbose "HTTP 401 from $($Connection.Server); logging in again and retrying once."
    Update-PVEAuthTicket -Connection $Connection -ForceLogin
    $retry = @{
      Connection = $Connection
      Method     = $Method
      Path       = $Path
      Parameters = $Parameters
      NoRetry    = $true
    }
    return Invoke-PVERequest @retry
  }

  if ($status -ge 400) {
    $message = if ($reason) { $reason.Trim() } else { "HTTP $status" }
    $bodyMessage = ([string](Get-PVEValue $body 'message')).Trim()
    if ($bodyMessage -and $bodyMessage -ne $message) {
      $message = '{0}: {1}' -f $message, $bodyMessage
    }
    $bodyErrors = Get-PVEValue $body 'errors'
    if ($bodyErrors) {
      $details = foreach ($property in $bodyErrors.PSObject.Properties) {
        '{0}: {1}' -f $property.Name, ([string]$property.Value).Trim()
      }
      if ($details) {
        $message = '{0} ({1})' -f $message, ($details -join '; ')
      }
    }

    $category = switch ($status) {
      400 { [System.Management.Automation.ErrorCategory]::InvalidArgument }
      401 { [System.Management.Automation.ErrorCategory]::AuthenticationError }
      403 { [System.Management.Automation.ErrorCategory]::PermissionDenied }
      404 { [System.Management.Automation.ErrorCategory]::ObjectNotFound }
      default { [System.Management.Automation.ErrorCategory]::InvalidOperation }
    }
    $exception = [System.Net.Http.HttpRequestException]::new(
      ('{0} {1} failed with HTTP {2}: {3}' -f $Method, $Path, $status, $message),
      $null,
      [System.Net.HttpStatusCode]$status
    )
    $record = [System.Management.Automation.ErrorRecord]::new($exception, "PVEHttp$status", $category, $Path)
    $PSCmdlet.ThrowTerminatingError($record)
  }

  if ($null -eq $body) {
    return $null
  }
  if ($body -is [psobject] -and $body.PSObject.Properties['data']) {
    return $body.data
  }
  $body
}
