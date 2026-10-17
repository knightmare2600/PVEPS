#Requires -Modules Pester
# Phase 3 lifecycle cmdlets. HTTP is mocked (see TestHelpers.ps1); nothing here touches a real server.
# The fake server keeps per-guest state (status, config, pending changes) and applies the create, clone,
# config, template, delete and move requests to it, so the tests check both the requests sent and the
# objects written back.

BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  Mock -ModuleName PVEPS Start-Sleep { }

  function New-Guest {
    param([string]$Type, [int]$VMId, [string]$Name, [string]$Status = 'stopped', [int]$Template = 0, [hashtable]$Config = @{}, [string]$Pool)
    @{ type = $Type; vmid = $VMId; name = $Name; node = 'pve'; status = $Status; template = $Template; pool = $Pool; tags = ''; config = $Config; pending = @() }
  }

  function Initialize-Lifecycle {
    Reset-FakeState
    $script:State = @{
      Guests       = [ordered]@{}
      Nodes        = @('pve')
      Hidden       = @()
      FailTasks    = $false
      FailMoveDisk = ''
      NextId       = 105
    }
    $guests = @(
      New-Guest -Type qemu -VMId 100 -Name web01 -Status running -Config @{
        name   = 'web01'
        scsi0  = 'local-lvm:vm-100-disk-0,iothread=1,size=32G'
        scsi1  = 'fast:vm-100-disk-1,size=100G'
        ide2   = 'local:iso/debian.iso,media=cdrom'
        ide0   = 'none,media=cdrom'
        net0   = 'virtio=BC:24:11:00:00:01,bridge=vmbr0'
        sata0  = '/dev/disk/by-id/ata-DISK,size=1T'
        memory = '2048'
      }
      New-Guest -Type qemu -VMId 101 -Name db01 -Config @{ name = 'db01'; virtio0 = 'local-lvm:vm-101-disk-0,size=10G'; efidisk0 = 'local-lvm:vm-101-disk-1,efitype=4m,size=4M' }
      New-Guest -Type qemu -VMId 102 -Name db02 -Config @{ name = 'db02'; scsi0 = 'fast:vm-102-disk-0,size=10G' }
      New-Guest -Type qemu -VMId 9000 -Name tmpl-debian -Template 1 -Config @{ name = 'tmpl-debian'; template = 1; scsi0 = 'local-lvm:base-9000-disk-0,size=8G' }
      New-Guest -Type lxc -VMId 200 -Name dns01 -Status running -Config @{ hostname = 'dns01'; rootfs = 'local-lvm:vm-200-disk-0,size=8G' }
      New-Guest -Type lxc -VMId 201 -Name proxy01 -Config @{ hostname = 'proxy01'; rootfs = 'local-lvm:vm-201-disk-0,size=8G'; mp0 = 'local-lvm:vm-201-disk-1,mp=/data,size=4G'; mp1 = '/srv/share,mp=/share' }
      New-Guest -Type lxc -VMId 9100 -Name tmpl-ct -Template 1 -Config @{ hostname = 'tmpl-ct'; template = 1; rootfs = 'local-lvm:base-9100-disk-0,size=8G' }
    )
    foreach ($g in $guests) {
      $script:State.Guests[[string]$g.vmid] = $g
    }
    $script:Fake.Handler = $script:LifecycleHandler
    $null = Connect-PVE -Server pve -User root@pam -Password 'x'
    $script:Fake.Calls.Clear()
  }

  function New-Upid {
    param([string]$Type, [int]$VMId)
    "UPID:pve:0000A1B2:00C3D4E5:67000000:$Type`:$VMId`:root@pam:"
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

  $script:LifecycleHandler = {
    param($Method, $Path, $Call)
    $state = $script:State
    $body = ConvertFrom-Body $Call.Body
    if ($Path -eq '/access/ticket') { return New-FakeResponse -Data @{ ticket = 'PVE:root@pam:AAAA::sig'; CSRFPreventionToken = 'AAAA:csrf'; username = 'root@pam' } }
    if ($Path -eq '/version') { return New-FakeResponse -Data @{ version = '9.2.1'; release = '9.2' } }
    if ($Path -eq '/nodes') { return New-FakeResponse -Data @($state.Nodes | ForEach-Object { @{ node = $_; status = 'online' } }) }
    if ($Path -eq '/cluster/nextid') {
      $query = ConvertFrom-Body $Call.Query
      if ($query.vmid) {
        if ($state.Guests.Contains($query.vmid)) { return New-FakeResponse -Status 400 -Reason "VM $($query.vmid) already exists" -Data $null }
        return New-FakeResponse -Data $query.vmid
      }
      return New-FakeResponse -Data ([string]$state.NextId)
    }
    if ($Path -eq '/cluster/resources') {
      $data = foreach ($g in $state.Guests.Values) {
        if ($g.vmid -in $state.Hidden) { continue }
        @{ id = "$($g.type)/$($g.vmid)"; type = $g.type; vmid = $g.vmid; name = $g.name; node = $g.node; status = $g.status; template = $g.template; pool = $g.pool; tags = $g.tags; maxmem = 1GB }
      }
      return New-FakeResponse -Data @($data)
    }
    if ($Method -eq 'POST' -and $Path -match '^/nodes/pve/(qemu|lxc)$') {
      $type = $Matches[1]
      $id = [int]$body.vmid
      $name = if ($type -eq 'lxc') { $body.hostname } else { $body.name }
      $g = New-Guest -Type $type -VMId $id -Name $name -Status $(if ($body.start -eq '1') { 'running' } else { 'stopped' }) -Config $body -Pool $body.pool
      $g.tags = [string]$body.tags
      $state.Guests[[string]$id] = $g
      return New-FakeResponse -Data (New-Upid -Type $(if ($type -eq 'lxc') { 'vzcreate' } else { 'qmcreate' }) -VMId $id)
    }
    if ($Path -match '^/nodes/pve/(qemu|lxc)/(\d+)(/.*)?$') {
      $type = $Matches[1]
      $id = $Matches[2]
      $rest = $Matches[3]
      $g = $state.Guests[$id]
      if (-not $g) { return New-FakeResponse -Status 500 -Reason "Configuration file 'nodes/pve/$type-server/$id.conf' does not exist" -Data $null }
      switch -Regex ($rest) {
        '^/status/current$' {
          return New-FakeResponse -Data @{ vmid = [int]$id; status = $g.status; name = $g.name; tags = $(if ($g.tags) { $g.tags } else { $null }); template = $(if ($g.template) { 1 } else { $null }); maxmem = 2GB; cpus = 2; uptime = $(if ($g.status -eq 'running') { 42 } else { 0 }) }
        }
        '^/config$' {
          if ($Method -eq 'GET') { return New-FakeResponse -Data $g.config }
          foreach ($key in $body.Keys) {
            if ($key -eq 'delete') { continue }
            $g.config[$key] = $body[$key]
          }
          if ($body.name) { $g.name = $body.name }
          if ($body.hostname) { $g.name = $body.hostname }
          if ($body.ContainsKey('tags')) { $g.tags = $body.tags }
          if ($body.delete -and ($body.delete -split ',') -contains 'tags') { $g.tags = '' }
          if ($Method -eq 'PUT') { return New-FakeResponse -Data $null }
          return New-FakeResponse -Data (New-Upid -Type qmconfig -VMId $id)
        }
        '^/pending$' {
          return New-FakeResponse -Data @($g.pending)
        }
        '^/template$' {
          $g.template = 1
          if ($type -eq 'lxc') { return New-FakeResponse -Data $null }
          return New-FakeResponse -Data (New-Upid -Type qmtemplate -VMId $id)
        }
        '^/clone$' {
          $newId = [int]$body.newid
          $name = if ($type -eq 'lxc') { $body.hostname } else { $body.name }
          $state.Guests[[string]$newId] = New-Guest -Type $type -VMId $newId -Name $name -Config @{ name = $name } -Pool $body.pool
          return New-FakeResponse -Data (New-Upid -Type $(if ($type -eq 'lxc') { 'vzclone' } else { 'qmclone' }) -VMId $id)
        }
        '^/(move_disk|move_volume)$' {
          $key = if ($type -eq 'lxc') { $body.volume } else { $body.disk }
          if ($state.FailMoveDisk -eq $key) { return New-FakeResponse -Data (New-Upid -Type 'qmmove-fail' -VMId $id) }
          $g.config[$key] = $g.config[$key] -replace '^[^:]+:', "$($body.storage):"
          return New-FakeResponse -Data (New-Upid -Type $(if ($type -eq 'lxc') { 'move_volume' } else { 'qmmove' }) -VMId $id)
        }
        '^$' {
          if ($Method -eq 'DELETE') {
            $state.Guests.Remove($id)
            return New-FakeResponse -Data (New-Upid -Type $(if ($type -eq 'lxc') { 'vzdestroy' } else { 'qmdestroy' }) -VMId $id)
          }
        }
      }
    }
    if ($Path -match '^/nodes/pve/tasks/(.+)/status$') {
      $upid = [uri]::UnescapeDataString($Matches[1])
      $parts = $upid -split ':'
      $exit = if ($state.FailTasks -or $parts[5] -eq 'qmmove-fail') { "command failed for $($parts[6])" } else { 'OK' }
      return New-FakeResponse -Data @{ upid = $upid; node = 'pve'; status = 'stopped'; exitstatus = $exit; type = $parts[5]; id = $parts[6]; user = 'root@pam' }
    }
    New-FakeResponse -Status 501 -Reason "Unexpected $Method $Path in test" -Data $null
  }

  function Get-Request {
    param([string]$Method, [string]$PathPattern)
    @($script:Fake.Calls | Where-Object { $_.Method -eq $Method -and $_.Path -match $PathPattern })
  }

  function Get-RequestBody {
    param([string]$Method, [string]$PathPattern)
    $calls = Get-Request -Method $Method -PathPattern $PathPattern
    $calls.Count | Should -Be 1 -Because "exactly one $Method matching $PathPattern is expected"
    ConvertFrom-Body $calls[0].Body
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
    @{ Command = 'New-PVEVM'; Impact = 'Medium' }
    @{ Command = 'New-PVEContainer'; Impact = 'Medium' }
    @{ Command = 'Set-PVEVM'; Impact = 'Medium' }
    @{ Command = 'Set-PVEContainer'; Impact = 'Medium' }
    @{ Command = 'Copy-PVEVM'; Impact = 'Medium' }
    @{ Command = 'Copy-PVEContainer'; Impact = 'Medium' }
    @{ Command = 'Move-PVEVM'; Impact = 'Medium' }
    @{ Command = 'Move-PVEContainer'; Impact = 'Medium' }
    @{ Command = 'Remove-PVEVM'; Impact = 'High' }
    @{ Command = 'Remove-PVEContainer'; Impact = 'High' }
    @{ Command = 'ConvertTo-PVEVMTemplate'; Impact = 'High' }
    @{ Command = 'ConvertTo-PVEContainerTemplate'; Impact = 'High' }
  ) {
    $metadata = [System.Management.Automation.CommandMetadata]::new((Get-Command $Command))
    $metadata.SupportsShouldProcess | Should -BeTrue
    [string]$metadata.ConfirmImpact | Should -Be $Impact
  }
}

