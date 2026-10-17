#Requires -Modules Pester
# Phase 7 storage content, appliance template, backup and restore cmdlets. HTTP is mocked (see
# TestHelpers.ps1); nothing here touches a real server.

BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  Mock -ModuleName PVEPS Start-Sleep { }

  function Initialize-Storage {
    Reset-FakeState
    $script:State = @{
      Storages  = @(
        @{ storage = 'local'; type = 'dir'; content = 'iso,vztmpl,backup'; active = 1; enabled = 1 }
        @{ storage = 'local-lvm'; type = 'lvmthin'; content = 'images,rootdir'; active = 1; enabled = 1 }
        @{ storage = 'nas'; type = 'nfs'; content = 'backup'; active = 0; enabled = 1 }
      )
      Content   = @{
        'local'     = [System.Collections.Generic.List[hashtable]]@(
          @{ volid = 'local:iso/debian.iso'; content = 'iso'; format = 'iso'; size = 1GB; ctime = 1700000000 }
          @{ volid = 'local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst'; content = 'vztmpl'; format = 'tzst'; size = 120MB; ctime = 1700000100 }
          @{ volid = 'local:backup/vzdump-qemu-100-2026_10_01-02_00_00.vma.zst'; content = 'backup'; format = 'vma.zst'; size = 2GB; ctime = 1700001000; vmid = 100; subtype = 'qemu'; notes = 'web01' }
          @{ volid = 'local:backup/vzdump-qemu-100-2026_10_02-02_00_00.vma.zst'; content = 'backup'; format = 'vma.zst'; size = 2GB; ctime = 1700002000; vmid = 100 }
          @{ volid = 'local:backup/vzdump-lxc-200-2026_10_02-02_00_00.tar.zst'; content = 'backup'; format = 'tar.zst'; size = 1GB; ctime = 1700002500; vmid = 200; protected = 1 }
        )
        'local-lvm' = [System.Collections.Generic.List[hashtable]]@(
          @{ volid = 'local-lvm:vm-100-disk-0'; content = 'images'; format = 'raw'; size = 32GB; vmid = 100 }
        )
      }
      Guests    = [ordered]@{
        '100' = @{ type = 'qemu'; vmid = 100; name = 'web01'; status = 'running' }
        '200' = @{ type = 'lxc'; vmid = 200; name = 'dns01'; status = 'stopped' }
      }
      Appliance = @(
        @{ template = 'debian-13-standard_13.1-2_amd64.tar.zst'; section = 'system'; os = 'debian-13'; version = '13.1-2'; package = 'debian-13-standard'; headline = 'Debian 13 (standard)' }
        @{ template = 'alpine-3.22-default_20250617_amd64.tar.xz'; section = 'system'; os = 'alpine'; version = '3.22-default'; headline = 'Alpine Linux 3.22' }
        @{ template = 'debian-12-turnkey-nextcloud_18.0-1_amd64.tar.gz'; section = 'turnkeylinux'; os = 'debian-12'; headline = 'TurnKey Nextcloud' }
      )
      Backups   = 0
      Fail      = $false
    }
    $script:Fake.Handler = $script:StorageHandler
    $null = Connect-PVE -Server pve -User root@pam -Password 'x'
    $script:Fake.Calls.Clear()
  }

  function ConvertFrom-Body {
    param([string]$Body)
    $result = @{}
    foreach ($pair in ($Body -split '&' | Where-Object { $_ })) {
      $key, $value = $pair -split '=', 2
      $result[[uri]::UnescapeDataString($key)] = [uri]::UnescapeDataString($value)
    }
    $result
  }

  $script:StorageHandler = {
    param($Method, $Path, $Call)
    $state = $script:State
    $query = ConvertFrom-Body $Call.Query
    $body = if ($Call.Body -is [string]) { ConvertFrom-Body $Call.Body } else { @{} }
    $upid = 'UPID:pve:0000A1B2:00C3D4E5:67000000:task:x:root@pam:'
    if ($Path -eq '/access/ticket') { return New-FakeResponse -Data @{ ticket = 'PVE:root@pam:AAAA::sig'; CSRFPreventionToken = 'AAAA:csrf'; username = 'root@pam' } }
    if ($Path -eq '/version') { return New-FakeResponse -Data @{ version = '9.2.1'; release = '9.2' } }
    if ($Path -eq '/nodes') { return New-FakeResponse -Data @(@{ node = 'pve'; status = 'online' }) }
    if ($Path -eq '/nodes/pve/status') { return New-FakeResponse -Data @{} }
    if ($Path -eq '/cluster/resources') {
      return New-FakeResponse -Data @($state.Guests.Values | ForEach-Object { @{ type = $_.type; vmid = $_.vmid; name = $_.name; node = 'pve'; status = $_.status; template = 0 } })
    }
    if ($Path -match '^/nodes/pve/(qemu|lxc)/(\d+)/status/current$') {
      $g = $state.Guests[$Matches[2]]
      return New-FakeResponse -Data @{ vmid = $g.vmid; status = $g.status; name = $g.name }
    }
    if ($Path -match '^/nodes/pve/tasks/(.+)/status$') {
      $exit = if ($state.Fail) { 'job failed' } else { 'OK' }
      return New-FakeResponse -Data @{ upid = [uri]::UnescapeDataString($Matches[1]); node = 'pve'; status = 'stopped'; exitstatus = $exit; type = 'task'; id = 'x'; user = 'root@pam' }
    }
    if ($Path -eq '/nodes/pve/storage') {
      $list = @($state.Storages | Where-Object { -not $query.content -or ($_.content -split ',') -contains $query.content })
      return New-FakeResponse -Data $list
    }
    if ($Path -match '^/nodes/pve/storage/([^/]+)/content$') {
      $items = @($state.Content[$Matches[1]] | Where-Object { $_ } | Where-Object { (-not $query.content -or $_.content -eq $query.content) -and (-not $query.vmid -or [string]$_.vmid -eq $query.vmid) })
      return New-FakeResponse -Data $items
    }
    if ($Path -match '^/nodes/pve/storage/([^/]+)/content/(.+)$') {
      $volid = [uri]::UnescapeDataString($Matches[2])
      $list = $state.Content[$Matches[1]]
      $entry = $list | Where-Object { $_.volid -eq $volid }
      if ($Method -eq 'DELETE') { $null = $list.Remove($entry); return New-FakeResponse -Data $upid }
      if ($Method -eq 'PUT') {
        if ($body.ContainsKey('notes')) { $entry.notes = $body.notes }
        if ($body.ContainsKey('protected')) { $entry.protected = [int]$body.protected }
        return New-FakeResponse -Data $null
      }
    }
    if ($Path -match '^/nodes/pve/storage/([^/]+)/download-url$') {
      $state.Content[$Matches[1]].Add(@{ volid = "$($Matches[1]):$($body.content)/$($body.filename)"; content = $body.content; format = 'iso'; size = 10MB; ctime = 1700009000 })
      return New-FakeResponse -Data $upid
    }
    if ($Path -match '^/nodes/pve/storage/([^/]+)/upload$') {
      $state.Content[$Matches[1]].Add(@{ volid = "$($Matches[1]):iso/uploaded.iso"; content = 'iso'; format = 'iso'; size = 1MB; ctime = 1700009000 })
      return New-FakeResponse -Data $upid
    }
    if ($Path -eq '/nodes/pve/aplinfo') {
      if ($Method -eq 'GET') { return New-FakeResponse -Data @($state.Appliance) }
      $state.Content[$body.storage].Add(@{ volid = "$($body.storage):vztmpl/$($body.template)"; content = 'vztmpl'; format = 'tzst'; size = 100MB; ctime = 1700009000 })
      return New-FakeResponse -Data $upid
    }
    if ($Path -eq '/nodes/pve/vzdump') {
      $target = if ($body.storage) { $body.storage } else { 'local' }
      foreach ($id in ($body.vmid -split ',')) {
        $state.Backups++
        $kind = $state.Guests[$id].type
        $state.Content[$target].Add(@{ volid = "$target`:backup/vzdump-$kind-$id-new$($state.Backups).zst"; content = 'backup'; format = 'zst'; size = 1GB; ctime = 1800000000 + $state.Backups; vmid = [int]$id; subtype = $kind })
      }
      return New-FakeResponse -Data $upid
    }
    if ($Method -eq 'POST' -and $Path -match '^/nodes/pve/(qemu|lxc)$') {
      $state.Guests[$body.vmid] = @{ type = $Matches[1]; vmid = [int]$body.vmid; name = 'restored'; status = $(if ($body.start -eq '1') { 'running' } else { 'stopped' }) }
      return New-FakeResponse -Data $upid
    }
    New-FakeResponse -Status 501 -Reason "Unexpected $Method $Path in test" -Data $null
  }

  function Get-Request {
    param([string]$Method, [string]$PathPattern)
    @($script:Fake.Calls | Where-Object { $_.Method -eq $Method -and $_.Path -match $PathPattern })
  }

  function Invoke-Streams {
    param([scriptblock]$ScriptBlock)
    $all = @(& $ScriptBlock 2>&1 3>&1)
    [pscustomobject]@{
      Output   = @($all | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] -and $_ -isnot [System.Management.Automation.WarningRecord] })
      Errors   = @($all | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
      Warnings = @($all | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    }
  }
}

