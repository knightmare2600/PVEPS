function Invoke-PVEGuestClone {
  <#
  .SYNOPSIS
  Shared engine for Copy-PVEVM and Copy-PVEContainer.
  .DESCRIPTION
  Resolves the collected targets to exactly one source guest (templates included, by ID or name), picks
  the new ID (Get-PVENewVMId), asks ShouldProcess on the calling cmdlet, then POSTs
  /nodes/{node}/{type}/{vmid}/clone. Complete-PVEOperation waits for the task and writes the new guest,
  or the task with -RunAsync.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Calls ShouldProcess on the calling public cmdlet, passed as -Cmdlet, so its -WhatIf and -Confirm apply.')]
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCmdlet]$Cmdlet,

    [Parameter(Mandatory)]
    [ValidateSet('qemu', 'lxc')]
    [string]$Type,

    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [System.Collections.Generic.List[psobject]]$Target,

    [Parameter(Mandatory)]
    [string]$NewName,

    [int]$NewVMId,

    # Clone options other than newid and the name, by their API names.
    [Parameter(Mandatory)]
    [hashtable]$Parameters,

    [switch]$RunAsync
  )

  $kind = if ($Type -eq 'qemu') { 'VM' } else { 'Container' }
  $sources = @(Resolve-PVEGuestTarget -Cmdlet $Cmdlet -Type $Type -Target $Target -IncludeTemplate)
  if ($sources.Count -eq 0) {
    return
  }
  if ($sources.Count -gt 1) {
    $Cmdlet.WriteError((New-PVEArgumentError -Message ('The source matched {0} guests ({1}); clone one source at a time.' -f $sources.Count, (@($sources | ForEach-Object { $_.VMId }) -join ', ')) -Target $sources))
    return
  }
  $source = $sources[0]

  try {
    $id = Get-PVENewVMId -Connection $source.Connection -VMId $NewVMId
  }
  catch {
    $Cmdlet.WriteError($_)
    return
  }

  $body = @{ newid = $id } + $Parameters
  $body[$(if ($Type -eq 'lxc') { 'hostname' } else { 'name' })] = $NewName

  $mode = if ($Parameters.ContainsKey('full')) { 'full clone' } elseif ($source.IsTemplate) { 'linked clone' } else { 'full clone' }
  $action = 'Clone ({0}) to {1} {2} ({3})' -f $mode, $kind, $id, $NewName
  if (-not $Cmdlet.ShouldProcess((Get-PVEGuestLabel -Guest $source), $action)) {
    return
  }

  $path = Format-PVEPath '/nodes/{node}/{type}/{vmid}/clone' @{ node = $source.Node; type = $Type; vmid = $source.VMId }
  try {
    $upid = Invoke-PVERequest -Connection $source.Connection -Method POST -Path $path -Parameters $body
  }
  catch {
    $Cmdlet.WriteError($_)
    return
  }
  Write-Verbose "$action`: task $upid"

  $operations = [System.Collections.Generic.List[psobject]]::new()
  $pool = if ($Parameters.ContainsKey('pool')) { [string]$Parameters.pool } else { $null }
  $operations.Add([pscustomobject]@{ Upid = [string]$upid; Connection = $source.Connection; Guest = $null; Type = $Type; Node = $source.Node; VMId = $id; Pool = $pool })
  Complete-PVEOperation -Cmdlet $Cmdlet -Operation $operations -RunAsync:$RunAsync
}
