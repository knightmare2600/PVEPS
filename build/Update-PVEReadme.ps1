#Requires -Version 7.4
<#
.SYNOPSIS
Regenerates the cmdlet index and cmdlet reference in README.md from the module's comment-based help.
.DESCRIPTION
The comment-based help in Public/*.ps1 is the single source for the cmdlet documentation. This script
imports the module from the repository, reads each cmdlet's help, parameter metadata (parameter sets,
types, validation, pipeline binding, defaults) and ShouldProcess settings, and rewrites the parts of
README.md between these marker pairs:

  <!-- cmdlet-index:start -->      <!-- cmdlet-index:end -->
  <!-- cmdlet-reference:start -->  <!-- cmdlet-reference:end -->

Everything outside the markers is left as it is. Every exported cmdlet must appear in exactly one group
in $Groups below; the script stops if one is missing or listed twice.

With -Check it changes nothing and fails if README.md is out of date (the unit tests run it this way).
.PARAMETER Check
Compare instead of writing; throw if README.md differs from what would be generated.
.EXAMPLE
pwsh ./build/Update-PVEReadme.ps1
.EXAMPLE
pwsh ./build/Update-PVEReadme.ps1 -Check
#>
[CmdletBinding()]
param(
  [switch]$Check
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Path $PSScriptRoot -Parent
$readmePath = Join-Path -Path $root -ChildPath 'README.md'
Import-Module (Join-Path -Path $root -ChildPath 'PVEPS.psd1') -Force -Verbose:$false

$Groups = [ordered]@{
  'Connections and the raw API'      = 'Connect-PVE', 'Disconnect-PVE', 'Get-PVEConnection', 'Invoke-PVEApi'
  'Tasks'                            = 'Get-PVETask', 'Wait-PVETask'
  'Inventory'                        = 'Get-PVENode', 'Get-PVEVM', 'Get-PVEContainer', 'Get-PVEStorage', 'Get-PVEPool'
  'VM power'                         = 'Start-PVEVM', 'Stop-PVEVMGuest', 'Stop-PVEVM', 'Restart-PVEVMGuest', 'Restart-PVEVM',
  'Suspend-PVEVM', 'Resume-PVEVM'
  'Container power'                  = 'Start-PVEContainer', 'Stop-PVEContainerGuest', 'Stop-PVEContainer', 'Restart-PVEContainer'
  'VM lifecycle'                     = 'New-PVEVM', 'Set-PVEVM', 'Copy-PVEVM', 'Move-PVEVM', 'ConvertTo-PVEVMTemplate', 'Remove-PVEVM'
  'Container lifecycle'              = 'New-PVEContainer', 'Set-PVEContainer', 'Copy-PVEContainer', 'Move-PVEContainer',
  'ConvertTo-PVEContainerTemplate', 'Remove-PVEContainer'
  'VM hardware'                      = 'Get-PVEVMHardDisk', 'New-PVEVMHardDisk', 'Set-PVEVMHardDisk', 'Remove-PVEVMHardDisk',
  'Get-PVEVMNetworkAdapter', 'New-PVEVMNetworkAdapter', 'Set-PVEVMNetworkAdapter', 'Remove-PVEVMNetworkAdapter',
  'Get-PVEVMCDDrive', 'New-PVEVMCDDrive', 'Set-PVEVMCDDrive', 'Remove-PVEVMCDDrive', 'Get-PVEVMCloudInit', 'Set-PVEVMCloudInit'
  'Container hardware'               = 'Get-PVEContainerVolume', 'New-PVEContainerVolume', 'Set-PVEContainerVolume',
  'Remove-PVEContainerVolume', 'Get-PVEContainerNetworkAdapter', 'New-PVEContainerNetworkAdapter',
  'Set-PVEContainerNetworkAdapter', 'Remove-PVEContainerNetworkAdapter'
  'Snapshots'                        = 'Get-PVEVMSnapshot', 'New-PVEVMSnapshot', 'Set-PVEVMSnapshot', 'Restore-PVEVMSnapshot',
  'Remove-PVEVMSnapshot', 'Get-PVEContainerSnapshot', 'New-PVEContainerSnapshot', 'Set-PVEContainerSnapshot',
  'Restore-PVEContainerSnapshot', 'Remove-PVEContainerSnapshot'
  'Guest agent and console'          = 'Get-PVEVMGuest', 'Invoke-PVEVMScript', 'Copy-PVEVMGuestFile', 'Open-PVEVMConsole',
  'Open-PVEContainerConsole'
  'Storage content and templates'    = 'Get-PVEStorageContent', 'Import-PVEStorageContent', 'Set-PVEStorageContent',
  'Remove-PVEStorageContent', 'Get-PVEApplianceTemplate', 'Save-PVEApplianceTemplate'
  'Backup and restore'               = 'Backup-PVEVM', 'Backup-PVEContainer', 'Get-PVEBackup', 'Restore-PVEBackup'
  'Statistics and events'            = 'Get-PVEVMStat', 'Get-PVEContainerStat', 'Get-PVENodeStat', 'Get-PVEStorageStat', 'Get-PVEEvent'
}

$exported = @((Get-Module PVEPS).ExportedFunctions.Keys | Sort-Object)
$listed = @($Groups.Values | ForEach-Object { $_ })
$duplicates = @($listed | Group-Object | Where-Object Count -GT 1 | ForEach-Object Name)
$missing = @($exported | Where-Object { $_ -notin $listed })
$unknown = @($listed | Where-Object { $_ -notin $exported })
if ($duplicates -or $missing -or $unknown) {
  throw ('README groups do not match the exported cmdlets. Listed twice: {0}. Not listed: {1}. Not exported: {2}.' -f
    ($duplicates -join ', '), ($missing -join ', '), ($unknown -join ', '))
}

$commonNames = [System.Management.Automation.PSCmdlet]::CommonParameters +
[System.Management.Automation.PSCmdlet]::OptionalCommonParameters

function ConvertTo-MarkdownText {
  # Help text is plain text. URLs go into code spans, so placeholders such as <server> show as written
  # and GitHub does not autolink part of them; elsewhere the characters Markdown treats as markup are
  # escaped.
  param([string]$Text)
  $parts = [regex]::Split($Text, '(https?://[^\s)]*)')
  $converted = for ($i = 0; $i -lt $parts.Count; $i++) {
    if ($i % 2) {
      '`{0}`' -f $parts[$i]
    }
    else {
      $parts[$i] -replace '\\', '\\' -replace '\*', '\*' -replace '<', '&lt;' -replace '>', '&gt;' -replace '\|', '\|'
    }
  }
  $converted -join ''
}

function Get-Anchor {
  # GitHub heading anchors: lower case, spaces to hyphens, other punctuation dropped.
  param([string]$Heading)
  ($Heading.ToLowerInvariant() -replace '[^a-z0-9 \-]', '') -replace ' ', '-'
}

function Split-SyntaxToken {
  # Splits a parameter-set syntax string at the spaces between parameters, not inside [...] or <...>.
  param([string]$Syntax)
  $tokens = [System.Collections.Generic.List[string]]::new()
  $current = [System.Text.StringBuilder]::new()
  $depth = 0
  for ($i = 0; $i -lt $Syntax.Length; $i++) {
    $char = $Syntax[$i]
    if ($char -in '[', '<') { $depth++ }
    if ($char -in ']', '>') { $depth-- }
    $next = if ($i + 1 -lt $Syntax.Length) { $Syntax[$i + 1] } else { '' }
    if ($char -eq ' ' -and $depth -eq 0 -and $next -in '[', '-') {
      $tokens.Add($current.ToString())
      $null = $current.Clear()
      continue
    }
    $null = $current.Append($char)
  }
  if ($current.Length) {
    $tokens.Add($current.ToString())
  }
  $tokens
}

function Format-Syntax {
  # One line per parameter set, wrapped at 110 columns with a four-space hanging indent.
  param([string]$Name, [string]$Syntax)
  $lines = [System.Collections.Generic.List[string]]::new()
  $line = $Name
  foreach ($token in Split-SyntaxToken -Syntax $Syntax) {
    if (($line.Length + 1 + $token.Length) -gt 110 -and $line.Trim()) {
      $lines.Add($line)
      $line = '    ' + $token
    }
    else {
      $line = $line + ' ' + $token
    }
  }
  $lines.Add($line)
  $lines -join "`n"
}

function Get-ParameterDefault {
  param($Command)
  $defaults = @{}
  $ast = $Command.ScriptBlock.Ast
  $paramBlock = if ($ast.PSObject.Properties['Body'] -and $ast.Body.ParamBlock) { $ast.Body.ParamBlock } else { $ast.ParamBlock }
  if ($paramBlock) {
    foreach ($parameter in $paramBlock.Parameters) {
      if ($parameter.DefaultValue) {
        $defaults[$parameter.Name.VariablePath.UserPath] = $parameter.DefaultValue.Extent.Text
      }
    }
  }
  $defaults
}

function Format-TypeName {
  param([type]$Type)
  if ($Type -eq [switch]) { return 'SwitchParameter' }
  $Type.Name
}

function Get-ParameterFact {
  # The metadata line under each parameter: required, position, pipeline, wildcards, aliases, values,
  # range and default.
  param($Parameter, [hashtable]$Defaults, [string[]]$SetNames)
  $facts = [System.Collections.Generic.List[string]]::new()
  $attributes = @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
  $visibleSets = @($attributes | ForEach-Object {
      if ($_.ParameterSetName -eq '__AllParameterSets') { $SetNames } else { $_.ParameterSetName }
    } | Select-Object -Unique)
  $mandatorySets = @($attributes | Where-Object Mandatory | ForEach-Object {
      if ($_.ParameterSetName -eq '__AllParameterSets') { $SetNames } else { $_.ParameterSetName }
    } | Select-Object -Unique)

  if ($mandatorySets.Count -eq 0) {
    $facts.Add('Required: no')
  }
  elseif ($SetNames.Count -le 1 -or $mandatorySets.Count -eq $visibleSets.Count) {
    $facts.Add('Required: yes')
  }
  else {
    $facts.Add(('Required: in the {0} set{1}' -f ($mandatorySets -join ', '), $(if ($mandatorySets.Count -gt 1) { 's' })))
  }
  if ($SetNames.Count -gt 1 -and $visibleSets.Count -lt $SetNames.Count) {
    $facts.Add(('Parameter set{0}: {1}' -f $(if ($visibleSets.Count -gt 1) { 's' }), ($visibleSets -join ', ')))
  }

  $positions = @($attributes | Where-Object { $_.Position -ge 0 } | ForEach-Object Position | Select-Object -Unique)
  if ($positions.Count) {
    $ordinal = foreach ($position in $positions) {
      switch ($position + 1) { 1 { 'first' } 2 { 'second' } 3 { 'third' } default { "number $_" } }
    }
    $facts.Add(('Position: {0}' -f ($ordinal -join ', ')))
  }
  else {
    $facts.Add('Position: named')
  }

  $byValue = @($attributes | Where-Object ValueFromPipeline).Count -gt 0
  $byName = @($attributes | Where-Object ValueFromPipelineByPropertyName).Count -gt 0
  if ($byValue -and $byName) {
    $facts.Add('Pipeline: by value and by property name')
  }
  elseif ($byValue) {
    $facts.Add('Pipeline: by value')
  }
  elseif ($byName) {
    $facts.Add('Pipeline: by property name')
  }

  if (@($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.SupportsWildcardsAttribute] }).Count) {
    $facts.Add('Wildcards: yes')
  }
  if ($Parameter.Aliases.Count) {
    $facts.Add(('Alias: {0}' -f (($Parameter.Aliases | ForEach-Object { "-$_" }) -join ', ')))
  }
  $set = @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })
  if ($set.Count) {
    $facts.Add(('Values: {0}' -f ($set[0].ValidValues -join ', ')))
  }
  $range = @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] })
  if ($range.Count -and $null -ne $range[0].MinRange) {
    $facts.Add(('Range: {0} to {1}' -f $range[0].MinRange, $range[0].MaxRange))
  }
  if ($Defaults.ContainsKey($Parameter.Name)) {
    $facts.Add(('Default: {0}' -f $Defaults[$Parameter.Name]))
  }
  $facts -join " `u{00B7} "
}

function Get-HelpText {
  param($Item)
  ((@($Item) | Where-Object { $_ } | ForEach-Object { $_.Text }) -join "`n").Trim()
}

$index = [System.Text.StringBuilder]::new()
$reference = [System.Text.StringBuilder]::new()

foreach ($group in $Groups.Keys) {
  $null = $index.AppendLine("**[$group](#$(Get-Anchor $group))**").AppendLine()
  $null = $index.AppendLine('| Cmdlet | Purpose |').AppendLine('|---|---|')
  $null = $reference.AppendLine("### $group").AppendLine()

  foreach ($name in $Groups[$group]) {
    $command = Get-Command -Name $name -Module PVEPS
    $help = Get-Help -Name $name -Full
    $synopsis = ([string]$help.Synopsis).Trim()
    $null = $index.AppendLine(('| [`{0}`](#{1}) | {2} |' -f $name, (Get-Anchor $name), (ConvertTo-MarkdownText $synopsis)))

    $null = $reference.AppendLine("#### $name").AppendLine()
    $null = $reference.AppendLine((ConvertTo-MarkdownText $synopsis)).AppendLine()
    $description = Get-HelpText $help.description
    if ($description) {
      $null = $reference.AppendLine((ConvertTo-MarkdownText $description)).AppendLine()
    }

    $binding = @($command.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] })
    if ($binding.Count -and $binding[0].SupportsShouldProcess) {
      if ($binding[0].ConfirmImpact -eq 'High') {
        $null = $reference.AppendLine('**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.').AppendLine()
      }
      else {
        $null = $reference.AppendLine('**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.').AppendLine()
      }
    }

    $sets = @($command.ParameterSets)
    $setNames = @($sets | ForEach-Object Name)
    $null = $reference.AppendLine('**Syntax**').AppendLine().AppendLine('```text')
    $first = $true
    foreach ($set in $sets) {
      if (-not $first) {
        $null = $reference.AppendLine()
      }
      $first = $false
      if ($sets.Count -gt 1) {
        $null = $reference.AppendLine("# Parameter set: $($set.Name)$(if ($set.IsDefault) { ' (default)' })")
      }
      $null = $reference.AppendLine((Format-Syntax -Name $name -Syntax $set.ToString()))
    }
    $null = $reference.AppendLine('```').AppendLine()

    $parameters = @($command.Parameters.Values | Where-Object { $_.Name -notin $commonNames })
    if ($parameters.Count) {
      # Help lists parameters in declaration order; keep that order.
      $helpParameters = @($help.parameters.parameter)
      $order = @{}
      for ($i = 0; $i -lt $helpParameters.Count; $i++) {
        $order[[string]$helpParameters[$i].name] = $i
      }
      $defaults = Get-ParameterDefault -Command $command
      $null = $reference.AppendLine('**Parameters**').AppendLine()
      foreach ($parameter in $parameters | Sort-Object { if ($order.ContainsKey($_.Name)) { $order[$_.Name] } else { 999 } }) {
        $helpParameter = @($helpParameters | Where-Object { $_.name -eq $parameter.Name })
        $text = if ($helpParameter.Count) { Get-HelpText $helpParameter[0].description } else { '' }
        $null = $reference.AppendLine(('- **`-{0}`** `{1}`' -f $parameter.Name, (Format-TypeName $parameter.ParameterType)))
        foreach ($line in (ConvertTo-MarkdownText $text) -split "`n") {
          $null = $reference.AppendLine("  $line".TrimEnd())
        }
        $null = $reference.AppendLine().AppendLine(('  _{0}_' -f (ConvertTo-MarkdownText (Get-ParameterFact -Parameter $parameter -Defaults $defaults -SetNames $setNames))))
      }
      $null = $reference.AppendLine()
    }

    $outputs = @($command.OutputType | ForEach-Object Name | Select-Object -Unique)
    if ($outputs.Count) {
      $null = $reference.AppendLine(('**Output:** {0}' -f (($outputs | ForEach-Object { "``$_``" }) -join ', '))).AppendLine()
    }

    $examples = @($help.examples.example | Where-Object { $_ })
    if ($examples.Count) {
      $null = $reference.AppendLine('**Examples**').AppendLine().AppendLine('```powershell')
      foreach ($example in $examples) {
        $null = $reference.AppendLine(([string]$example.code).Trim())
      }
      $null = $reference.AppendLine('```').AppendLine()
    }
    $null = $reference.AppendLine("[Back to the cmdlet index](#cmdlet-index)").AppendLine()
  }
  $null = $index.AppendLine()
}

function Join-Section {
  param([string]$Text, [string]$Marker, [string]$Content)
  $start = "<!-- $Marker`:start -->"
  $end = "<!-- $Marker`:end -->"
  $from = $Text.IndexOf($start)
  $to = $Text.IndexOf($end)
  if ($from -lt 0 -or $to -lt $from) {
    throw "README.md has no '$start' ... '$end' markers."
  }
  $Text.Substring(0, $from + $start.Length) + "`n" + $Content.TrimEnd() + "`n" + $Text.Substring($to)
}

# Compare and write with LF line endings, whatever the platform or git checkout setting.
$current = ([System.IO.File]::ReadAllText($readmePath)) -replace "`r`n", "`n"
$updated = Join-Section -Text $current -Marker 'cmdlet-index' -Content ($index.ToString() -replace "`r`n", "`n")
$updated = Join-Section -Text $updated -Marker 'cmdlet-reference' -Content ($reference.ToString() -replace "`r`n", "`n")

if ($Check) {
  if ($updated -ne $current) {
    throw 'README.md is out of date with the comment-based help; run build/Update-PVEReadme.ps1.'
  }
  Write-Verbose 'README.md is up to date.'
  return
}
if ($updated -ne $current) {
  [System.IO.File]::WriteAllText($readmePath, $updated, [System.Text.UTF8Encoding]::new($false))
  Write-Verbose 'README.md updated.'
}
