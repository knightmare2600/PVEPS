function Get-PVEStorage {
  <#
  .SYNOPSIS
  Gets storage (datastores) and their capacity, per node.
  .DESCRIPTION
  Reads /nodes/{node}/storage for each node, which reports space as seen from that node. A storage defined
  for several nodes appears once per node. Capacity fields are empty for storage that is not active.

  A non-wildcard -Name that matches no storage is reported as a non-terminating "not found" error.
  .PARAMETER Name
  Storage ID(s), for example local or local-lvm. Wildcards allowed.
  .PARAMETER Node
  Only these node(s). Wildcards allowed. Binds from piped PVEPS.Node objects. Defaults to every node.
  .PARAMETER Content
  Only storage that accepts this content type, for example images (VM disks), rootdir (container
  volumes), iso, vztmpl (container templates), backup, snippets or import.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection.
  .EXAMPLE
  Get-PVEStorage
  .EXAMPLE
  Get-PVEStorage -Content iso
  #>
  [CmdletBinding()]
  [OutputType('PVEPS.Storage')]
  param(
    [Parameter(Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Name,

    [Parameter(ValueFromPipelineByPropertyName)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Node,

    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete)
        $null = $commandName, $parameterName
        'images', 'rootdir', 'iso', 'vztmpl', 'backup', 'snippets', 'import' | Where-Object { $_ -like "$wordToComplete*" }
      })]
    [ValidateNotNullOrEmpty()]
    [string]$Content,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  process {
    try {
      $connections = @(Resolve-PVEConnection -Server $Server)
    }
    catch {
      $PSCmdlet.WriteError($_)
      return
    }

    $query = @{}
    if ($Content) {
      $query.content = $Content
    }

    foreach ($connection in $connections) {
      try {
        $nodeNames = @(
          Invoke-PVERequest -Connection $connection -Path '/nodes' |
            Where-Object { (Get-PVEValue $_ 'status') -eq 'online' } |
            ForEach-Object { [string](Get-PVEValue $_ 'node') } |
            Where-Object { Test-PVEWildcardMatch -Value $_ -Pattern $Node } |
            Sort-Object
        )
      }
      catch {
        $PSCmdlet.WriteError($_)
        continue
      }

      $found = [System.Collections.Generic.List[string]]::new()
      foreach ($nodeName in $nodeNames) {
        try {
          $entries = @(Invoke-PVERequest -Connection $connection -Path (Format-PVEPath '/nodes/{node}/storage' @{ node = $nodeName }) -Parameters $query)
        }
        catch {
          $PSCmdlet.WriteError($_)
          continue
        }

        foreach ($raw in ($entries | Sort-Object -Property { Get-PVEValue $_ 'storage' })) {
          $storageName = [string](Get-PVEValue $raw 'storage')
          if (-not (Test-PVEWildcardMatch -Value $storageName -Pattern $Name)) {
            continue
          }
          $found.Add($storageName)

          $fraction = Get-PVEValue $raw 'used_fraction'
          [pscustomobject]@{
            PSTypeName  = 'PVEPS.Storage'
            Name        = $storageName
            Node        = $nodeName
            Type        = Get-PVEValue $raw 'type'
            Content     = [string[]]@(([string](Get-PVEValue $raw 'content')) -split ',' | Where-Object { $_ } | Sort-Object)
            Enabled     = [bool][int](Get-PVEValue $raw 'enabled')
            Active      = [bool][int](Get-PVEValue $raw 'active')
            Shared      = [bool][int](Get-PVEValue $raw 'shared')
            CapacityGB  = ConvertTo-PVEGB (Get-PVEValue $raw 'total')
            UsedGB      = ConvertTo-PVEGB (Get-PVEValue $raw 'used')
            FreeGB      = ConvertTo-PVEGB (Get-PVEValue $raw 'avail')
            UsedPercent = if ($null -ne $fraction) { [math]::Round([double]$fraction * 100, 1) } else { $null }
            Connection  = $connection
          }
        }
      }

      if ($Name) {
        Write-PVENotFound -Cmdlet $PSCmdlet -Kind 'Storage' -Filter $Name -Found $found.ToArray() -Server $connection.Server
      }
    }
  }
}
