function Get-PVEGuest {
  <#
  .SYNOPSIS
  Shared implementation of Get-PVEVM and Get-PVEContainer.
  .DESCRIPTION
  Reads every guest in one call to /cluster/resources?type=vm (present on standalone nodes as well as
  clusters), keeps the requested type, then filters by node, template, name and VMId. Non-wildcard
  names and every VMId that match nothing are reported through Write-PVENotFound on the calling cmdlet.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCmdlet]$Cmdlet,

    [Parameter(Mandatory)]
    [psobject]$Connection,

    [Parameter(Mandatory)]
    [ValidateSet('qemu', 'lxc')]
    [string]$Type,

    [string[]]$Name,

    [int[]]$VMId,

    [string[]]$Node,

    [switch]$IncludeTemplate
  )

  $kind = if ($Type -eq 'qemu') { 'VM' } else { 'Container' }

  $all = @(
    Invoke-PVERequest -Connection $Connection -Path '/cluster/resources' -Parameters @{ type = 'vm' } |
      Where-Object { (Get-PVEValue $_ 'type') -eq $Type } |
      ConvertTo-PVEGuest -Connection $Connection |
      Where-Object { Test-PVEWildcardMatch -Value $_.Node -Pattern $Node }
  )

  $candidates = @($all | Where-Object { $IncludeTemplate -or -not $_.IsTemplate })
  $result = @(
    $candidates |
      Where-Object { Test-PVEWildcardMatch -Value $_.Name -Pattern $Name } |
      Where-Object { -not $VMId -or $_.VMId -in $VMId } |
      Sort-Object -Property VMId
  )

  foreach ($guest in $result) {
    $guest
  }

  # ForEach-Object rather than member enumeration ($result.Name): under strict mode, member enumeration
  # on an empty array throws.
  $templates = @($all | Where-Object IsTemplate)
  $hint = 'It is a template; add -IncludeTemplate.'
  if ($Name) {
    $notFound = @{
      Cmdlet    = $Cmdlet
      Kind      = "$kind with name"
      Filter    = $Name
      Found     = @($result | ForEach-Object { $_.Name })
      Server    = $Connection.Server
      HintValue = @($templates | ForEach-Object { $_.Name })
      Hint      = $hint
    }
    Write-PVENotFound @notFound
  }
  if ($VMId) {
    $notFound = @{
      Cmdlet    = $Cmdlet
      Kind      = "$kind with ID"
      Filter    = $VMId
      Found     = @($result | ForEach-Object { $_.VMId })
      Server    = $Connection.Server
      HintValue = @($templates | ForEach-Object { $_.VMId })
      Hint      = $hint
    }
    Write-PVENotFound @notFound
  }
}