Describe 'ConvertFrom-PVEPropertyString' {
  It 'puts a first item without a key under the default key' {
    InModuleScope PVEPS {
      $r = ConvertFrom-PVEPropertyString -Value 'local-lvm:vm-100-disk-0,iothread=1,size=32G' -DefaultKey file
      $r.file | Should -Be 'local-lvm:vm-100-disk-0'
      $r.iothread | Should -Be '1'
      $r.size | Should -Be '32G'
      @($r.Keys) | Should -Be @('file', 'iothread', 'size')
    }
  }

  It 'keeps an explicit first key and handles values containing =' {
    InModuleScope PVEPS {
      $r = ConvertFrom-PVEPropertyString -Value 'volume=local:vm-1-disk-0,mountoptions=noatime' -DefaultKey volume
      $r.volume | Should -Be 'local:vm-1-disk-0'
      (ConvertFrom-PVEPropertyString -Value 'order=scsi0;net0' -DefaultKey legacy).order | Should -Be 'scsi0;net0'
      (ConvertFrom-PVEPropertyString -Value 'a=b=c').a | Should -Be 'b=c'
    }
  }

  It 'returns an empty table for an empty string' {
    InModuleScope PVEPS {
      (ConvertFrom-PVEPropertyString -Value '').Count | Should -Be 0
    }
  }
}