Describe 'Confirmation level' {
  It '<Command> has ConfirmImpact <Impact>' -ForEach @(
    @{ Command = 'Remove-PVEStorageContent'; Impact = 'High' }
    @{ Command = 'Set-PVEStorageContent'; Impact = 'Medium' }
    @{ Command = 'Import-PVEStorageContent'; Impact = 'Medium' }
    @{ Command = 'Save-PVEApplianceTemplate'; Impact = 'Medium' }
    @{ Command = 'Backup-PVEVM'; Impact = 'Medium' }
    @{ Command = 'Backup-PVEContainer'; Impact = 'Medium' }
    @{ Command = 'Restore-PVEBackup'; Impact = 'High' }
  ) {
    $metadata = [System.Management.Automation.CommandMetadata]::new((Get-Command $Command))
    $metadata.SupportsShouldProcess | Should -BeTrue
    [string]$metadata.ConfirmImpact | Should -Be $Impact
  }
}

Describe 'Get-PVEStorageContent' {
  BeforeEach {
    Initialize-Storage
  }

  It 'lists every active storage, newest first per storage, and warns about inactive ones' {
    $r = Invoke-Streams { Get-PVEStorageContent }
    $r.Warnings[0].Message | Should -BeLike '*nas on pve is not active*'
    $r.Output.Count | Should -Be 6
    $r.Output[0].Volume | Should -Be 'local:backup/vzdump-lxc-200-2026_10_02-02_00_00.tar.zst'
    $r.Output[0].PSObject.TypeNames | Should -Contain 'PVEPS.StorageContent'
  }

  It 'filters by content type, passing it to the API, and reads the fields' {
    $iso = @(Get-PVEStorageContent -Content iso)
    $iso.Count | Should -Be 1
    $iso[0].Storage | Should -Be 'local'
    $iso[0].SizeGB | Should -Be 1
    $iso[0].Created | Should -Be ([DateTimeOffset]::FromUnixTimeSeconds(1700000000).LocalDateTime)
    (Get-Request GET '/storage/local/content$')[0].Query | Should -Be 'content=iso'
  }

  It 'tells VM from container backups' {
    $backups = @(Get-PVEStorageContent -Content backup)
    ($backups | Where-Object VMId -EQ 200).GuestType | Should -Be 'lxc'
    @($backups | Where-Object VMId -EQ 100 | ForEach-Object { $_.GuestType } | Select-Object -Unique) | Should -Be @('qemu')
    ($backups | Where-Object VMId -EQ 200).Protected | Should -BeTrue
  }

  It 'takes storages from Get-PVEStorage in the pipeline' {
    @(Get-PVEStorage local-lvm | Get-PVEStorageContent).Volume | Should -Be 'local-lvm:vm-100-disk-0'
  }
}

