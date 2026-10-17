function Get-PVEEvent {
  <#
  .SYNOPSIS
  Gets recent entries of the PVE cluster log: logins, task starts and ends, and other events.
  .DESCRIPTION
  Reads GET /cluster/log (which standalone nodes have too) and writes one PVEPS.Event object per entry,
  newest first. The API schema does not describe the entries; Time, Node, User, Tag, Severity and
  Message are read from the fields the PVE web interface's cluster log uses (time, node, user, tag, pri,
  msg), and are empty if PVE leaves one out. Severity is the syslog priority number (0 emergency to 7
  debug). For task details, Get-PVETask reads the task list itself.
  .PARAMETER MaxEntries
  Maximum number of entries PVE returns. PVE's default applies if omitted.
  .PARAMETER Start
  Only entries at or after this time.
  .PARAMETER Finish
  Only entries at or before this time.
  .PARAMETER Node
  Only entries from these nodes. Wildcards allowed.
  .PARAMETER User
  Only entries for these users, for example 'root@pam'. Wildcards allowed.
  .PARAMETER Message
  Only entries whose message matches. Wildcards allowed.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection.
  .EXAMPLE
  Get-PVEEvent -Start (Get-Date).AddHours(-1)
  .EXAMPLE
  Get-PVEEvent -MaxEntries 500 -Message '*authentication failure*'
  #>
  [CmdletBinding()]
  [OutputType('PVEPS.Event')]
  param(
    [ValidateRange(1, [int]::MaxValue)]
    [int]$MaxEntries,

    [datetime]$Start,

    [datetime]$Finish,

    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Node,

    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$User,

    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Message,

    [Alias('Connection')]
    [object[]]$Server
  )

  try {
    $connections = @(Resolve-PVEConnection -Server $Server)
  }
  catch {
    $PSCmdlet.WriteError($_)
    return
  }
  $parameters = @{}
  if ($MaxEntries) {
    $parameters.max = $MaxEntries
  }
  foreach ($connection in $connections) {
    try {
      $entries = @(Invoke-PVERequest -Connection $connection -Path '/cluster/log' -Parameters $parameters)
    }
    catch {
      $PSCmdlet.WriteError($_)
      continue
    }
    $events = foreach ($entry in $entries) {
      $time = Get-PVEValue $entry 'time'
      $when = if ($null -ne $time) { ConvertFrom-PVEUnixTime $time } else { $null }
      if ($PSBoundParameters.ContainsKey('Start') -and ($null -eq $when -or $when -lt $Start)) {
        continue
      }
      if ($PSBoundParameters.ContainsKey('Finish') -and ($null -eq $when -or $when -gt $Finish)) {
        continue
      }
      $item = [pscustomobject]@{
        PSTypeName = 'PVEPS.Event'
        Time       = $when
        Node       = Get-PVEValue $entry 'node'
        User       = Get-PVEValue $entry 'user'
        Tag        = Get-PVEValue $entry 'tag'
        Severity   = Get-PVEValue $entry 'pri'
        Message    = ([string](Get-PVEValue $entry 'msg')).TrimEnd()
        Connection = $connection
      }
      if ((Test-PVEWildcardMatch -Value $item.Node -Pattern $Node) -and (Test-PVEWildcardMatch -Value $item.User -Pattern $User) -and (Test-PVEWildcardMatch -Value $item.Message -Pattern $Message)) {
        $item
      }
    }
    @($events) | Sort-Object -Property @{ Expression = { if ($_.Time) { $_.Time } else { [datetime]::MinValue } }; Descending = $true }
  }
}
