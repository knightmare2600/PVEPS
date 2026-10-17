#Requires -Modules Pester
# Phase 4 hardware cmdlets. HTTP is mocked (see TestHelpers.ps1); nothing here touches a real server.
# The fake server keeps each guest's configuration and applies config, resize and cloud-init requests to
# it the way PVE does for the cases tested here: new disks are allocated, detached disks become unusedN,
# and a request with a stale digest is refused.

BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  Mock -ModuleName PVEPS Start-Sleep { }

  function Initialize-Hardware {
    Reset-FakeState
    $script:State = @{
      Guests = [ordered]@{}
      Disk   = 10
    }
    $guests = @(
      @{ type = 'qemu'; vmid = 100; name = 'web01'; status = 'running'; template = 0; pending = @(); config = [ordered]@{
          name     = 'web01'
          scsi0    = 'local-lvm:vm-100-disk-0,iothread=1,size=32G'
          scsi2    = 'fast:vm-100-disk-1,size=100G'
          scsi10   = 'fast:vm-100-disk-2,size=1G'
          virtio0  = 'local-lvm:vm-100-disk-3,size=8G'
          ide2     = 'local:iso/debian.iso,media=cdrom'
          ide0     = 'local-lvm:vm-100-cloudinit,media=cdrom'
          net0     = 'virtio=BC:24:11:00:00:01,bridge=vmbr0,firewall=1,tag=10'
          net1     = 'e1000=BC:24:11:00:00:02,bridge=vmbr1,link_down=1'
          ciuser   = 'debian'
          sshkeys  = 'ssh-ed25519%20AAAA%20one%0Assh-ed25519%20BBBB%20two'
          ipconfig0 = 'ip=192.0.2.5/24,gw=192.0.2.1'
          ipconfig1 = 'ip6=auto'
          cipassword = '**********'
          nameserver = '192.0.2.53 192.0.2.54'
        }
      }
      @{ type = 'qemu'; vmid = 101; name = 'db01'; status = 'stopped'; template = 0; pending = @(); config = [ordered]@{ name = 'db01'; ide2 = 'none,media=cdrom'; ciupgrade = 0 } }
      @{ type = 'lxc'; vmid = 200; name = 'dns01'; status = 'stopped'; template = 0; pending = @(); config = [ordered]@{
          hostname = 'dns01'
          rootfs   = 'local-lvm:vm-200-disk-0,size=8G'
          mp0      = 'local-lvm:vm-200-disk-1,mp=/srv/data,backup=1,size=10G'
          mp1      = '/tank/media,mp=/mnt/media,ro=1'
          net0     = 'name=eth0,bridge=vmbr0,hwaddr=BC:24:11:00:02:00,ip=dhcp,type=veth'
        }
      }
    )
    foreach ($g in $guests) {
      $g.digest = 1
      $script:State.Guests[[string]$g.vmid] = $g
    }
    $script:Fake.Handler = $script:HardwareHandler
    $null = Connect-PVE -Server pve -User root@pam -Password 'x'
    $script:Fake.Calls.Clear()
  }

  function ConvertFrom-Body {
    param([string]$Body)
    $result = [ordered]@{}
    foreach ($pair in ($Body -split '&' | Where-Object { $_ })) {
      $key, $value = $pair -split '=', 2
      $result[[uri]::UnescapeDataString($key)] = [uri]::UnescapeDataString($value)
    }
    $result
  }

  function Add-Unused {
    param($Config, [string]$Volume)
    $i = 0
    while ($Config.Contains("unused$i")) { $i++ }
    $Config["unused$i"] = $Volume
  }

  $script:HardwareHandler = {
    param($Method, $Path, $Call)
    $state = $script:State
    $body = ConvertFrom-Body $Call.Body
    if ($Path -eq '/access/ticket') { return New-FakeResponse -Data @{ ticket = 'PVE:root@pam:AAAA::sig'; CSRFPreventionToken = 'AAAA:csrf'; username = 'root@pam' } }
    if ($Path -eq '/version') { return New-FakeResponse -Data @{ version = '9.2.1'; release = '9.2' } }
    if ($Path -eq '/cluster/resources') {
      return New-FakeResponse -Data @($state.Guests.Values | ForEach-Object { @{ type = $_.type; vmid = $_.vmid; name = $_.name; node = 'pve'; status = $_.status; template = $_.template } })
    }
    if ($Path -match '^/nodes/pve/tasks/(.+)/status$') {
      $upid = [uri]::UnescapeDataString($Matches[1])
      $parts = $upid -split ':'
      return New-FakeResponse -Data @{ upid = $upid; node = 'pve'; status = 'stopped'; exitstatus = 'OK'; type = $parts[5]; id = $parts[6]; user = 'root@pam' }
    }
    if ($Path -notmatch '^/nodes/pve/(qemu|lxc)/(\d+)/(.+)$') {
      return New-FakeResponse -Status 501 -Reason "Unexpected $Method $Path in test" -Data $null
    }
    $type = $Matches[1]
    $id = $Matches[2]
    $rest = $Matches[3]
    $g = $state.Guests[$id]
    $upid = "UPID:pve:0000A1B2:00C3D4E5:67000000:qmconfig:$id`:root@pam:"

    if ($rest -eq 'status/current') { return New-FakeResponse -Data @{ vmid = [int]$id; status = $g.status; name = $g.name } }
    if ($rest -eq 'pending') { return New-FakeResponse -Data @($g.pending) }
    if ($rest -eq 'cloudinit' -and $Method -eq 'GET') { return New-FakeResponse -Data @(@{ key = 'ciuser'; value = 'debian' }, @{ key = 'ipconfig0'; value = 'ip=dhcp'; pending = 'ip=192.0.2.5/24,gw=192.0.2.1' }) }
    if ($rest -eq 'cloudinit' -and $Method -eq 'PUT') { return New-FakeResponse -Data $null }
    if ($rest -eq 'config' -and $Method -eq 'GET') { return New-FakeResponse -Data ($g.config + @{ digest = [string]$g.digest }) }

    if ($body.Contains('digest') -and $body.digest -ne [string]$g.digest) {
      return New-FakeResponse -Status 500 -Reason 'detected modified configuration - file changed by other user? Try again.' -Data $null
    }
    if ($rest -eq 'resize') {
      $entry = $g.config[$body.disk]
      $g.config[$body.disk] = ($entry -replace ',size=[^,]+', '') + ",size=$($body.size)"
      $g.digest++
      return New-FakeResponse -Data $upid
    }
    if ($rest -eq 'config') {
      foreach ($key in ($body.delete -split ',' | Where-Object { $_ })) {
        $old = [string]$g.config[$key]
        $g.config.Remove($key)
        $volume = ($old -split ',')[0]
        if ($key -match '^(scsi|virtio|sata|ide|mp)\d+$' -and $volume -match '^[^/:]+:' -and $old -notmatch 'media=cdrom' -and $body.force -ne '1') {
          Add-Unused -Config $g.config -Volume $volume
        }
      }
      foreach ($key in $body.Keys) {
        if ($key -in 'delete', 'digest', 'force') { continue }
        $value = $body[$key]
        if ($value -match '^([^:,]+):cloudinit$') {
          $value = "$($Matches[1]):vm-$id-cloudinit,media=cdrom"
        }
        elseif ($value -match '^([^:,/]+):(\d+)(,.*)?$') {
          $value = '{0}:vm-{1}-disk-{2}{3},size={4}G' -f $Matches[1], $id, $state.Disk, $Matches[3], $Matches[2]
          $state.Disk++
        }
        $g.config[$key] = $value
      }
      $g.digest++
      if ($Method -eq 'PUT') { return New-FakeResponse -Data $null }
      return New-FakeResponse -Data $upid
    }
    New-FakeResponse -Status 501 -Reason "Unexpected $Method $Path in test" -Data $null
  }

  function Get-Request {
    param([string]$Method, [string]$PathPattern)
    @($script:Fake.Calls | Where-Object { $_.Method -eq $Method -and $_.Path -match $PathPattern })
  }

  function Get-SingleBody {
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
    @{ Command = 'New-PVEVMHardDisk'; Impact = 'Medium' }
    @{ Command = 'Set-PVEVMHardDisk'; Impact = 'Medium' }
    @{ Command = 'Remove-PVEVMHardDisk'; Impact = 'High' }
    @{ Command = 'New-PVEVMNetworkAdapter'; Impact = 'Medium' }
    @{ Command = 'Set-PVEVMNetworkAdapter'; Impact = 'Medium' }
    @{ Command = 'Remove-PVEVMNetworkAdapter'; Impact = 'High' }
    @{ Command = 'New-PVEVMCDDrive'; Impact = 'Medium' }
    @{ Command = 'Set-PVEVMCDDrive'; Impact = 'Medium' }
    @{ Command = 'Remove-PVEVMCDDrive'; Impact = 'Medium' }
    @{ Command = 'Set-PVEVMCloudInit'; Impact = 'Medium' }
    @{ Command = 'New-PVEContainerVolume'; Impact = 'Medium' }
    @{ Command = 'Set-PVEContainerVolume'; Impact = 'Medium' }
    @{ Command = 'Remove-PVEContainerVolume'; Impact = 'High' }
    @{ Command = 'New-PVEContainerNetworkAdapter'; Impact = 'Medium' }
    @{ Command = 'Set-PVEContainerNetworkAdapter'; Impact = 'Medium' }
    @{ Command = 'Remove-PVEContainerNetworkAdapter'; Impact = 'High' }
  ) {
    $metadata = [System.Management.Automation.CommandMetadata]::new((Get-Command $Command))
    $metadata.SupportsShouldProcess | Should -BeTrue
    [string]$metadata.ConfirmImpact | Should -Be $Impact
  }
}

