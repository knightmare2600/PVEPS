#Requires -Modules Pester
# Integration tests for the Phase 7 storage, appliance template, backup and restore cmdlets. THESE WRITE
# AND DELETE FILES ON STORAGE, AND CREATE AND DELETE GUESTS: every file is named pveps-test-*, every guest
# is created by the test in PVEPS_TEST_POOL and named pveps-test-st-*, and all of them are deleted again.
#
# Skipped unless these are set, in addition to PVEPS_TEST_SERVER (and PVEPS_TEST_SKIPCERT if needed):
#   PVEPS_TEST_WRITE_TOKEN_ID, PVEPS_TEST_WRITE_TOKEN_SECRET, PVEPS_TEST_POOL
#   PVEPS_TEST_STORAGE          storage for test disks (as in the lifecycle tests)
#   PVEPS_TEST_FILE_STORAGE     a storage allowing iso and backup content, e.g. local
# Optional:
#   PVEPS_TEST_ISO_URL          a small ISO for the node to download, enabling the download test
#   PVEPS_TEST_APPLIANCE        an appliance template name to download onto PVEPS_TEST_FILE_STORAGE (it
#                               is deleted afterwards only if it was not there before)
#
# Run: Invoke-Pester ./tests/Integration/Storage.Integration.Tests.ps1 -Output Detailed

BeforeDiscovery {
  $script:HaveStorage = [bool]($env:PVEPS_TEST_SERVER -and $env:PVEPS_TEST_WRITE_TOKEN_ID -and $env:PVEPS_TEST_WRITE_TOKEN_SECRET -and $env:PVEPS_TEST_POOL -and $env:PVEPS_TEST_STORAGE -and $env:PVEPS_TEST_FILE_STORAGE)
  $script:HaveUrl = [bool]$env:PVEPS_TEST_ISO_URL
  $script:HaveAppliance = [bool]$env:PVEPS_TEST_APPLIANCE
}

BeforeAll {
  . (Join-Path $PSScriptRoot 'IntegrationHelpers.ps1')
  Connect-PVETestWrite
  $script:Created = [System.Collections.Generic.List[int]]::new()
  $script:Files = [System.Collections.Generic.List[string]]::new()
  $script:RunTag = 'pveps-test-st-{0}' -f (Get-Random -Minimum 1000 -Maximum 9999)
}

AfterAll {
  foreach ($volume in $script:Files) {
    Set-PVEStorageContent -Volume $volume -Protected $false -ErrorAction SilentlyContinue | Out-Null
    Remove-PVEStorageContent -Volume $volume -Confirm:$false -ErrorAction SilentlyContinue
  }
  foreach ($id in $script:Created) {
    $guest = Get-PVEVM -VMId $id -IncludeTemplate -ErrorAction SilentlyContinue
    if (-not $guest) {
      continue
    }
    try {
      Assert-PVETestGuest -Guest $guest -Kind 'VM'
    }
    catch {
      Write-Warning "Clean-up skipped: $_"
      continue
    }
    if ((Get-PVETestLiveStatus -Guest $guest) -ne 'stopped') { $null = Stop-PVEVM -VMId $id -Confirm:$false -ErrorAction Continue }
    Remove-PVEVM -VMId $id -Purge -Confirm:$false -ErrorAction Continue
  }
  Disconnect-PVE -Server * -Confirm:$false -ErrorAction SilentlyContinue
}