Describe 'Set- and Remove-PVEStorageContent' {
  BeforeEach {
    Initialize-Storage
  }

  It 'Set-PVEStorageContent sends notes and protection and writes the volume' {
    $item = Set-PVEStorageContent -Volume local:backup/vzdump-qemu-100-2026_10_01-02_00_00.vma.zst -Notes 'keep' -Protected $true
    $call = (Get-Request PUT '/content/')[0]
    $call.Path | Should -Be '/nodes/pve/storage/local/content/local%3Abackup%2Fvzdump-qemu-100-2026_10_01-02_00_00.vma.zst'
    $body = ConvertFrom-Body $call.Body
    $body.notes | Should -Be 'keep'
    $body.protected | Should -Be '1'
    $item.Protected | Should -BeTrue
    $item.Notes | Should -Be 'keep'
  }

  It 'Remove-PVEStorageContent deletes piped volumes and waits for the tasks' {
    Get-PVEStorageContent -Content iso | Remove-PVEStorageContent -Confirm:$false
    (Get-Request DELETE '/content/').Count | Should -Be 1
    (Get-Request GET '/tasks/').Count | Should -BeGreaterThan 0
    Get-PVEStorageContent -Content iso | Should -BeNullOrEmpty
  }

  It 'Remove-PVEStorageContent sends nothing under -WhatIf and refuses a value that is not a volume ID' {
    Remove-PVEStorageContent -Volume local:iso/debian.iso -WhatIf
    (Get-Request DELETE '.*').Count | Should -Be 0
    $r = Invoke-Streams { Remove-PVEStorageContent -Volume 'debian.iso' -Confirm:$false }
    $r.Errors[0].Exception.Message | Should -BeLike '*not a volume ID*'
  }
}