Describe 'Property string helpers' {
  It 'ConvertTo-PVEPropertyString writes the default key bare and first, drops $null, and writes booleans as 1/0' {
    InModuleScope PVEPS {
      ConvertTo-PVEPropertyString -Option ([ordered]@{ size = '8G'; file = 'local:vm-1-disk-0'; ssd = $true; cache = $null; ro = $false }) -DefaultKey file |
        Should -Be 'local:vm-1-disk-0,size=8G,ssd=1,ro=0'
      ConvertTo-PVEPropertyString -Option ([ordered]@{ name = 'eth0'; ip = 'dhcp' }) | Should -Be 'name=eth0,ip=dhcp'
    }
  }

  It 'ConvertFrom-PVENetworkOption reads the model=MAC, model= and bare-model forms' {
    InModuleScope PVEPS {
      $a = ConvertFrom-PVENetworkOption -Value 'virtio=BC:24:11:00:00:01,bridge=vmbr0,tag=5'
      $a.model | Should -Be 'virtio'
      $a.macaddr | Should -Be 'BC:24:11:00:00:01'
      $a.bridge | Should -Be 'vmbr0'
      $a.tag | Should -Be '5'
      $b = ConvertFrom-PVENetworkOption -Value 'model=e1000,macaddr=BC:24:11:00:00:02,bridge=vmbr1'
      $b.model | Should -Be 'e1000'
      $b.macaddr | Should -Be 'BC:24:11:00:00:02'
      $c = ConvertFrom-PVENetworkOption -Value 'virtio,bridge=vmbr0'
      $c.model | Should -Be 'virtio'
      $c.macaddr | Should -BeNullOrEmpty
    }
  }

  It 'ConvertTo-PVENetworkOptionString writes model=MAC first, or the bare model without a MAC' {
    InModuleScope PVEPS {
      ConvertTo-PVENetworkOptionString -Option (ConvertFrom-PVENetworkOption -Value 'model=e1000,macaddr=BC:24:11:00:00:02,bridge=vmbr1') |
        Should -Be 'e1000=BC:24:11:00:00:02,bridge=vmbr1'
      ConvertTo-PVENetworkOptionString -Option ([ordered]@{ model = 'virtio'; macaddr = $null; bridge = 'vmbr0' }) | Should -Be 'virtio,bridge=vmbr0'
      ConvertTo-PVENetworkOptionString -Option ([ordered]@{ model = 'virtio'; macaddr = $null }) | Should -Be 'virtio'
    }
  }

  It 'ConvertFrom-PVESize reads <Size> as <Bytes> bytes' -ForEach @(
    @{ Size = '32G'; Bytes = 34359738368 }
    @{ Size = '512M'; Bytes = 536870912 }
    @{ Size = '4K'; Bytes = 4096 }
    @{ Size = '1.5T'; Bytes = 1649267441664 }
    @{ Size = '4096'; Bytes = 4096 }
  ) {
    InModuleScope PVEPS -Parameters @{ Size = $Size; Bytes = $Bytes } {
      param($Size, $Bytes)
      ConvertFrom-PVESize $Size | Should -Be $Bytes
    }
  }

  It 'ConvertFrom-PVESize returns $null for something else' {
    InModuleScope PVEPS {
      ConvertFrom-PVESize 'big' | Should -BeNullOrEmpty
      ConvertFrom-PVESize '' | Should -BeNullOrEmpty
    }
  }

  It 'Test-PVECloudInitVolume recognises cloud-init images: <Volume> is <Expected>' -ForEach @(
    @{ Volume = 'local-lvm:vm-100-cloudinit'; Expected = $true }
    @{ Volume = 'local:100/vm-100-cloudinit.qcow2'; Expected = $true }
    @{ Volume = 'local:iso/vm-100-cloudinit-notes.iso'; Expected = $false }
    @{ Volume = 'local-lvm:vm-100-disk-0'; Expected = $false }
    @{ Volume = 'none'; Expected = $false }
  ) {
    InModuleScope PVEPS -Parameters @{ Volume = $Volume; Expected = $Expected } {
      param($Volume, $Expected)
      Test-PVECloudInitVolume -Volume $Volume | Should -Be $Expected
    }
  }
}

