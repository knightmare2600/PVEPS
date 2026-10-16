function Update-PVEAuthTicket {
  <#
  .SYNOPSIS
  Obtains or renews the PVEAuthCookie ticket for a ticket-authenticated connection.
  .DESCRIPTION
  Without -ForceLogin, first tries to renew by posting the current ticket as the password (supported by
  POST /access/ticket: "The secret password. This can also be a valid ticket."). If that fails, or with
  -ForceLogin, logs in again with the stored credential.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private helper; only refreshes in-memory authentication state.')]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [psobject]$Connection,

    [switch]$ForceLogin
  )

  $state = $script:PVEAuthState[$Connection.Id]
  if ($null -eq $state -or $state.AuthType -ne 'Ticket') {
    return
  }

  $userName = $state.Credential.UserName
  $result = $null

  if (-not $ForceLogin -and $state.Ticket) {
    try {
      $result = Invoke-PVERequest -Connection $Connection -Method POST -Path '/access/ticket' -NoAuth -Parameters @{
        username = $userName
        password = $state.Ticket
      }
    }
    catch {
      Write-Verbose "Ticket renewal for $userName failed ($($_.Exception.Message)); logging in with the stored credential."
    }
  }

  if ($null -eq $result) {
    $result = Invoke-PVERequest -Connection $Connection -Method POST -Path '/access/ticket' -NoAuth -Parameters @{
      username = $userName
      password = ConvertFrom-PVESecureString -SecureString $state.Credential.Password
    }
  }

  # With two-factor authentication enabled, PVE returns a half-authenticated ticket and NeedTFA instead
  # of a usable ticket. TFA login is not supported; API tokens are the intended route for automation.
  $ticket = [string](Get-PVEValue $result 'ticket')
  $csrfToken = [string](Get-PVEValue $result 'CSRFPreventionToken')
  if ((Get-PVEValue $result 'NeedTFA') -or $ticket.Contains('!tfa!')) {
    throw "User $userName has two-factor authentication enabled, which PVEPS does not support for interactive login. Use an API token instead (Connect-PVE -Token)."
  }
  if (-not $ticket -or -not $csrfToken) {
    throw "Login to $($Connection.Server) as $userName did not return a ticket and CSRF token."
  }

  $state.Ticket = $ticket
  $state.CsrfToken = $csrfToken
  $state.TicketTime = Get-Date
}
