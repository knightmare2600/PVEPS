function Invoke-PVEGuestOperation {
  <#
  .SYNOPSIS
  Shared engine for lifecycle cmdlets that send one request per existing guest (Remove-*, Set-*,
  ConvertTo-*Template).
  .DESCRIPTION
  For each guest (already resolved by Resolve-PVEGuestTarget):
  1. With -SkipTemplate, a guest that is already a template is skipped with a warning and written
     unchanged.
  2. With -RequireStopped, reads the live status; a guest that is not stopped is an error (PVEGuestRunning)
     naming the cmdlet that stops it.
  3. Asks ShouldProcess on the calling cmdlet, then sends -Method to /nodes/{node}/{type}/{vmid} plus
     -Suffix, with -Parameters.
  4. Complete-PVEOperation waits for the tasks (endpoints that return no task count as finished) and
     writes the guests with their live status, or the tasks with -RunAsync, or nothing with -NoOutput.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Calls ShouldProcess on the calling public cmdlet, passed as -Cmdlet, so its -WhatIf and -Confirm apply.')]
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCmdlet]$Cmdlet,

    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [psobject[]]$Guest,

    # Text for ShouldProcess and messages, for example 'Remove'.
    [Parameter(Mandatory)]
    [string]$Description,

    [Parameter(Mandatory)]
    [ValidateSet('POST', 'PUT', 'DELETE')]
    [string]$Method,

    # Appended to /nodes/{node}/{type}/{vmid}, for example '/template'. Empty for the guest itself.
    [AllowEmptyString()]
    [string]$Suffix = '',

    [hashtable]$Parameters,

    [switch]$RequireStopped,

    [switch]$SkipTemplate,

    [switch]$RunAsync,

    [switch]$NoOutput
  )

  $operations = [System.Collections.Generic.List[psobject]]::new()

  foreach ($item in $Guest) {
    $label = Get-PVEGuestLabel -Guest $item

    if ($SkipTemplate -and $item.IsTemplate) {
      Write-Warning "$label is already a template; skipped $($Description.ToLowerInvariant())."
      $item
      continue
    }

    if ($RequireStopped) {
      try {
        $null = Update-PVEGuestStatus -Guest $item
      }
      catch {
        $Cmdlet.WriteError($_)
        continue
      }
      if ($item.Status -ne 'stopped') {
        $stopCommand = if ($item.Type -eq 'lxc') { 'Stop-PVEContainerGuest or Stop-PVEContainer' } else { 'Stop-PVEVMGuest or Stop-PVEVM' }
        $Cmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new("$label is $($item.Status); stop it first with $stopCommand."),
            'PVEGuestRunning',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $item))
        continue
      }
    }

    if (-not $Cmdlet.ShouldProcess($label, $Description)) {
      continue
    }

    $path = (Format-PVEPath '/nodes/{node}/{type}/{vmid}' @{ node = $item.Node; type = $item.Type; vmid = $item.VMId }) + $Suffix
    try {
      $result = Invoke-PVERequest -Connection $item.Connection -Method $Method -Path $path -Parameters $Parameters
    }
    catch {
      $Cmdlet.WriteError($_)
      continue
    }
    Write-Verbose "$Description $label`: $(if ($result) { "task $result" } else { 'done' })"
    $operations.Add([pscustomobject]@{ Upid = [string]$result; Connection = $item.Connection; Guest = $item })
  }

  Complete-PVEOperation -Cmdlet $Cmdlet -Operation $operations -RunAsync:$RunAsync -NoOutput:$NoOutput
}