Describe 'Storage content against a real server' -Tag 'Integration', 'Storage' -Skip:(-not $script:HaveStorage) {
  It 'lists the content of the file storage' {
    { Get-PVEStorageContent -Storage $env:PVEPS_TEST_FILE_STORAGE -ErrorAction Stop } | Should -Not -Throw
  }

  It 'uploads a local file as an ISO image under a different name, and deletes it' {
    $local = Join-Path ([System.IO.Path]::GetTempPath()) ('upload-' + [guid]::NewGuid() + '.iso')
    $bytes = [byte[]]::new(1MB)
    [System.Random]::new(7).NextBytes($bytes)
    [System.IO.File]::WriteAllBytes($local, $bytes)
    try {
      $sha = (Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash.ToLowerInvariant()
      $name = "$($script:RunTag)-upload.iso"
      $item = Import-PVEStorageContent -Path $local -FileName $name -Storage $env:PVEPS_TEST_FILE_STORAGE -Content iso -Checksum $sha -ChecksumAlgorithm sha256 -ErrorAction Stop
      $script:Files.Add("$($env:PVEPS_TEST_FILE_STORAGE):iso/$name")
      $item.Volume | Should -Be "$($env:PVEPS_TEST_FILE_STORAGE):iso/$name"
      $item.SizeGB | Should -Be ([math]::Round(1MB / 1GB, 2))
      Remove-PVEStorageContent -Volume $item.Volume -Confirm:$false -ErrorAction Stop
      Get-PVEStorageContent -Storage $env:PVEPS_TEST_FILE_STORAGE -Content iso | Where-Object Volume -EQ $item.Volume | Should -BeNullOrEmpty
    }
    finally {
      Remove-Item -LiteralPath $local -ErrorAction SilentlyContinue
    }
  }

  It 'has the node download an ISO from a URL' -Skip:(-not $script:HaveUrl) {
    $name = "$($script:RunTag)-download.iso"
    $item = Import-PVEStorageContent -Url $env:PVEPS_TEST_ISO_URL -FileName $name -Storage $env:PVEPS_TEST_FILE_STORAGE -Content iso -ErrorAction Stop
    $script:Files.Add($item.Volume)
    $item.Content | Should -Be 'iso'
  }

  It 'reads the appliance catalogue, with the fields the module expects' {
    $templates = @(Get-PVEApplianceTemplate -ErrorAction Stop)
    $templates.Count | Should -BeGreaterThan 0
    @($templates | Where-Object { $_.Template -and $_.Section }).Count | Should -Be $templates.Count
  }

  It 'downloads an appliance template' -Skip:(-not $script:HaveAppliance) {
    $volume = "$($env:PVEPS_TEST_FILE_STORAGE):vztmpl/$($env:PVEPS_TEST_APPLIANCE)"
    $existed = [bool](Get-PVEStorageContent -Storage $env:PVEPS_TEST_FILE_STORAGE -Content vztmpl | Where-Object Volume -EQ $volume)
    $item = Save-PVEApplianceTemplate -Template $env:PVEPS_TEST_APPLIANCE -Storage $env:PVEPS_TEST_FILE_STORAGE -ErrorAction Stop
    $item.Volume | Should -Be $volume
    if (-not $existed) {
      $script:Files.Add($volume)
    }
  }
}

Describe 'Backup and restore against a real server' -Tag 'Integration', 'Storage' -Skip:(-not $script:HaveStorage) {
  BeforeAll {
    $script:VM = New-PVEVM -Name "$($script:RunTag)-vm" -Pool $env:PVEPS_TEST_POOL -Cores 1 -MemoryGB 0.5 -DiskGB 1 -Storage $env:PVEPS_TEST_STORAGE -ErrorAction Stop
    $script:Created.Add($script:VM.VMId)
    Assert-PVETestGuest -Guest $script:VM -Kind 'VM'
  }

  It 'backs the VM up and writes the new backup' {
    $backup = Backup-PVEVM -VMId $script:VM.VMId -Storage $env:PVEPS_TEST_FILE_STORAGE -Mode stop -Compress zstd -Notes 'pveps-test {{guestname}}' -ErrorAction Stop
    $script:Files.Add($backup.Volume)
    $backup.VMId | Should -Be $script:VM.VMId
    $backup.GuestType | Should -Be 'qemu'
    $backup.Content | Should -Be 'backup'
    $script:Backup = $backup
  }

  It 'lists it with Get-PVEBackup -Latest' {
    (Get-PVEBackup -VMId $script:VM.VMId -Latest -ErrorAction Stop).Volume | Should -Be $script:Backup.Volume
  }

  It 'protects the backup, so deleting it fails, then unprotects it' {
    (Set-PVEStorageContent -Volume $script:Backup.Volume -Protected $true -ErrorAction Stop).Protected | Should -BeTrue
    $errors = $null
    Remove-PVEStorageContent -Volume $script:Backup.Volume -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable errors
    $errors.Count | Should -BeGreaterThan 0
    (Get-PVEBackup -VMId $script:VM.VMId -Latest).Volume | Should -Be $script:Backup.Volume
    (Set-PVEStorageContent -Volume $script:Backup.Volume -Protected $false -ErrorAction Stop).Protected | Should -BeFalse
  }

  It 'restores the backup as a new VM with new MAC addresses' {
    $newId = (Invoke-PVEApi -Path /cluster/nextid -ErrorAction Stop) -as [int]
    $restored = $script:Backup | Restore-PVEBackup -VMId $newId -Storage $env:PVEPS_TEST_STORAGE -Pool $env:PVEPS_TEST_POOL -Unique -Confirm:$false -ErrorAction Stop
    $script:Created.Add($newId)
    $restored.VMId | Should -Be $newId
    $restored.Name | Should -Be $script:VM.Name
    $null = Set-PVEVM -VMId $newId -NewName "$($script:RunTag)-restored" -ErrorAction Stop
  }

  It 'refuses to restore over the existing VM without -Force' {
    $errors = $null
    $script:Backup | Restore-PVEBackup -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable errors
    $errors.Count | Should -BeGreaterThan 0
  }

  It 'deletes the backup' {
    Remove-PVEStorageContent -Volume $script:Backup.Volume -Confirm:$false -ErrorAction Stop
    Get-PVEBackup -VMId $script:VM.VMId | Should -BeNullOrEmpty
  }
}
