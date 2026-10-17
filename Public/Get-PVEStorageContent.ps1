function Get-PVEStorageContent {
  <#
  .SYNOPSIS
  Lists what is stored on PVE storages: ISO images, container templates, backups, disk images and more.
  .DESCRIPTION
  Finds the storages with Get-PVEStorage (all of them unless -Storage or -Node narrows it, and only those
  that hold -Content if it is given), then lists each one's content with
  GET /nodes/{node}/storage/{storage}/content. Inactive storages are skipped with a warning, since PVE
  cannot list them. Writes PVEPS.StorageContent objects, newest first per storage.
  .PARAMETER Storage
  Storage name(s). Wildcards allowed. Binds from piped PVEPS.Storage objects.
  .PARAMETER Node
  Node name(s). Wildcards allowed. Binds from piped objects.
  .PARAMETER Content
  Only this type: iso, vztmpl, backup, images, rootdir, snippets or import.
  .PARAMETER VMId
  Only volumes and backups belonging to this guest ID.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Get-PVEStorageContent -Content iso
  .EXAMPLE
  Get-PVEStorage local-lvm | Get-PVEStorageContent | Sort-Object SizeGB -Descending | Select-Object -First 10
  .EXAMPLE
  Get-PVEStorageContent -Content backup -VMId 100
  #>
  [CmdletBinding()]
  [OutputType('PVEPS.StorageContent')]
  param(
    [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
    [Alias('Name')]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Storage,

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

    [ValidateRange(1, 999999999)]
    [int]$VMId,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  process {
    $find = @{ Server = $Server }
    if ($Storage) { $find.Name = $Storage }
    if ($Node) { $find.Node = $Node }
    if ($Content) { $find.Content = $Content }
    foreach ($store in @(Get-PVEStorage @find)) {
      if (-not $store.Active) {
        Write-Warning "Storage $($store.Name) on $($store.Node) is not active; skipped."
        continue
      }
      try {
        Get-PVEStorageItem -Connection $store.Connection -Node $store.Node -Storage $store.Name -Content $Content -VMId $VMId
      }
      catch {
        $PSCmdlet.WriteError($_)
      }
    }
  }
}