Describe 'New-PVEVM' {
  BeforeEach {
    Initialize-Lifecycle
  }

  It 'builds the create request from the parameters' {
    $params = @{
      Name          = 'app01'
      Cores         = 2
      Sockets       = 1
      MemoryGB      = 1.5
      DiskGB        = 32, 100
      Storage       = 'local-lvm'
      NetworkBridge = 'vmbr0', 'vmbr1'
      IsoImage      = 'local:iso/debian.iso'
      OSType        = 'l26'
      CpuType       = 'host'
      GuestAgent    = $true
      Tags          = 'web', 'prod'
      Description   = 'made by test'
      StartOnBoot   = $true
      Pool          = 'web'
    }
    $null = New-PVEVM @params
    $body = Get-RequestBody POST '^/nodes/pve/qemu$'
    $body.vmid | Should -Be '105'
    $body.name | Should -Be 'app01'
    $body.cores | Should -Be '2'
    $body.sockets | Should -Be '1'
    $body.memory | Should -Be '1536'
    $body.scsi0 | Should -Be 'local-lvm:32'
    $body.scsi1 | Should -Be 'local-lvm:100'
    $body.scsihw | Should -Be 'virtio-scsi-single'
    $body.ide2 | Should -Be 'local:iso/debian.iso,media=cdrom'
    $body.net0 | Should -Be 'virtio,bridge=vmbr0'
    $body.net1 | Should -Be 'virtio,bridge=vmbr1'
    $body.boot | Should -Be 'order=scsi0;ide2;net0'
    $body.ostype | Should -Be 'l26'
    $body.cpu | Should -Be 'host'
    $body.agent | Should -Be '1'
    $body.tags | Should -Be 'web;prod'
    $body.description | Should -Be 'made by test'
    $body.onboot | Should -Be '1'
    $body.pool | Should -Be 'web'
    $body.ContainsKey('start') | Should -BeFalse
  }

  It 'sends only the name and ID when nothing else is given, leaving the rest to PVE defaults' {
    $null = New-PVEVM -Name bare
    $body = Get-RequestBody POST '^/nodes/pve/qemu$'
    @($body.Keys | Sort-Object) | Should -Be @('name', 'vmid')
  }

  It 'waits for the create task and writes the new VM with its live status' {
    $vm = New-PVEVM -Name app01 -PowerOn
    $vm.PSObject.TypeNames | Should -Contain 'PVEPS.VM'
    $vm.VMId | Should -Be 105
    $vm.Name | Should -Be 'app01'
    $vm.Status | Should -Be 'running'
    $vm.MemoryGB | Should -Be 2
    @(Get-Request GET '^/nodes/pve/tasks/').Count | Should -BeGreaterThan 0
    (Get-RequestBody POST '^/nodes/pve/qemu$').start | Should -Be '1'
  }

  It 'builds the VM from status/current when /cluster/resources does not list it yet' {
    $script:State.Hidden = @(105)
    $vm = New-PVEVM -Name app01 -Pool web
    $vm.VMId | Should -Be 105
    $vm.Name | Should -Be 'app01'
    $vm.Node | Should -Be 'pve'
    $vm.Pool | Should -Be 'web'
    $vm.Status | Should -Be 'stopped'
  }

  It 'checks a given -VMId is free with /cluster/nextid?vmid=' {
    $null = New-PVEVM -Name app01 -VMId 150
    (Get-Request GET '^/cluster/nextid$')[0].Query | Should -Be 'vmid=150'
    (Get-RequestBody POST '^/nodes/pve/qemu$').vmid | Should -Be '150'
  }

  It 'reports a taken -VMId without sending a create request' {
    $r = Invoke-Streams { New-PVEVM -Name app01 -VMId 100 }
    $r.Errors.Count | Should -Be 1
    $r.Errors[0].Exception.Message | Should -BeLike '*already exists*'
    (Get-Request POST '^/nodes/pve/qemu$').Count | Should -Be 0
  }

  It 'needs -Node when the server has several nodes' {
    $script:State.Nodes = @('pve', 'pve2')
    $r = Invoke-Streams { New-PVEVM -Name app01 }
    $r.Errors[0].FullyQualifiedErrorId | Should -BeLike 'PVENodeRequired*'
    $r.Errors[0].Exception.Message | Should -BeLike '*pve, pve2*'
    (Get-Request POST '^/nodes/').Count | Should -Be 0
    $null = New-PVEVM -Name app01 -Node pve
    (Get-Request POST '^/nodes/pve/qemu$').Count | Should -Be 1
  }

  It 'adds an EFI vars disk for -Bios ovmf' {
    $null = New-PVEVM -Name uefi01 -Bios ovmf -Storage local-lvm
    $body = Get-RequestBody POST '^/nodes/pve/qemu$'
    $body.bios | Should -Be 'ovmf'
    $body.efidisk0 | Should -Be 'local-lvm:1,efitype=4m'
  }

  It 'skips ide2 for disks on the ide bus when it holds the CD drive' {
    $null = New-PVEVM -Name old01 -DiskGB 10, 20, 30 -DiskBus ide -Storage local-lvm -IsoImage local:iso/x.iso
    $body = Get-RequestBody POST '^/nodes/pve/qemu$'
    $body.ide0 | Should -Be 'local-lvm:10'
    $body.ide1 | Should -Be 'local-lvm:20'
    $body.ide3 | Should -Be 'local-lvm:30'
    $body.ide2 | Should -Be 'local:iso/x.iso,media=cdrom'
    $body.ContainsKey('scsihw') | Should -BeFalse
  }

  It 'refuses <Case>' -ForEach @(
    @{ Case = '-DiskGB without -Storage'; Params = @{ Name = 'x'; DiskGB = 10 }; Message = '*-DiskGB needs -Storage*' }
    @{ Case = '-Bios ovmf without -Storage'; Params = @{ Name = 'x'; Bios = 'ovmf' }; Message = '*-Bios ovmf needs -Storage*' }
    @{ Case = 'more disks than the bus has slots'; Params = @{ Name = 'x'; DiskGB = 1, 2, 3, 4, 5, 6, 7; DiskBus = 'sata'; Storage = 's' }; Message = '*room for 6 disks*' }
    @{ Case = 'vmid in -Parameter'; Params = @{ Name = 'x'; Parameter = @{ vmid = 1 } }; Message = "*cannot set 'vmid'*" }
  ) {
    { New-PVEVM @Params } | Should -Throw $Message
    (Get-Request POST '^/nodes/').Count | Should -Be 0
  }

  It 'applies -Parameter last, overriding the computed options' {
    $null = New-PVEVM -Name app01 -DiskGB 10 -Storage local-lvm -Parameter @{ scsihw = 'lsi'; balloon = 0 }
    $body = Get-RequestBody POST '^/nodes/pve/qemu$'
    $body.scsihw | Should -Be 'lsi'
    $body.balloon | Should -Be '0'
  }

  It 'sends nothing under -WhatIf' {
    New-PVEVM -Name app01 -WhatIf
    (Get-Request POST '.*').Count | Should -Be 0
  }

  It 'returns the create task with -RunAsync' {
    $task = New-PVEVM -Name app01 -RunAsync
    $task.PSObject.TypeNames | Should -Contain 'PVEPS.Task'
    $task.Type | Should -Be 'qmcreate'
  }

  It 'writes an error and no VM when the create task fails' {
    $script:State.FailTasks = $true
    $r = Invoke-Streams { New-PVEVM -Name app01 }
    $r.Output.Count | Should -Be 0
    $r.Errors[0].FullyQualifiedErrorId | Should -BeLike 'PVETaskFailed*'
  }
}

