function Resolve-PVEVolumeTarget {
  <#
  .SYNOPSIS
  Turns -Volume / -Node / -Server values from a storage content cmdlet into { Connection; Node; Storage;
  Volume } entries. The storage is the part of the volume ID before the first colon (PVE volume IDs are
  <storage>:<volume name>). Without -Node, the server's only node is used.
  #>
  [CmdletBinding()]
  [OutputType([psobject])]
  param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCmdlet]$Cmdlet,

    [Parameter(Mandatory)]
    [string[]]$Volume,

    [AllowNull()]
    [string]$Node,

    [AllowNull()]
    [object[]]$Server
  )

  try {
    $connections = @(Resolve-PVEConnection -Server $Server)
  }
  catch {
    $Cmdlet.WriteError($_)
    return
  }
  foreach ($connection in $connections) {
    try {
      $nodeName = Resolve-PVENodeName -Connection $connection -Node $Node
    }
    catch {
      $Cmdlet.WriteError($_)
      continue
    }
    foreach ($item in $Volume) {
      if ($item -notmatch '^([^:]+):.+') {
        $Cmdlet.WriteError((New-PVEArgumentError -Message "'$item' is not a volume ID (<storage>:<volume name>)." -Target $item))
        continue
      }
      [pscustomobject]@{ Connection = $connection; Node = $nodeName; Storage = $Matches[1]; Volume = $item }
    }
  }
}