Describe 'Get-PVEVMHardDisk' {
  BeforeEach {
    Initialize-Hardware
  }

  It 'lists the disks, not CD drives, sorted by bus and then index as a number' {
    $disks = @(Get-PVEVMHardDisk -VMId 100)
    @($disks | ForEach-Object { $_.Device }) | Should -Be @('scsi0', 'scsi2', 'scsi10', 'virtio0')
    $disks[0].PSObject.TypeNames | Should -Contain 'PVEPS.HardDisk'
    $disks[0].Storage | Should -Be 'local-lvm'
    $disks[0].SizeGB | Should -Be 32
    $disks[0].IOThread | Should -BeTrue
    $disks[0].SSD | Should -BeFalse
    $disks[0].Bus | Should -Be 'scsi'
    $disks[0].VMName | Should -Be 'web01'
    $disks[0].Options.iothread | Should -Be '1'
  }

  It 'takes VMs from the pipeline and filters by -Device' {
    $disks = @(Get-PVEVM web01 | Get-PVEVMHardDisk -Device 'scsi*')
    $disks.Count | Should -Be 3
  }

  It 'reports a named disk that does not exist, and keeps quiet for a wildcard' {
    $r = Invoke-Streams { Get-PVEVMHardDisk -VMId 100 -Device scsi5, 'sata*' }
    $r.Output.Count | Should -Be 0
    $r.Errors.Count | Should -Be 1
    $r.Errors[0].Exception.Message | Should -Be "VM 100 (web01) on pve hard disk 'scsi5' was not found on pve."
  }

  It 'finds VMs by -VMName' {
    @(Get-PVEVMHardDisk -VMName 'web*').Count | Should -Be 4
  }
}