Describe 'New-PVEContainer' {
  BeforeEach {
    Initialize-Lifecycle
  }

  It 'builds the create request from the parameters' {
    $params = @{
      Name          = 'ct01'
      OSTemplate    = 'local:vztmpl/debian-13.tar.zst'
      Storage       = 'local-lvm'
      DiskGB        = 16
      Cores         = 2
      MemoryGB      = 1
      SwapGB        = 0
      Password      = (ConvertTo-SecureString -String 'Secret123' -AsPlainText -Force)
      SshPublicKey  = 'ssh-ed25519 AAAA one', 'ssh-ed25519 BBBB two'
      NetworkBridge = 'vmbr0'
      IPAddress     = '192.0.2.10/24'
      Gateway       = '192.0.2.1'
      IPv6Address   = 'auto'
      Nesting       = $true
      Tags          = 'dns'
    }
    $null = New-PVEContainer @params
    $body = Get-RequestBody POST '^/nodes/pve/lxc$'
    $body.vmid | Should -Be '105'
    $body.hostname | Should -Be 'ct01'
    $body.ostemplate | Should -Be 'local:vztmpl/debian-13.tar.zst'
    $body.rootfs | Should -Be 'local-lvm:16'
    $body.cores | Should -Be '2'
    $body.memory | Should -Be '1024'
    $body.swap | Should -Be '0'
    $body.password | Should -Be 'Secret123'
    $body['ssh-public-keys'] | Should -Be "ssh-ed25519 AAAA one`nssh-ed25519 BBBB two"
    $body.net0 | Should -Be 'name=eth0,bridge=vmbr0,ip=192.0.2.10/24,gw=192.0.2.1,ip6=auto'
    $body.features | Should -Be 'nesting=1'
    $body.unprivileged | Should -Be '1'
    $body.tags | Should -Be 'dns'
  }

  It 'defaults to an 8 GiB unprivileged root file system and DHCP' {
    $ct = New-PVEContainer -Name ct01 -OSTemplate local:vztmpl/x.tar.zst -Storage local-lvm -NetworkBridge vmbr0
    $body = Get-RequestBody POST '^/nodes/pve/lxc$'
    $body.rootfs | Should -Be 'local-lvm:8'
    $body.unprivileged | Should -Be '1'
    $body.net0 | Should -Be 'name=eth0,bridge=vmbr0,ip=dhcp'
    $ct.PSObject.TypeNames | Should -Contain 'PVEPS.Container'
    $ct.Name | Should -Be 'ct01'
  }

  It 'sends unprivileged=0 with -Privileged and a plain-string password as given' {
    $null = New-PVEContainer -Name ct01 -OSTemplate t -Storage s -Privileged -Password 'Plain1234'
    $body = Get-RequestBody POST '^/nodes/pve/lxc$'
    $body.unprivileged | Should -Be '0'
    $body.password | Should -Be 'Plain1234'
  }

  It 'refuses <Name> without -NetworkBridge' -ForEach @(
    @{ Name = 'IPAddress'; Value = '192.0.2.1/24' }
    @{ Name = 'Gateway'; Value = '192.0.2.1' }
    @{ Name = 'IPv6Address'; Value = 'auto' }
  ) {
    $params = @{ Name = 'ct01'; OSTemplate = 't'; Storage = 's'; $Name = $Value }
    { New-PVEContainer @params } | Should -Throw "*-$Name needs -NetworkBridge*"
    (Get-Request POST '.*').Count | Should -Be 0
  }

  It 'does not write the password to the verbose stream' {
    $verbose = @(New-PVEContainer -Name ct01 -OSTemplate t -Storage s -Password 'Secret123' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
    $verbose.Count | Should -BeGreaterThan 0
    ($verbose | Where-Object { $_.Message -like '*Secret123*' }) | Should -BeNullOrEmpty
  }
}

Describe 'Remove-PVEVM and Remove-PVEContainer' {
  BeforeEach {
    Initialize-Lifecycle
  }

  It 'deletes a stopped VM, sends the options, and writes nothing' {
    $out = Remove-PVEVM -VMId 101 -Purge -DestroyUnreferencedDisks -Confirm:$false
    $out | Should -BeNullOrEmpty
    $calls = Get-Request DELETE '^/nodes/pve/qemu/101$'
    $calls.Count | Should -Be 1
    $query = ConvertFrom-Body $calls[0].Query
    $query.purge | Should -Be '1'
    $query['destroy-unreferenced-disks'] | Should -Be '1'
    $script:State.Guests.Contains('101') | Should -BeFalse
  }

  It 'refuses a running VM, decided on the live status' {
    $r = Invoke-Streams { Remove-PVEVM -VMId 100 -Confirm:$false }
    $r.Errors.Count | Should -Be 1
    $r.Errors[0].FullyQualifiedErrorId | Should -BeLike 'PVEGuestRunning*'
    $r.Errors[0].Exception.Message | Should -BeLike '*VM 100 (web01) on pve is running; stop it first with Stop-PVEVMGuest or Stop-PVEVM.*'
    (Get-Request DELETE '.*').Count | Should -Be 0
  }

  It 'sends nothing under -WhatIf' {
    Remove-PVEVM -VMId 101 -WhatIf
    (Get-Request DELETE '.*').Count | Should -Be 0
  }

  It 'deletes a template named by ID' {
    Remove-PVEVM -VMId 9000 -Confirm:$false
    (Get-Request DELETE '^/nodes/pve/qemu/9000$').Count | Should -Be 1
  }

  It 'matches a template by name only with -IncludeTemplate' {
    $r = Invoke-Streams { Remove-PVEVM -Name tmpl-debian -Confirm:$false }
    $r.Errors[0].Exception.Message | Should -BeLike "*'tmpl-debian' was not found*add -IncludeTemplate.*"
    (Get-Request DELETE '.*').Count | Should -Be 0
    Remove-PVEVM -Name tmpl-debian -IncludeTemplate -Confirm:$false
    (Get-Request DELETE '^/nodes/pve/qemu/9000$').Count | Should -Be 1
  }

  It 'does not let a wildcard sweep up templates' {
    Remove-PVEVM -Name '*' -Confirm:$false -ErrorAction SilentlyContinue
    (Get-Request DELETE '^/nodes/pve/qemu/9000$').Count | Should -Be 0
    (Get-Request DELETE '^/nodes/pve/qemu/10[12]$').Count | Should -Be 2
  }

  It 'removes VMs piped from Get-PVEVM' {
    Get-PVEVM -Name 'db*' | Remove-PVEVM -Confirm:$false
    (Get-Request DELETE '^/nodes/pve/qemu/10[12]$').Count | Should -Be 2
  }

  It 'returns the delete tasks with -RunAsync' {
    $tasks = @(Remove-PVEVM -VMId 101, 102 -Confirm:$false -RunAsync)
    $tasks.Count | Should -Be 2
    $tasks[0].Type | Should -Be 'qmdestroy'
  }

  It 'deletes a stopped container and refuses a running one' {
    $r = Invoke-Streams { Remove-PVEContainer -VMId 201, 200 -Purge -Confirm:$false }
    $r.Errors.Count | Should -Be 1
    $r.Errors[0].Exception.Message | Should -BeLike '*Container 200 (dns01) on pve is running; stop it first with Stop-PVEContainerGuest or Stop-PVEContainer.*'
    $calls = Get-Request DELETE '^/nodes/pve/lxc/'
    $calls.Count | Should -Be 1
    $calls[0].Path | Should -Be '/nodes/pve/lxc/201'
    (ConvertFrom-Body $calls[0].Query).purge | Should -Be '1'
  }

  It 'refuses a container ID with a hint to use the container cmdlets' {
    $r = Invoke-Streams { Remove-PVEVM -VMId 201 -Confirm:$false }
    $r.Errors[0].Exception.Message | Should -BeLike '*use the `*-PVEContainer cmdlets*'
    (Get-Request DELETE '.*').Count | Should -Be 0
  }
}

Describe 'Set-PVEVM' {
  BeforeEach {
    Initialize-Lifecycle
  }

  It 'sends the changes with POST .../config' {
    $null = Set-PVEVM -VMId 101 -Cores 4 -Sockets 2 -MemoryGB 8 -CpuType host -OSType win11 -Tags a, b -StartOnBoot $false -Protection $true -GuestAgent $true -Description 'notes'
    $body = Get-RequestBody POST '^/nodes/pve/qemu/101/config$'
    $body.cores | Should -Be '4'
    $body.sockets | Should -Be '2'
    $body.memory | Should -Be '8192'
    $body.cpu | Should -Be 'host'
    $body.ostype | Should -Be 'win11'
    $body.tags | Should -Be 'a;b'
    $body.onboot | Should -Be '0'
    $body.protection | Should -Be '1'
    $body.agent | Should -Be '1'
    $body.description | Should -Be 'notes'
    $body.ContainsKey('delete') | Should -BeFalse
  }

  It 'removes tags and description given as empty, and options in -Delete' {
    $null = Set-PVEVM -VMId 101 -Tags @() -Description '' -Delete balloon, vga
    $body = Get-RequestBody POST '^/nodes/pve/qemu/101/config$'
    @($body.delete -split ',' | Sort-Object) | Should -Be @('balloon', 'description', 'tags', 'vga')
    $body.ContainsKey('tags') | Should -BeFalse
  }

  It 'writes the VM with the new values from the live status' {
    $script:State.Guests['101'].tags = 'old'
    $vm = Set-PVEVM -VMId 101 -NewName db01-renamed -Tags new
    $vm.Name | Should -Be 'db01-renamed'
    $vm.Tags | Should -Be @('new')
  }

  It 'refuses a call with no change' {
    { Set-PVEVM -VMId 101 } | Should -Throw '*No change given*'
  }

  It 'refuses -NewName for several VMs and changes nothing' {
    { Set-PVEVM -Name 'db*' -NewName same } | Should -Throw '*2 VMs are targeted; nothing was changed*'
    (Get-Request POST '.*').Count | Should -Be 0
  }

  It 'warns about changes still pending on a running VM' {
    $script:State.Guests['100'].pending = @(
      @{ key = 'memory'; value = '2048'; pending = '4096' }
      @{ key = 'cores'; value = '2' }
      @{ key = 'balloon'; value = '0'; delete = 1 }
    )
    $r = Invoke-Streams { Set-PVEVM -VMId 100 -MemoryGB 4 }
    $r.Output.Count | Should -Be 1
    $r.Warnings.Count | Should -Be 1
    $r.Warnings[0].Message | Should -BeLike '*VM 100 (web01) on pve is running; these changes are pending*: memory, balloon'
  }

  It 'does not read pending changes for a stopped VM' {
    $null = Set-PVEVM -VMId 101 -Cores 2
    (Get-Request GET '/pending$').Count | Should -Be 0
  }

  It 'sends nothing under -WhatIf' {
    Set-PVEVM -VMId 101 -Cores 2 -WhatIf
    (Get-Request POST '.*').Count | Should -Be 0
  }
}

Describe 'Set-PVEContainer' {
  BeforeEach {
    Initialize-Lifecycle
  }

  It 'sends the changes with PUT .../config and writes the container (no task)' {
    $ct = Set-PVEContainer -VMId 201 -NewName proxy02 -Cores 2 -MemoryGB 0.5 -SwapGB 0 -StartOnBoot $true
    $body = Get-RequestBody PUT '^/nodes/pve/lxc/201/config$'
    $body.hostname | Should -Be 'proxy02'
    $body.cores | Should -Be '2'
    $body.memory | Should -Be '512'
    $body.swap | Should -Be '0'
    $body.onboot | Should -Be '1'
    $ct.Name | Should -Be 'proxy02'
    (Get-Request GET '^/nodes/pve/tasks/').Count | Should -Be 0
  }
}

Describe 'Copy-PVEVM and Copy-PVEContainer' {
  BeforeEach {
    Initialize-Lifecycle
  }

  It 'clones a template by name into the next free ID and writes the new VM' {
    $vm = Copy-PVEVM tmpl-debian -NewName web03
    $body = Get-RequestBody POST '^/nodes/pve/qemu/9000/clone$'
    $body.newid | Should -Be '105'
    $body.name | Should -Be 'web03'
    $body.ContainsKey('full') | Should -BeFalse
    $vm.VMId | Should -Be 105
    $vm.Name | Should -Be 'web03'
    $vm.PSObject.TypeNames | Should -Contain 'PVEPS.VM'
  }

  It 'sends the full-clone options' {
    $null = Copy-PVEVM -VMId 9000 -NewName web04 -NewVMId 120 -Full -Storage local-lvm -Format qcow2 -Pool web -Description d -Snapshot base
    $body = Get-RequestBody POST '^/nodes/pve/qemu/9000/clone$'
    $body.newid | Should -Be '120'
    $body.full | Should -Be '1'
    $body.storage | Should -Be 'local-lvm'
    $body.format | Should -Be 'qcow2'
    $body.pool | Should -Be 'web'
    $body.description | Should -Be 'd'
    $body.snapname | Should -Be 'base'
  }

  It 'describes a template clone as linked unless -Full is given' {
    $verbose = Copy-PVEVM -VMId 9000 -NewName x -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | Out-String
    $verbose | Should -BeLike '*Clone (linked clone) to VM 105 (x)*'
    $verbose = Copy-PVEVM -VMId 9000 -NewName y -NewVMId 106 -Full -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | Out-String
    $verbose | Should -BeLike '*Clone (full clone) to VM 106 (y)*'
    $verbose = Copy-PVEVM -VMId 101 -NewName z -NewVMId 107 -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | Out-String
    $verbose | Should -BeLike '*Clone (full clone)*'
  }

  It 'sends nothing under -WhatIf' {
    Copy-PVEVM -VMId 9000 -NewName x -WhatIf
    (Get-Request POST '.*').Count | Should -Be 0
  }

  It 'refuses more than one source' {
    $r = Invoke-Streams { Copy-PVEVM -Name 'db*' -NewName x }
    $r.Errors[0].Exception.Message | Should -BeLike '*matched 2 guests (101, 102)*'
    (Get-Request POST '.*').Count | Should -Be 0
  }

  It 'clones a container with hostname' {
    $ct = Copy-PVEContainer -VMId 9100 -NewName dns02
    $body = Get-RequestBody POST '^/nodes/pve/lxc/9100/clone$'
    $body.hostname | Should -Be 'dns02'
    $body.ContainsKey('name') | Should -BeFalse
    $ct.Name | Should -Be 'dns02'
    $ct.PSObject.TypeNames | Should -Contain 'PVEPS.Container'
  }

  It 'returns the clone task with -RunAsync' {
    (Copy-PVEVM -VMId 9000 -NewName x -RunAsync).Type | Should -Be 'qmclone'
  }
}

Describe 'ConvertTo-PVEVMTemplate and ConvertTo-PVEContainerTemplate' {
  BeforeEach {
    Initialize-Lifecycle
  }

  It 'converts a stopped VM and writes it as a template' {
    $vm = ConvertTo-PVEVMTemplate -VMId 101 -Confirm:$false
    (Get-Request POST '^/nodes/pve/qemu/101/template$').Count | Should -Be 1
    $vm.IsTemplate | Should -BeTrue
  }

  It 'converts a container (a call that returns no task) and writes it as a template' {
    $ct = ConvertTo-PVEContainerTemplate -VMId 201 -Confirm:$false
    (Get-Request POST '^/nodes/pve/lxc/201/template$').Count | Should -Be 1
    $ct.IsTemplate | Should -BeTrue
  }

  It 'skips a guest that is already a template, with a warning' {
    $r = Invoke-Streams { ConvertTo-PVEVMTemplate -VMId 9000 -Confirm:$false }
    $r.Warnings[0].Message | Should -BeLike '*VM 9000 (tmpl-debian) on pve is already a template*'
    $r.Output[0].VMId | Should -Be 9000
    (Get-Request POST '.*').Count | Should -Be 0
  }

  It 'refuses a running VM' {
    $r = Invoke-Streams { ConvertTo-PVEVMTemplate -VMId 100 -Confirm:$false }
    $r.Errors[0].FullyQualifiedErrorId | Should -BeLike 'PVEGuestRunning*'
    (Get-Request POST '.*').Count | Should -Be 0
  }
}

Describe 'Move-PVEVM' {
  BeforeEach {
    Initialize-Lifecycle
  }

  It 'moves every storage disk not already on the target, one at a time, skipping CD drives and pass-through' {
    $vm = Move-PVEVM -VMId 100 -Storage fast
    $moves = Get-Request POST '^/nodes/pve/qemu/100/move_disk$'
    $moves.Count | Should -Be 1
    $body = ConvertFrom-Body $moves[0].Body
    $body.disk | Should -Be 'scsi0'
    $body.storage | Should -Be 'fast'
    $body.ContainsKey('delete') | Should -BeFalse
    $vm.VMId | Should -Be 100
  }

  It 'moves the EFI vars disk too, and sends -DeleteSource and -Format' {
    $null = Move-PVEVM -VMId 101 -Storage fast -DeleteSource -Format qcow2
    $bodies = @(Get-Request POST '^/nodes/pve/qemu/101/move_disk$' | ForEach-Object { ConvertFrom-Body $_.Body })
    @($bodies | ForEach-Object { $_.disk }) | Should -Be @('efidisk0', 'virtio0')
    $bodies | ForEach-Object { $_.delete | Should -Be '1'; $_.format | Should -Be 'qcow2' }
  }

  It 'waits for each move before starting the next' {
    $null = Move-PVEVM -VMId 101 -Storage fast
    $order = @($script:Fake.Calls | Where-Object { $_.Path -match 'move_disk$|/tasks/' } | ForEach-Object { if ($_.Path -match 'move_disk$') { 'move' } else { 'wait' } })
    $order[0] | Should -Be 'move'
    $order[1] | Should -Be 'wait'
    [array]::IndexOf($order, 'move', 1) | Should -BeGreaterThan 1
  }

  It 'moves only the disks named in -Disk' {
    $null = Move-PVEVM -VMId 101 -Storage fast -Disk virtio0
    $moves = Get-Request POST 'move_disk$'
    $moves.Count | Should -Be 1
    (ConvertFrom-Body $moves[0].Body).disk | Should -Be 'virtio0'
  }

  It 'refuses a -Disk the VM does not have as a storage volume' {
    $r = Invoke-Streams { Move-PVEVM -VMId 100 -Storage fast -Disk ide2 }
    $r.Errors[0].FullyQualifiedErrorId | Should -BeLike 'PVEVolumeNotFound*'
    $r.Errors[0].Exception.Message | Should -BeLike "*no storage volume 'ide2'. Volumes: scsi0, scsi1.*"
    (Get-Request POST '.*').Count | Should -Be 0
  }

  It 'warns and writes the VM when nothing needs moving' {
    $r = Invoke-Streams { Move-PVEVM -VMId 102 -Storage fast }
    $r.Warnings[0].Message | Should -BeLike '*no volumes to move; they are already on fast*'
    $r.Output.Count | Should -Be 1
    (Get-Request POST '.*').Count | Should -Be 0
  }

  It 'stops moving the remaining disks of a VM after a failed move' {
    $script:State.FailMoveDisk = 'efidisk0'
    $r = Invoke-Streams { Move-PVEVM -VMId 101 -Storage fast }
    $r.Errors[0].FullyQualifiedErrorId | Should -BeLike 'PVETaskFailed*'
    $r.Output.Count | Should -Be 0
    (Get-Request POST 'move_disk$').Count | Should -Be 1
  }

  It 'sends nothing under -WhatIf' {
    Move-PVEVM -VMId 101 -Storage fast -WhatIf
    (Get-Request POST '.*').Count | Should -Be 0
  }
}

Describe 'Move-PVEContainer' {
  BeforeEach {
    Initialize-Lifecycle
  }

  It 'moves rootfs and volume mount points, not bind mounts' {
    $null = Move-PVEContainer -VMId 201 -Storage fast
    $bodies = @(Get-Request POST '^/nodes/pve/lxc/201/move_volume$' | ForEach-Object { ConvertFrom-Body $_.Body })
    @($bodies | ForEach-Object { $_.volume }) | Should -Be @('mp0', 'rootfs')
    $bodies[0].storage | Should -Be 'fast'
  }

  It 'moves only the volumes named in -Volume' {
    $null = Move-PVEContainer -VMId 201 -Storage fast -Volume rootfs -DeleteSource
    $moves = Get-Request POST 'move_volume$'
    $moves.Count | Should -Be 1
    $body = ConvertFrom-Body $moves[0].Body
    $body.volume | Should -Be 'rootfs'
    $body.delete | Should -Be '1'
  }
}

Describe 'Update-PVEGuestStatus' {
  BeforeEach {
    Initialize-Lifecycle
  }

  It 'replaces name and tags with the live values, and empties tags the endpoint omits' {
    InModuleScope PVEPS {
      $guest = [pscustomobject]@{
        VMId = 101; Name = 'stale'; Node = 'pve'; Type = 'qemu'; Status = 'running'; IsTemplate = $false; Cpus = 1
        MemoryGB = 1; MemoryUsedGB = $null; DiskGB = $null; CpuUsagePercent = $null; Uptime = $null; Tags = [string[]]@('old')
        Lock = $null; Connection = $script:DefaultPVEConnection
      }
      $null = Update-PVEGuestStatus -Guest $guest
      $guest.Name | Should -Be 'db01'
      $guest.Status | Should -Be 'stopped'
      $guest.Cpus | Should -Be 2
      $guest.MemoryGB | Should -Be 2
      $guest.Tags.Count | Should -Be 0
      $guest.IsTemplate | Should -BeFalse
    }
  }
}
