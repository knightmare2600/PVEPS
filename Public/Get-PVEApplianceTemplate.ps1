function Get-PVEApplianceTemplate {
  <#
  .SYNOPSIS
  Lists the container templates PVE can download (the appliance catalogue that pveam uses).
  .DESCRIPTION
  Reads GET /nodes/{node}/aplinfo and writes one PVEPS.ApplianceTemplate object per entry. The API schema
  does not describe the entries' fields; Template, Section, OS, Version, Package, Headline and
  Description are read from the fields PVE's own catalogue uses (template, section, os, version,
  package, headline, description), and are empty if PVE leaves one out. Save-PVEApplianceTemplate
  downloads one onto a storage.
  .PARAMETER Template
  Template file name(s) to return, for example 'debian-13-*'. Wildcards allowed.
  .PARAMETER Section
  Only templates in this section, for example system or turnkeylinux.
  .PARAMETER Node
  Node whose catalogue to read. Can be omitted on a single-node server.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection.
  .EXAMPLE
  Get-PVEApplianceTemplate -Section system | Select-Object Template, Headline
  .EXAMPLE
  Get-PVEApplianceTemplate 'debian-13-standard*' | Save-PVEApplianceTemplate -Storage local
  #>
  [CmdletBinding()]
  [OutputType('PVEPS.ApplianceTemplate')]
  param(
    [Parameter(Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Template,

    [ValidateNotNullOrEmpty()]
    [string]$Section,

    [ValidateNotNullOrEmpty()]
    [string]$Node,

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
  foreach ($connection in $connections) {
    try {
      $nodeName = Resolve-PVENodeName -Connection $connection -Node $Node
      $path = Format-PVEPath '/nodes/{node}/aplinfo' @{ node = $nodeName }
      $entries = @(Invoke-PVERequest -Connection $connection -Path $path)
    }
    catch {
      $PSCmdlet.WriteError($_)
      continue
    }
    $found = [System.Collections.Generic.List[string]]::new()
    $items = foreach ($entry in $entries) {
      $name = [string](Get-PVEValue $entry 'template')
      if (-not (Test-PVEWildcardMatch -Value $name -Pattern $Template)) {
        continue
      }
      if ($Section -and [string](Get-PVEValue $entry 'section') -ne $Section) {
        continue
      }
      $found.Add($name)
      [pscustomobject]@{
        PSTypeName  = 'PVEPS.ApplianceTemplate'
        Template    = $name
        Section     = Get-PVEValue $entry 'section'
        OS          = Get-PVEValue $entry 'os'
        Version     = Get-PVEValue $entry 'version'
        Package     = Get-PVEValue $entry 'package'
        Headline    = Get-PVEValue $entry 'headline'
        Description = Get-PVEValue $entry 'description'
        Node        = $nodeName
        Connection  = $connection
      }
    }
    @($items) | Sort-Object -Property Section, Template
    if ($Template) {
      Write-PVENotFound -Cmdlet $PSCmdlet -Kind 'Appliance template' -Filter $Template -Found $found.ToArray() -Server $connection.Server
    }
  }
}
