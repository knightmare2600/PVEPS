function Save-PVEApplianceTemplate {
  <#
  .SYNOPSIS
  Downloads container templates from the PVE appliance catalogue onto a storage.
  .DESCRIPTION
  Starts each download with POST /nodes/{node}/aplinfo, waits for the tasks, and writes each stored
  template as a PVEPS.StorageContent object, ready for New-PVEContainer -OSTemplate.
  .PARAMETER Template
  Template file name(s), as Get-PVEApplianceTemplate lists them. Binds from piped objects.
  .PARAMETER Storage
  Storage to save the templates on. It must allow container templates (vztmpl).
  .PARAMETER Node
  Node to download on. Binds from piped objects; can be omitted on a single-node server.
  .PARAMETER RunAsync
  Return the task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Save-PVEApplianceTemplate -Template debian-13-standard_13.1-2_amd64.tar.zst -Storage local
  .EXAMPLE
  $t = Get-PVEApplianceTemplate 'debian-13-standard*' | Save-PVEApplianceTemplate -Storage local
  New-PVEContainer -Name ct01 -OSTemplate $t.Volume -Storage local-lvm
  #>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.StorageContent', 'PVEPS.Task')]
  param(
    [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Template,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Storage,

    [Parameter(ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string]$Node,

    [switch]$RunAsync,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $operations = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    try {
      $connections = @(Resolve-PVEConnection -Server $Server)
    }
    catch {
      $PSCmdlet.WriteError($_)
      return
    }
    foreach ($connection in $connections) {
      try {
        $nodeName = Resolve-PVENodeName -Connection $connection -Node $Node
      }
      catch {
        $PSCmdlet.WriteError($_)
        continue
      }
      foreach ($name in $Template) {
        if (-not $PSCmdlet.ShouldProcess("$Storage on $nodeName", "Download appliance template $name")) {
          continue
        }
        $path = Format-PVEPath '/nodes/{node}/aplinfo' @{ node = $nodeName }
        try {
          $upid = [string](Invoke-PVERequest -Connection $connection -Method POST -Path $path -Parameters @{ storage = $Storage; template = $name })
        }
        catch {
          $PSCmdlet.WriteError($_)
          continue
        }
        $operations.Add([pscustomobject]@{ Upid = $upid; Connection = $connection; Node = $nodeName; Template = $name })
      }
    }
  }

  end {
    if ($RunAsync) {
      foreach ($op in $operations) {
        if ($op.Upid -match '^UPID:') {
          Get-PVETask -Upid $op.Upid -Server $op.Connection
        }
      }
      return
    }
    foreach ($op in @(Wait-PVEOperation -Operation $operations)) {
      try {
        Find-PVEStoredFile -Connection $op.Connection -Node $op.Node -Storage $Storage -Content vztmpl -FileName $op.Template
      }
      catch {
        $PSCmdlet.WriteError($_)
      }
    }
  }
}