Describe 'New-PVEVMHardDisk' {
  BeforeEach {
    Initialize-Hardware
  }

  It 'adds a disk at the lowest free index with the options, sending the digest' {
    $disk = New-PVEVMHardDisk -VMId 100 -SizeGB 50 -Storage local-lvm -SSD -Discard -IOThread -NoBackup -Cache writeback
    $body = Get-SingleBody POST '^/nodes/pve/qemu/100/config$'
    $body.scsi1 | Should -Be 'local-lvm:50,cache=writeback,ssd=1,discard=on,iothread=1,backup=0'
    $body.digest | Should -Be '1'
    $disk.Device | Should -Be 'scsi1'
    $disk.SizeGB | Should -Be 50
    $disk.Volume | Should -BeLike 'local-lvm:vm-100-disk-*'
  }

  It 'attaches an existing volume with -Volume' {
    $null = New-PVEVMHardDisk -VMId 101 -Volume local-lvm:vm-101-disk-7 -Bus virtio
    (Get-SingleBody POST '^/nodes/pve/qemu/101/config$').virtio0 | Should -Be 'local-lvm:vm-101-disk-7'
  }

  It 'skips the ide indexes that are already used' {
    $null = New-PVEVMHardDisk -VMId 101 -SizeGB 1 -Storage s -Bus ide
    (Get-SingleBody POST 'config$').Keys | Should -Contain 'ide0'
    Initialize-Hardware
    $null = New-PVEVMHardDisk -VMId 100 -SizeGB 1 -Storage s -Bus ide
    (Get-SingleBody POST 'config$').Keys | Should -Contain 'ide1'
  }

  It 'refuses an index already in use without sending anything' {
    $r = Invoke-Streams { New-PVEVMHardDisk -VMId 100 -SizeGB 1 -Storage s -Index 0 }
    $r.Errors[0].FullyQualifiedErrorId | Should -BeLike 'PVEDeviceInUse*'
    $r.Errors[0].Exception.Message | Should -Be 'VM 100 (web01) on pve already has scsi0.'
    (Get-Request POST '.*').Count | Should -Be 0
  }

  It 'refuses <Case>' -ForEach @(
    @{ Case = 'no size or volume'; Params = @{ VMId = 100 }; Message = '*-SizeGB with -Storage*' }
    @{ Case = '-SizeGB without -Storage'; Params = @{ VMId = 100; SizeGB = 1 }; Message = '*-SizeGB with -Storage*' }
    @{ Case = '-Volume with -SizeGB'; Params = @{ VMId = 100; Volume = 'x:y'; SizeGB = 1 }; Message = '*not both*' }
    @{ Case = 'an index beyond the bus'; Params = @{ VMId = 100; SizeGB = 1; Storage = 's'; Bus = 'sata'; Index = 6 }; Message = '*indexes 0 to 5*' }
  ) {
    { New-PVEVMHardDisk @Params } | Should -Throw $Message
  }

  It 'warns about a pending change on a running VM' {
    $script:State.Guests['100'].pending = @(@{ key = 'scsi1'; pending = 'local-lvm:vm-100-disk-9,size=1G' })
    $r = Invoke-Streams { New-PVEVMHardDisk -VMId 100 -SizeGB 1 -Storage local-lvm }
    $r.Warnings[0].Message | Should -BeLike '*pending until it is next started*: scsi1'
    $r.Output.Count | Should -Be 1
  }

  It 'sends nothing under -WhatIf' {
    New-PVEVMHardDisk -VMId 100 -SizeGB 1 -Storage s -WhatIf
    (Get-Request POST '.*').Count | Should -Be 0
  }
}

Describe 'Set-PVEVMHardDisk' {
  BeforeEach {
    Initialize-Hardware
  }

  It 'grows a disk with PUT .../resize' {
    $disk = Set-PVEVMHardDisk -VMId 100 -Device scsi0 -SizeGB 64.5
    $body = Get-SingleBody PUT '^/nodes/pve/qemu/100/resize$'
    $body.disk | Should -Be 'scsi0'
    $body.size | Should -Be '64.5G'
    $disk.SizeGB | Should -Be 64.5
  }

  It 'refuses to shrink a disk and sends nothing' {
    $r = Invoke-Streams { Set-PVEVMHardDisk -VMId 100 -Device scsi0 -SizeGB 16 }
    $r.Errors[0].FullyQualifiedErrorId | Should -BeLike 'PVEShrinkNotSupported*'
    (Get-Request PUT '.*').Count | Should -Be 0
  }

  It 'skips a resize to the current size with a warning' {
    $r = Invoke-Streams { Set-PVEVMHardDisk -VMId 100 -Device scsi0 -SizeGB 32 }
    $r.Warnings[0].Message | Should -BeLike '*already 32 GiB*'
    (Get-Request PUT '.*').Count | Should -Be 0
    $r.Output.Count | Should -Be 1
  }

  It 'changes options and keeps the ones not named' {
    $null = Set-PVEVMHardDisk -VMId 100 -Device scsi0 -SSD $true -Discard $false -Parameter @{ iothread = $null; iops_rd = 500 }
    $body = Get-SingleBody POST '^/nodes/pve/qemu/100/config$'
    $body.scsi0 | Should -Be 'local-lvm:vm-100-disk-0,size=32G,ssd=1,discard=ignore,iops_rd=500'
    $body.digest | Should -Be '1'
  }

  It 'sends the current digest for each of several disks on one VM' {
    Get-PVEVMHardDisk -VMId 100 -Device scsi2, scsi10 | Set-PVEVMHardDisk -Backup $false
    $bodies = @(Get-Request POST 'config$' | ForEach-Object { ConvertFrom-Body $_.Body })
    $bodies.Count | Should -Be 2
    $bodies[0].digest | Should -Be '1'
    $bodies[1].digest | Should -Be '2'
  }

  It 'resizes and then changes options with a digest read after the resize' {
    $null = Set-PVEVMHardDisk -VMId 100 -Device scsi0 -SizeGB 40 -SSD $true
    (Get-SingleBody POST 'config$').digest | Should -Be '2'
  }

  It 'refuses a call with no change' {
    { Set-PVEVMHardDisk -VMId 100 -Device scsi0 } | Should -Throw '*No change given*'
  }
}

