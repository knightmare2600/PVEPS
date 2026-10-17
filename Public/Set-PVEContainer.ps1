function Set-PVEContainer {
  <#
  .SYNOPSIS
  Changes the configuration of LXC containers.
  .DESCRIPTION
  Sends the changes with PUT /nodes/{node}/lxc/{vmid}/config (a synchronous call; there is no task) and
  writes each container with its live status.

  On a running container, PVE either applies a change at once or stores it as pending until the
  container is next started. After the change, a warning lists the options still pending on a running
  container (read from GET .../pending).

  Only the options given are changed. -Parameter reaches any other option by its API name.
  .PARAMETER Name
  Container name(s). Wildcards allowed.
  .PARAMETER VMId
  Container ID(s). Binds from piped PVEPS.Container objects.
  .PARAMETER IncludeTemplate
  Let -Name match templates as well as containers.
  .PARAMETER NewName
  New host name for the container. Only allowed when exactly one container is targeted.
  .PARAMETER Cores
  CPU cores the container may use.
  .PARAMETER MemoryGB
  Memory in GiB, sent to PVE in whole MiB.
  .PARAMETER SwapGB
  Swap in GiB, sent to PVE in whole MiB. 0 disables swap.
  .PARAMETER Description
  Description (notes). An empty string removes it.
  .PARAMETER Tags
  Tags, replacing the current ones. An empty array removes all tags.
  .PARAMETER StartOnBoot
  Whether the container starts when the node boots.
  .PARAMETER Protection
  Whether the protection flag is set. While set, PVE refuses to delete the container or its volumes.
  .PARAMETER Parameter
  Further options by their API names, for example @{ timezone = 'host' }. Applied last.
  .PARAMETER Delete
  Option names to remove from the configuration, so their PVE defaults apply, for example 'cores'.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Set-PVEContainer -VMId 200 -Cores 2 -MemoryGB 1
  .EXAMPLE
  Get-PVEContainer -Name 'dns*' | Set-PVEContainer -Tags dns, production -StartOnBoot $true
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestOperation.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.Container')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Name,

    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(ParameterSetName = 'Name')]
    [switch]$IncludeTemplate,

    [ValidateNotNullOrEmpty()]
    [string]$NewName,

    [ValidateRange(1, 8192)]
    [int]$Cores,

    [ValidateRange(0.015625, [double]::MaxValue)]
    [double]$MemoryGB,

    [ValidateRange(0, [double]::MaxValue)]
    [double]$SwapGB,

    [AllowEmptyString()]
    [string]$Description,

    [AllowEmptyCollection()]
    [string[]]$Tags,

    [bool]$StartOnBoot,

    [bool]$Protection,

    [hashtable]$Parameter,

    [ValidateNotNullOrEmpty()]
    [string[]]$Delete,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $body = @{}
    $remove = [System.Collections.Generic.List[string]]::new()
    if ($NewName) { $body.hostname = $NewName }
    if ($PSBoundParameters.ContainsKey('Cores')) { $body.cores = $Cores }
    if ($PSBoundParameters.ContainsKey('MemoryGB')) { $body.memory = ConvertTo-PVEMiB $MemoryGB }
    if ($PSBoundParameters.ContainsKey('SwapGB')) { $body.swap = ConvertTo-PVEMiB $SwapGB }
    if ($PSBoundParameters.ContainsKey('Description')) {
      if ($Description) { $body.description = $Description } else { $remove.Add('description') }
    }
    if ($PSBoundParameters.ContainsKey('Tags')) {
      if ($Tags) { $body.tags = $Tags -join ';' } else { $remove.Add('tags') }
    }
    if ($PSBoundParameters.ContainsKey('StartOnBoot')) { $body.onboot = $StartOnBoot }
    if ($PSBoundParameters.ContainsKey('Protection')) { $body.protection = $Protection }
    if ($Parameter) {
      foreach ($key in $Parameter.Keys) {
        $body[$key] = $Parameter[$key]
      }
    }
    foreach ($key in $Delete) {
      $remove.Add($key)
    }
    if ($remove.Count -gt 0) {
      $body.delete = $remove -join ','
    }
    if ($body.Count -eq 0) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message 'No change given; specify at least one setting.' -Target $null))
    }
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $Name
  }

  end {
    $guests = @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type lxc -Target $targets -IncludeTemplate:$IncludeTemplate)
    if ($NewName -and $guests.Count -gt 1) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message "-NewName gives one name, but $($guests.Count) containers are targeted; nothing was changed." -Target $guests))
    }
    $action = 'Set {0}' -f (@($body.Keys | Sort-Object) -join ', ')
    foreach ($guest in @(Invoke-PVEGuestOperation -Cmdlet $PSCmdlet -Guest $guests -Description $action -Method PUT -Suffix '/config' -Parameters $body)) {
      try {
        Write-PVEPendingWarning -Guest $guest
      }
      catch {
        $PSCmdlet.WriteError($_)
      }
      $guest
    }
  }
}
