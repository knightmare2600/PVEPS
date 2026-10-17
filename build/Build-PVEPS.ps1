#Requires -Version 7.4
#Requires -Modules Microsoft.PowerShell.PSResourceGet
<#
.SYNOPSIS
Stages, checks and packages the PVEPS module; optionally installs it for the current user or publishes it
to the PowerShell Gallery.
.DESCRIPTION
1. Checks the manifest with Test-ModuleManifest, and that FunctionsToExport lists exactly the files in
   Public/.
2. Copies the module files (manifest, root module, format and types files, Public/, Private/, LICENSE,
   README.md) to <OutputPath>/PVEPS, leaving out tests and build scripts.
3. Imports the staged copy in a separate pwsh process and checks it exports every function.
4. Builds <OutputPath>/PVEPS.<version>.nupkg with Compress-PSResource, and
   <OutputPath>/PVEPS-<version>.zip (a PVEPS folder, for copying into a module path by hand).

-Install then installs the package for the current user with Install-PSResource -Scope CurrentUser,
from a temporary repository registered on <OutputPath> and removed afterwards, so the module path is the
one PSResourceGet uses on that platform. -Publish publishes the staged module to the PowerShell Gallery
with Publish-PSResource. Publishing makes the module public and a published version cannot be replaced,
so -Publish asks for confirmation.

<OutputPath> is emptied of earlier build output (the PVEPS folder, .nupkg and .zip files) first.
.PARAMETER OutputPath
Where to put the build output. Defaults to out/ in the repository (ignored by git).
.PARAMETER Install
Install the built package for the current user.
.PARAMETER Publish
Publish to the PowerShell Gallery. Needs -ApiKey.
.PARAMETER ApiKey
PowerShell Gallery API key, for -Publish.
.EXAMPLE
pwsh ./build/Build-PVEPS.ps1
.EXAMPLE
pwsh ./build/Build-PVEPS.ps1 -Install
.EXAMPLE
pwsh ./build/Build-PVEPS.ps1 -Publish -ApiKey (Read-Host 'Gallery API key' -MaskInput)
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
  [string]$OutputPath,

  [switch]$Install,

  [switch]$Publish,

  [string]$ApiKey
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Path $PSScriptRoot -Parent
if (-not $OutputPath) {
  $OutputPath = Join-Path -Path $root -ChildPath 'out'
}
if ($Publish -and -not $ApiKey) {
  throw '-Publish needs -ApiKey.'
}

# 1. Manifest checks.
$manifestPath = Join-Path -Path $root -ChildPath 'PVEPS.psd1'
$manifest = Test-ModuleManifest -Path $manifestPath
$version = $manifest.Version.ToString()
$declared = @((Import-PowerShellDataFile -Path $manifestPath).FunctionsToExport | Sort-Object)
$public = @(Get-ChildItem -Path (Join-Path -Path $root -ChildPath 'Public') -Filter '*.ps1' -File | ForEach-Object BaseName | Sort-Object)
$difference = @(Compare-Object -ReferenceObject $public -DifferenceObject $declared)
if ($difference.Count) {
  throw ('FunctionsToExport does not match Public/: {0}' -f (($difference | ForEach-Object { '{0} {1}' -f $_.SideIndicator, $_.InputObject }) -join ', '))
}
Write-Verbose "PVEPS $version, $($public.Count) functions."

# 2. Stage.
$null = New-Item -ItemType Directory -Path $OutputPath -Force
$stage = Join-Path -Path $OutputPath -ChildPath 'PVEPS'
$nupkg = Join-Path -Path $OutputPath -ChildPath "PVEPS.$version.nupkg"
$zip = Join-Path -Path $OutputPath -ChildPath "PVEPS-$version.zip"
foreach ($old in @(Get-ChildItem -Path $OutputPath -Filter 'PVEPS*' | Where-Object { $_.Name -eq 'PVEPS' -or $_.Extension -in '.nupkg', '.zip' })) {
  Remove-Item -LiteralPath $old.FullName -Recurse -Force
}
$null = New-Item -ItemType Directory -Path $stage
foreach ($item in 'PVEPS.psd1', 'PVEPS.psm1', 'PVEPS.Format.ps1xml', 'PVEPS.Types.ps1xml', 'LICENSE', 'README.md', 'Public', 'Private') {
  Copy-Item -LiteralPath (Join-Path -Path $root -ChildPath $item) -Destination $stage -Recurse
}

# 3. Import the staged copy in a clean process.
$check = "Import-Module '$(Join-Path -Path $stage -ChildPath 'PVEPS.psd1')' -ErrorAction Stop; (Get-Module PVEPS).ExportedFunctions.Count"
$count = & ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -NoProfile -NonInteractive -Command $check
if ($LASTEXITCODE -ne 0 -or [int]($count | Select-Object -Last 1) -ne $public.Count) {
  throw "The staged module did not import cleanly or exported $count functions instead of $($public.Count)."
}

# 4. Packages.
Compress-PSResource -Path $stage -DestinationPath $OutputPath
if (-not (Test-Path -LiteralPath $nupkg)) {
  throw "Compress-PSResource did not write $nupkg."
}
Compress-Archive -Path $stage -DestinationPath $zip
Get-Item -LiteralPath $nupkg, $zip

if ($Install -and $PSCmdlet.ShouldProcess("PVEPS $version", 'Install for the current user')) {
  $repository = 'PVEPS-build-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
  Register-PSResourceRepository -Name $repository -Uri $OutputPath -Trusted
  try {
    Install-PSResource -Name PVEPS -Version $version -Repository $repository -Scope CurrentUser -Reinstall -TrustRepository
    Get-InstalledPSResource -Name PVEPS -Version $version -Scope CurrentUser
  }
  finally {
    Unregister-PSResourceRepository -Name $repository
  }
}

if ($Publish -and $PSCmdlet.ShouldProcess("PVEPS $version", 'Publish to the PowerShell Gallery (public, and the version cannot be replaced)')) {
  if (-not $PSBoundParameters.ContainsKey('Confirm') -and -not $PSCmdlet.ShouldContinue("Publish PVEPS $version to the PowerShell Gallery? It becomes public.", 'Publish')) {
    return
  }
  Publish-PSResource -Path $stage -Repository PSGallery -ApiKey $ApiKey
}