Describe 'Remove-PVEVMHardDisk' {
  BeforeEach {
    Initialize-Hardware
  }

  It 'detaches a disk, which PVE keeps as an unused disk' {
    $out = Remove-PVEVMHardDisk -VMId 100 -Device scsi2 -Confirm:$false
    $out | Should -BeNullOrEmpty
    $body = Get-SingleBody POST '^/nodes/pve/qemu/100/config$'
    $body.delete | Should -Be 'scsi2'
    $body.Contains('force') | Should -BeFalse
    $script:State.Guests['100'].config.unused0 | Should -Be 'fast:vm-100-disk-1'
  }

  It 'deletes the volume with -DeletePermanently (force=1)' {
    Remove-PVEVMHardDisk -VMId 100 -Device scsi2 -DeletePermanently -Confirm:$false
    (Get-SingleBody POST 'config$').force | Should -Be '1'
    $script:State.Guests['100'].config.Contains('unused0') | Should -BeFalse
  }

  It 'removes several disks of one VM, each with a current digest' {
    Remove-PVEVMHardDisk -VMId 100 -Device scsi2, scsi10 -Confirm:$false
    @(Get-Request POST 'config$').Count | Should -Be 2
    $script:State.Guests['100'].config.Contains('scsi10') | Should -BeFalse
  }

  It 'sends nothing under -WhatIf' {
    Remove-PVEVMHardDisk -VMId 100 -Device scsi2 -WhatIf
    (Get-Request POST '.*').Count | Should -Be 0
  }

  It 'will not remove a CD drive as a hard disk' {
    $r = Invoke-Streams { Remove-PVEVMHardDisk -VMId 100 -Device ide2 -Confirm:$false }
    $r.Errors[0].Exception.Message | Should -BeLike "*hard disk 'ide2' was not found*"
    (Get-Request POST '.*').Count | Should -Be 0
  }
}

Describe 'VM network adapters' {
  BeforeEach {
    Initialize-Hardware
  }

  It 'Get-PVEVMNetworkAdapter reads model, MAC, bridge, VLAN, firewall and link state' {
    $nics = @(Get-PVEVMNetworkAdapter -VMId 100)
    $nics.Count | Should -Be 2
    $nics[0].Model | Should -Be 'virtio'
    $nics[0].MacAddress | Should -Be 'BC:24:11:00:00:01'
    $nics[0].Bridge | Should -Be 'vmbr0'
    $nics[0].VlanTag | Should -Be 10
    $nics[0].Firewall | Should -BeTrue
    $nics[0].Connected | Should -BeTrue
    $nics[1].Connected | Should -BeFalse
    $nics[1].VlanTag | Should -BeNullOrEmpty
  }

  It 'New-PVEVMNetworkAdapter adds net2 without a MAC so PVE generates one' {
    $null = New-PVEVMNetworkAdapter -VMId 100 -Bridge vmbr2 -VlanTag 20 -Firewall -Mtu 1 -Queues 4 -RateLimitMBps 12.5
    (Get-SingleBody POST 'config$').net2 | Should -Be 'virtio,bridge=vmbr2,tag=20,firewall=1,mtu=1,queues=4,rate=12.5'
  }

  It 'New-PVEVMNetworkAdapter writes a given MAC in model=MAC form' {
    $nic = New-PVEVMNetworkAdapter -VMId 101 -Bridge vmbr0 -Model e1000 -MacAddress bc:24:11:aa:bb:cc -Disconnected
    (Get-SingleBody POST 'config$').net0 | Should -Be 'e1000=BC:24:11:AA:BB:CC,bridge=vmbr0,link_down=1'
    $nic.Device | Should -Be 'net0'
    $nic.Connected | Should -BeFalse
  }

  It 'Set-PVEVMNetworkAdapter changes the model and keeps the MAC, and removes the VLAN tag with 0' {
    $nic = Set-PVEVMNetworkAdapter -VMId 100 -Device net0 -Model e1000 -VlanTag 0 -Firewall $false
    (Get-SingleBody POST 'config$').net0 | Should -Be 'e1000=BC:24:11:00:00:01,bridge=vmbr0,firewall=0'
    $nic.Model | Should -Be 'e1000'
    $nic.VlanTag | Should -BeNullOrEmpty
  }

  It 'Set-PVEVMNetworkAdapter -Connected brings the link up or takes it down' {
    $null = Set-PVEVMNetworkAdapter -VMId 100 -Device net1 -Connected $true
    (Get-SingleBody POST 'config$').net1 | Should -Be 'e1000=BC:24:11:00:00:02,bridge=vmbr1'
    Initialize-Hardware
    $null = Set-PVEVMNetworkAdapter -VMId 100 -Device net0 -Connected $false
    (Get-SingleBody POST 'config$').net0 | Should -Be 'virtio=BC:24:11:00:00:01,bridge=vmbr0,firewall=1,tag=10,link_down=1'
  }

  It 'Remove-PVEVMNetworkAdapter deletes the entry' {
    Get-PVEVMNetworkAdapter -VMId 100 -Device net1 | Remove-PVEVMNetworkAdapter -Confirm:$false
    (Get-SingleBody POST 'config$').delete | Should -Be 'net1'
  }
}