Describe 'Import-PVEStorageContent' {
  BeforeEach {
    Initialize-Storage
    $script:Dir = Join-Path ([System.IO.Path]::GetTempPath()) ("pveps-test-" + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path $script:Dir
  }

  AfterEach {
    Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'has the node download a URL, naming the file after the URL, and writes the stored item' {
    $item = Import-PVEStorageContent -Url 'https://example.com/isos/netinst%20v2.iso' -Storage local -Content iso -Checksum abc -ChecksumAlgorithm sha256 -SkipCertificateCheck
    $body = ConvertFrom-Body (Get-Request POST '/download-url$')[0].Body
    $body.url | Should -Be 'https://example.com/isos/netinst%20v2.iso'
    $body.filename | Should -Be 'netinst v2.iso'
    $body.content | Should -Be 'iso'
    $body.checksum | Should -Be 'abc'
    $body['checksum-algorithm'] | Should -Be 'sha256'
    $body['verify-certificates'] | Should -Be '0'
    $item.Volume | Should -Be 'local:iso/netinst v2.iso'
  }

  It 'uploads a local file as multipart, with the file part last and under -FileName' {
    $file = Join-Path $script:Dir 'local.iso'
    [System.IO.File]::WriteAllBytes($file, [byte[]](1, 2, 3))
    $captured = [System.Collections.Generic.List[string]]::new()
    Mock -ModuleName PVEPS Invoke-WebRequest {
      if ($Body -is [System.Net.Http.MultipartFormDataContent]) {
        $captured.Add($Body.ReadAsStringAsync().GetAwaiter().GetResult())
      }
      $call = [pscustomobject]@{ Method = [string]$Method; Uri = [string]$Uri; Path = Get-PathOf $Uri; Query = Get-QueryOf $Uri; Headers = $Headers; Body = $Body }
      $script:Fake.Calls.Add($call)
      & $script:Fake.Handler $call.Method $call.Path $call
    }
    $r = Invoke-Streams { Import-PVEStorageContent -Path $file -Storage local -Content iso -FileName 'renamed.iso' }
    $captured.Count | Should -Be 1
    $text = $captured[0]
    $text.IndexOf('name="content"') | Should -BeLessThan $text.IndexOf('name="filename"')
    $text | Should -Match 'name="filename"; filename="renamed.iso"'
    (Get-Request POST '/upload$')[0].Headers['CSRFPreventionToken'] | Should -Be 'AAAA:csrf'
    $r.Warnings[0].Message | Should -BeLike '*local:iso/renamed.iso is not listed; PVE normalises file names*'
  }

  It 'refuses a checksum without its algorithm, and a missing local file' {
    { Import-PVEStorageContent -Url https://example.com/a.iso -Storage local -Content iso -Checksum abc } | Should -Throw '*go together*'
    { Import-PVEStorageContent -Path (Join-Path $script:Dir 'nope.iso') -Storage local -Content iso } | Should -Throw '*was not found*'
    (Get-Request POST '.*').Count | Should -Be 0
  }
}

Describe 'Appliance templates' {
  BeforeEach {
    Initialize-Storage
  }

  It 'Get-PVEApplianceTemplate filters by name and section' {
    @(Get-PVEApplianceTemplate).Count | Should -Be 3
    @(Get-PVEApplianceTemplate -Section system).Count | Should -Be 2
    $t = Get-PVEApplianceTemplate 'debian-13-*'
    $t.Template | Should -Be 'debian-13-standard_13.1-2_amd64.tar.zst'
    $t.Headline | Should -Be 'Debian 13 (standard)'
    $r = Invoke-Streams { Get-PVEApplianceTemplate 'nope.tar.zst' }
    $r.Errors[0].Exception.Message | Should -BeLike "*'nope.tar.zst' was not found*"
  }

  It 'Save-PVEApplianceTemplate downloads piped templates and writes the stored ones' {
    $item = Get-PVEApplianceTemplate 'alpine-*' | Save-PVEApplianceTemplate -Storage local
    $body = ConvertFrom-Body (Get-Request POST '/aplinfo$')[0].Body
    $body.template | Should -Be 'alpine-3.22-default_20250617_amd64.tar.xz'
    $body.storage | Should -Be 'local'
    $item.Volume | Should -Be 'local:vztmpl/alpine-3.22-default_20250617_amd64.tar.xz'
  }
}

Describe 'Backups' {
  BeforeEach {
    Initialize-Storage
  }

  It 'Backup-PVEVM sends one vzdump per node with every ID, and writes only the new backups' {
    $script:State.Guests['101'] = @{ type = 'qemu'; vmid = 101; name = 'db01'; status = 'stopped' }
    $backups = @(Backup-PVEVM -VMId 100, 101 -Storage local -Mode stop -Compress none -Notes '{{guestname}}' -Protected)
    $calls = Get-Request POST '/vzdump$'
    $calls.Count | Should -Be 1
    $body = ConvertFrom-Body $calls[0].Body
    $body.vmid | Should -Be '100,101'
    $body.storage | Should -Be 'local'
    $body.mode | Should -Be 'stop'
    $body.compress | Should -Be '0'
    $body['notes-template'] | Should -Be '{{guestname}}'
    $body.protected | Should -Be '1'
    $backups.Count | Should -Be 2
    @($backups | ForEach-Object { $_.VMId } | Sort-Object) | Should -Be @(100, 101)
    $backups | ForEach-Object { $_.Volume | Should -BeLike '*-new*' }
  }

  It 'finds the new backup on the storages that hold backups when no -Storage is given' {
    $backup = Backup-PVEContainer -VMId 200
    $backup.Volume | Should -BeLike 'local:backup/vzdump-lxc-200-new*'
    (ConvertFrom-Body (Get-Request POST '/vzdump$')[0].Body).ContainsKey('storage') | Should -BeFalse
  }

  It 'writes no backups when the task fails' {
    $script:State.Fail = $true
    $r = Invoke-Streams { Backup-PVEVM -VMId 100 -Storage local }
    $r.Errors[0].FullyQualifiedErrorId | Should -BeLike 'PVETaskFailed*'
    $r.Output.Count | Should -Be 0
  }

  It 'sends nothing under -WhatIf' {
    Backup-PVEVM -VMId 100 -WhatIf
    (Get-Request POST '.*').Count | Should -Be 0
  }

  It 'Get-PVEBackup lists a guest''s backups newest first, and -Latest keeps one per guest' {
    @(Get-PVEVM web01 | Get-PVEBackup).Count | Should -Be 2
    $latest = @(Get-PVEBackup -Latest)
    $latest.Count | Should -Be 2
    ($latest | Where-Object VMId -EQ 100).Volume | Should -Be 'local:backup/vzdump-qemu-100-2026_10_02-02_00_00.vma.zst'
  }

  It 'Get-PVEBackup finds backups of guests that no longer exist' {
    $script:State.Content['local'].Add(@{ volid = 'local:backup/vzdump-qemu-999-x.vma.zst'; content = 'backup'; vmid = 999; ctime = 1 })
    (Get-PVEBackup -VMId 999).Volume | Should -Be 'local:backup/vzdump-qemu-999-x.vma.zst'
  }
}

Describe 'Restore-PVEBackup' {
  BeforeEach {
    Initialize-Storage
  }

  It 'restores a piped VM backup with POST /nodes/{node}/qemu and archive=' {
    $vm = Get-PVEBackup -VMId 100 -Latest | Restore-PVEBackup -VMId 150 -Storage local-lvm -Pool web -Unique -PowerOn -Confirm:$false
    $body = ConvertFrom-Body (Get-Request POST '^/nodes/pve/qemu$')[0].Body
    $body.vmid | Should -Be '150'
    $body.archive | Should -Be 'local:backup/vzdump-qemu-100-2026_10_02-02_00_00.vma.zst'
    $body.storage | Should -Be 'local-lvm'
    $body.unique | Should -Be '1'
    $body.start | Should -Be '1'
    $body.pool | Should -Be 'web'
    $body.ContainsKey('force') | Should -BeFalse
    $vm.VMId | Should -Be 150
    $vm.PSObject.TypeNames | Should -Contain 'PVEPS.VM'
  }

  It 'restores a container backup with ostemplate= and restore=1, looking the type up when not piped' {
    $ct = Restore-PVEBackup -Volume local:backup/vzdump-lxc-200-2026_10_02-02_00_00.tar.zst -VMId 200 -Force -Confirm:$false
    $body = ConvertFrom-Body (Get-Request POST '^/nodes/pve/lxc$')[0].Body
    $body.ostemplate | Should -Be 'local:backup/vzdump-lxc-200-2026_10_02-02_00_00.tar.zst'
    $body.restore | Should -Be '1'
    $body.force | Should -Be '1'
    $ct.PSObject.TypeNames | Should -Contain 'PVEPS.Container'
  }

  It 'refuses a backup that is not on the storage, and sends nothing under -WhatIf' {
    $r = Invoke-Streams { Restore-PVEBackup -Volume local:backup/nope.vma.zst -VMId 150 -Confirm:$false }
    $r.Errors[0].Exception.Message | Should -BeLike "*'local:backup/nope.vma.zst' was not found*"
    Restore-PVEBackup -Volume local:backup/vzdump-lxc-200-2026_10_02-02_00_00.tar.zst -VMId 200 -WhatIf
    (Get-Request POST '.*').Count | Should -Be 0
  }
}
