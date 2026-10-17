function Invoke-PVEGuestChange {
  <#
  .SYNOPSIS
  Sends one configuration change (or resize) for a guest, after ShouldProcess, and waits for its task.
  Returns $true if the change went through.
  .DESCRIPTION
  -Endpoint config: POST /nodes/{node}/qemu/{vmid}/config (the asynchronous call, which the API
  documentation recommends for hotplug and storage allocation) or PUT /nodes/{node}/lxc/{vmid}/config.
  -Endpoint resize: PUT /nodes/{node}/{type}/{vmid}/resize.
  -Endpoint cloudinit: PUT /nodes/{node}/qemu/{vmid}/cloudinit (regenerate the cloud-init drive).
  Errors are written on the calling cmdlet; a failed task is an error from Wait-PVETask.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Calls ShouldProcess on the calling public cmdlet, passed as -Cmdlet, so its -WhatIf and -Confirm apply.')]
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCmdlet]$Cmdlet,

    [Parameter(Mandatory)]
    [psobject]$Guest,

    [Parameter(Mandatory)]
    [string]$Description,

    [Parameter(Mandatory)]
    [hashtable]$Body,

    [ValidateSet('config', 'resize', 'cloudinit')]
    [string]$Endpoint = 'config'
  )

  if (-not $Cmdlet.ShouldProcess((Get-PVEGuestLabel -Guest $Guest), $Description)) {
    return $false
  }
  $method = if ($Endpoint -eq 'config' -and $Guest.Type -eq 'qemu') { 'POST' } else { 'PUT' }
  $path = Format-PVEPath "/nodes/{node}/{type}/{vmid}/$Endpoint" @{ node = $Guest.Node; type = $Guest.Type; vmid = $Guest.VMId }
  try {
    $result = [string](Invoke-PVERequest -Connection $Guest.Connection -Method $method -Path $path -Parameters $Body)
  }
  catch {
    $Cmdlet.WriteError($_)
    return $false
  }
  Write-Verbose "$Description on $(Get-PVEGuestLabel -Guest $Guest): $(if ($result) { "task $result" } else { 'done' })"
  if ($result -match '^UPID:') {
    $finished = @([pscustomobject]@{ Upid = $result; Connection = $Guest.Connection } | Wait-PVETask)
    return $finished.Count -gt 0
  }
  $true
}