Describe 'VM CD drives' {
  BeforeEach {
    Initialize-Hardware
  }

  It 'Get-PVEVMCDDrive lists CD drives, not cloud-init drives or disks' {
    $drives = @(Get-PVEVMCDDrive -VMId 100)
    $drives.Count | Should -Be 1
    $drives[0].Device | Should -Be 'ide2'
    $drives[0].IsoImage | Should -Be 'local:iso/debian.iso'
    (Get-PVEVMCDDrive -VMId 101).IsoImage | Should -BeNullOrEmpty
  }

  It 'Set-PVEVMCDDrive inserts an ISO and keeps media=cdrom' {
    $drive = Set-PVEVMCDDrive -VMId 101 -Device ide2 -IsoImage local:iso/virtio-win.iso
    (Get-SingleBody POST 'config$').ide2 | Should -Be 'local:iso/virtio-win.iso,media=cdrom'
    $drive.IsoImage | Should -Be 'local:iso/virtio-win.iso'
  }

  It 'Set-PVEVMCDDrive -NoMedia ejects' {
    $drive = Get-PVEVMCDDrive -VMId 100 | Set-PVEVMCDDrive -NoMedia
    (Get-SingleBody POST 'config$').ide2 | Should -Be 'none,media=cdrom'
    $drive.IsoImage | Should -BeNullOrEmpty
  }

  It 'New-PVEVMCDDrive adds an empty drive at the lowest free index' {
    $drive = New-PVEVMCDDrive -VMId 100
    (Get-SingleBody POST 'config$').ide1 | Should -Be 'none,media=cdrom'
    $drive.Device | Should -Be 'ide1'
  }

  It 'Remove-PVEVMCDDrive deletes the drive and refuses a cloud-init drive' {
    Remove-PVEVMCDDrive -VMId 100 -Device ide2 -Confirm:$false
    (Get-SingleBody POST 'config$').delete | Should -Be 'ide2'
    $r = Invoke-Streams { Remove-PVEVMCDDrive -VMId 100 -Device ide0 -Confirm:$false }
    $r.Errors[0].Exception.Message | Should -BeLike "*CD drive 'ide0' was not found*"
  }
}

Describe 'Get-PVEVMCloudInit' {
  BeforeEach {
    Initialize-Hardware
  }

  It 'reads the drive, user, decoded SSH keys, IP and DNS settings, and pending state' {
    $ci = Get-PVEVMCloudInit -VMId 100
    $ci.PSObject.TypeNames | Should -Contain 'PVEPS.CloudInit'
    $ci.Drive | Should -Be 'ide0'
    $ci.DriveStorage | Should -Be 'local-lvm'
    $ci.User | Should -Be 'debian'
    $ci.PasswordSet | Should -BeTrue
    $ci.SshPublicKey | Should -Be @('ssh-ed25519 AAAA one', 'ssh-ed25519 BBBB two')
    $ci.IPConfig.Count | Should -Be 2
    $ci.IPConfig[0].IPAddress | Should -Be '192.0.2.5/24'
    $ci.IPConfig[0].Gateway | Should -Be '192.0.2.1'
    $ci.IPConfig[1].Index | Should -Be 1
    $ci.IPConfig[1].IPv6Address | Should -Be 'auto'
    "$($ci.IPConfig[0])" | Should -Be 'net0: ip=192.0.2.5/24,gw=192.0.2.1'
    "$($ci.IPConfig[1])" | Should -Be 'net1: ip6=auto'
    $ci.Nameserver | Should -Be @('192.0.2.53', '192.0.2.54')
    $ci.Upgrade | Should -BeTrue
    $ci.IsPending | Should -BeTrue
  }

  It 'reports no drive, no pending state, and an explicit ciupgrade=0' {
    $ci = Get-PVEVMCloudInit -VMId 101
    $ci.Drive | Should -BeNullOrEmpty
    $ci.IsPending | Should -BeNullOrEmpty
    $ci.Upgrade | Should -BeFalse
    $ci.SshPublicKey.Count | Should -Be 0
    (Get-Request GET '/cloudinit$').Count | Should -Be 0
  }
}

Describe 'Set-PVEVMCloudInit' {
  BeforeEach {
    Initialize-Hardware
  }

  It 'URL-encodes the SSH keys, as the sshkeys option format requires' {
    $null = Set-PVEVMCloudInit -VMId 100 -SshPublicKey 'ssh-ed25519 AAAA x@y', 'ssh-rsa BBBB+/= z'
    $body = Get-SingleBody POST 'config$'
    $body.sshkeys | Should -Be 'ssh-ed25519%20AAAA%20x%40y%0Assh-rsa%20BBBB%2B%2F%3D%20z'
    $body.sshkeys | Should -Match "^[-%a-zA-Z0-9_.!~*'()]*$"
  }

  It 'merges IP settings into the current ipconfigN' {
    $null = Set-PVEVMCloudInit -VMId 100 -IPAddress 192.0.2.6/24
    (Get-SingleBody POST 'config$').ipconfig0 | Should -Be 'ip=192.0.2.6/24,gw=192.0.2.1'
  }

  It 'applies IP settings to the adapter given by -NetworkIndex' {
    $null = Set-PVEVMCloudInit -VMId 100 -NetworkIndex 1 -IPAddress dhcp
    (Get-SingleBody POST 'config$').ipconfig1 | Should -Be 'ip6=auto,ip=dhcp'
  }

  It 'removes settings given as empty, deleting an ipconfigN left empty' {
    $null = Set-PVEVMCloudInit -VMId 100 -User '' -SshPublicKey @() -NetworkIndex 1 -IPv6Address ''
    $body = Get-SingleBody POST 'config$'
    @($body.delete -split ',' | Sort-Object) | Should -Be @('ciuser', 'ipconfig1', 'sshkeys')
  }

  It 'sends the password from a SecureString and joins DNS settings with spaces' {
    $null = Set-PVEVMCloudInit -VMId 100 -Password (ConvertTo-SecureString 'S3cret!' -AsPlainText -Force) -Nameserver 192.0.2.1, 192.0.2.2 -SearchDomain example.com -Upgrade $false -Type nocloud
    $body = Get-SingleBody POST 'config$'
    $body.cipassword | Should -Be 'S3cret!'
    $body.nameserver | Should -Be '192.0.2.1 192.0.2.2'
    $body.searchdomain | Should -Be 'example.com'
    $body.ciupgrade | Should -Be '0'
    $body.citype | Should -Be 'nocloud'
  }

  It 'adds a cloud-init drive with -Storage when the VM has none' {
    $ci = Set-PVEVMCloudInit -VMId 101 -User admin -Storage local-lvm
    $body = Get-SingleBody POST 'config$'
    $body.ide0 | Should -Be 'local-lvm:cloudinit'
    $ci.Drive | Should -Be 'ide0'
  }

  It 'leaves an existing cloud-init drive alone' {
    $null = Set-PVEVMCloudInit -VMId 100 -User admin -Storage local-lvm
    (Get-SingleBody POST 'config$').Keys | Should -Not -Contain 'ide1'
  }

  It 'warns when the VM has no drive and no -Storage is given' {
    $r = Invoke-Streams { Set-PVEVMCloudInit -VMId 101 -User admin }
    $r.Warnings[0].Message | Should -BeLike '*has no cloud-init drive*'
    $r.Output.Count | Should -Be 1
  }

  It 'regenerates the drive with -Regenerate' {
    $null = Set-PVEVMCloudInit -VMId 100 -User admin -Regenerate
    (Get-Request PUT '^/nodes/pve/qemu/100/cloudinit$').Count | Should -Be 1
  }

  It 'refuses a call with no change' {
    { Set-PVEVMCloudInit -VMId 100 } | Should -Throw '*No change given*'
  }

  It 'does not write the password to the verbose stream' {
    $verbose = @(Set-PVEVMCloudInit -VMId 100 -Password 'S3cret!' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
    ($verbose | Where-Object { $_.Message -like '*S3cret*' }) | Should -BeNullOrEmpty
  }
}

Describe 'Container volumes' {
  BeforeEach {
    Initialize-Hardware
  }

  It 'Get-PVEContainerVolume lists rootfs first, then mount points, including bind mounts' {
    $volumes = @(Get-PVEContainerVolume -VMId 200)
    @($volumes | ForEach-Object { $_.Device }) | Should -Be @('rootfs', 'mp0', 'mp1')
    $volumes[0].Path | Should -Be '/'
    $volumes[0].SizeGB | Should -Be 8
    $volumes[1].Path | Should -Be '/srv/data'
    $volumes[1].Storage | Should -Be 'local-lvm'
    $volumes[2].IsBindMount | Should -BeTrue
    $volumes[2].Storage | Should -BeNullOrEmpty
    $volumes[2].ReadOnly | Should -BeTrue
  }

  It 'New-PVEContainerVolume adds a volume mount point with PUT' {
    $volume = New-PVEContainerVolume -VMId 200 -Path /srv/logs -SizeGB 4 -Storage local-lvm -Backup
    (Get-SingleBody PUT '^/nodes/pve/lxc/200/config$').mp2 | Should -Be 'local-lvm:4,mp=/srv/logs,backup=1'
    $volume.Device | Should -Be 'mp2'
    $volume.SizeGB | Should -Be 4
  }

  It 'New-PVEContainerVolume adds a bind mount' {
    $null = New-PVEContainerVolume -VMId 200 -Path /mnt/x -HostPath /tank/x -ReadOnly
    (Get-SingleBody PUT 'config$').mp2 | Should -Be '/tank/x,mp=/mnt/x,ro=1'
  }

  It 'Set-PVEContainerVolume grows rootfs with PUT .../resize' {
    $volume = Set-PVEContainerVolume -VMId 200 -Device rootfs -SizeGB 16
    $body = Get-SingleBody PUT '^/nodes/pve/lxc/200/resize$'
    $body.disk | Should -Be 'rootfs'
    $body.size | Should -Be '16G'
    $volume.SizeGB | Should -Be 16
  }

  It 'Set-PVEContainerVolume refuses a path for rootfs and a size for a bind mount' {
    $r = Invoke-Streams { Set-PVEContainerVolume -VMId 200 -Device rootfs -Path /x }
    $r.Errors[0].Exception.Message | Should -BeLike '*root file system*'
    $r = Invoke-Streams { Set-PVEContainerVolume -VMId 200 -Device mp1 -SizeGB 5 }
    $r.Errors[0].Exception.Message | Should -BeLike '*bind mount*'
    (Get-Request PUT '.*').Count | Should -Be 0
  }

  It 'Set-PVEContainerVolume changes options and keeps the rest' {
    $null = Set-PVEContainerVolume -VMId 200 -Device mp0 -Backup $false -ReadOnly $true
    (Get-SingleBody PUT 'config$').mp0 | Should -Be 'local-lvm:vm-200-disk-1,mp=/srv/data,backup=0,size=10G,ro=1'
  }

  It 'Remove-PVEContainerVolume detaches, keeping the volume as unused' {
    Remove-PVEContainerVolume -VMId 200 -Device mp0 -Confirm:$false
    (Get-SingleBody PUT 'config$').delete | Should -Be 'mp0'
    $script:State.Guests['200'].config.unused0 | Should -Be 'local-lvm:vm-200-disk-1'
  }

  It 'Remove-PVEContainerVolume -DeletePermanently also deletes the unused entry' {
    Remove-PVEContainerVolume -VMId 200 -Device mp0 -DeletePermanently -Confirm:$false
    $bodies = @(Get-Request PUT 'config$' | ForEach-Object { ConvertFrom-Body $_.Body })
    $bodies.Count | Should -Be 2
    $bodies[0].delete | Should -Be 'mp0'
    $bodies[1].delete | Should -Be 'unused0'
    $bodies[1].digest | Should -Be '2'
    $script:State.Guests['200'].config.Contains('unused0') | Should -BeFalse
  }

  It 'Remove-PVEContainerVolume removes a bind mount with one request, even with -DeletePermanently' {
    Remove-PVEContainerVolume -VMId 200 -Device mp1 -DeletePermanently -Confirm:$false
    @(Get-Request PUT 'config$').Count | Should -Be 1
  }

  It 'Remove-PVEContainerVolume refuses rootfs' {
    $r = Invoke-Streams { Remove-PVEContainerVolume -VMId 200 -Device rootfs -Confirm:$false }
    $r.Errors[0].Exception.Message | Should -BeLike '*root file system and cannot be removed*'
    (Get-Request PUT '.*').Count | Should -Be 0
  }
}

Describe 'Container network adapters' {
  BeforeEach {
    Initialize-Hardware
  }

  It 'Get-PVEContainerNetworkAdapter reads the interface, bridge, MAC and addresses' {
    $nic = Get-PVEContainerNetworkAdapter -VMId 200
    $nic.InterfaceName | Should -Be 'eth0'
    $nic.Bridge | Should -Be 'vmbr0'
    $nic.MacAddress | Should -Be 'BC:24:11:00:02:00'
    $nic.IPAddress | Should -Be 'dhcp'
    $nic.Connected | Should -BeTrue
  }

  It 'New-PVEContainerNetworkAdapter names the interface after its index and defaults to DHCP' {
    $nic = New-PVEContainerNetworkAdapter -VMId 200 -Bridge vmbr1 -VlanTag 5
    (Get-SingleBody PUT 'config$').net1 | Should -Be 'name=eth1,bridge=vmbr1,ip=dhcp,tag=5'
    $nic.InterfaceName | Should -Be 'eth1'
  }

  It 'New-PVEContainerNetworkAdapter takes static addresses and an interface name' {
    $null = New-PVEContainerNetworkAdapter -VMId 200 -Bridge vmbr1 -InterfaceName lan0 -IPAddress 198.51.100.5/24 -Gateway 198.51.100.1 -IPv6Address auto
    (Get-SingleBody PUT 'config$').net1 | Should -Be 'name=lan0,bridge=vmbr1,ip=198.51.100.5/24,gw=198.51.100.1,ip6=auto'
  }

  It 'Set-PVEContainerNetworkAdapter changes addresses and removes ones given as empty' {
    $null = Set-PVEContainerNetworkAdapter -VMId 200 -Device net0 -IPAddress 192.0.2.20/24 -Gateway 192.0.2.1 -IPv6Address '' -Connected $false
    (Get-SingleBody PUT 'config$').net0 | Should -Be 'name=eth0,bridge=vmbr0,hwaddr=BC:24:11:00:02:00,ip=192.0.2.20/24,type=veth,gw=192.0.2.1,link_down=1'
  }

  It 'Remove-PVEContainerNetworkAdapter deletes the entry' {
    Remove-PVEContainerNetworkAdapter -VMId 200 -Device net0 -Confirm:$false
    (Get-SingleBody PUT 'config$').delete | Should -Be 'net0'
  }

  It 'refuses a VM ID with a hint to use the VM cmdlets' {
    $r = Invoke-Streams { Get-PVEContainerNetworkAdapter -VMId 100 }
    $r.Errors[0].Exception.Message | Should -BeLike '*use the `*-PVEVM cmdlets*'
  }
}
