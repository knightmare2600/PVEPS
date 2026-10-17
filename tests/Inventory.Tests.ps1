#Requires -Modules Pester
# Phase 1 inventory cmdlets. HTTP is mocked (see TestHelpers.ps1); nothing here touches a real server.

BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

  # Called from each Describe's BeforeEach (Pester 6 does not allow BeforeEach at file root).
  function Initialize-Inventory {
    Reset-FakeState
    Set-FakeResource
    $script:Fake.Handler = $script:InventoryHandler
    $null = Connect-PVE -Server pve -User root@pam -Password 'x'
    $script:Fake.Calls.Clear()
  }

  # A standalone node "pve" with VMs, a VM template, containers, a container template, storage and pools.
  # Reset before every test because some tests replace the guest list.
  function Set-FakeResource {
    $script:Resources = @(
      @{ type = 'qemu'; vmid = 101; name = 'db01'; node = 'pve'; status = 'stopped'; template = 0; maxcpu = 4; maxmem = 8589934592; mem = 0; maxdisk = 68719476736; disk = 0; uptime = 0; tags = 'prod' }
      @{ type = 'qemu'; vmid = 100; name = 'web01'; node = 'pve'; status = 'running'; template = 0; maxcpu = 2; maxmem = 4294967296; mem = 1073741824; maxdisk = 34359738368; disk = 0; cpu = 0.125; uptime = 90061; tags = 'prod;web'; pool = 'lab' }
      @{ type = 'qemu'; vmid = 9000; name = 'tmpl-debian'; node = 'pve'; status = 'stopped'; template = 1; maxcpu = 1; maxmem = 1073741824 }
      @{ type = 'lxc'; vmid = 200; name = 'dns01'; node = 'pve'; status = 'running'; template = 0; maxcpu = 1; maxmem = 536870912; mem = 52428800; maxdisk = 8589934592; disk = 1073741824; uptime = 3600 }
      @{ type = 'lxc'; vmid = 9001; name = 'tmpl-alpine'; node = 'pve'; status = 'stopped'; template = 1 }
    )
  }

  $script:InventoryHandler = {
    param($Method, $Path, $Call)
    switch -Regex ($Path) {
      '^/access/ticket$' { return New-FakeResponse -Data @{ ticket = 'PVE:root@pam:AAAA::sig'; CSRFPreventionToken = 'AAAA:csrf'; username = 'root@pam' } }
      '^/version$' { return New-FakeResponse -Data @{ version = '9.2.1'; release = '9.2' } }
      '^/cluster/resources$' { return New-FakeResponse -Data $script:Resources }
      '^/nodes$' {
        return New-FakeResponse -Data @(
          @{ node = 'pve'; status = 'online'; maxcpu = 16; cpu = 0.0512; mem = 17179869184; maxmem = 68719476736; uptime = 1209600; ssl_fingerprint = 'AA:BB' }
          @{ node = 'pve-old'; status = 'offline' }
        )
      }
      '^/nodes/pve/status$' {
        return New-FakeResponse -Data @{ pveversion = 'pve-manager/9.2.1/abcdef'; cpuinfo = @{ model = 'AMD EPYC 7302P'; cpus = 16 }; 'current-kernel' = @{ release = '6.14.8-2-pve' } }
      }
      '^/nodes/pve/storage$' {
        return New-FakeResponse -Data @(
          @{ storage = 'local-lvm'; type = 'lvmthin'; content = 'rootdir,images'; enabled = 1; active = 1; shared = 0; total = 107374182400; used = 26843545600; avail = 80530636800; used_fraction = 0.25 }
          @{ storage = 'local'; type = 'dir'; content = 'iso,vztmpl,backup'; enabled = 1; active = 1; shared = 0; total = 53687091200; used = 10737418240; avail = 42949672960; used_fraction = 0.2 }
          @{ storage = 'usb-backup'; type = 'dir'; content = 'backup'; enabled = 1; active = 0; shared = 0 }
        )
      }
      '^/pools$' {
        if ($Call.Query -match 'poolid=lab') {
          return New-FakeResponse -Data @(@{ poolid = 'lab'; comment = 'Test lab'; members = @(
                @{ type = 'qemu'; id = 'qemu/100'; vmid = 100; name = 'web01'; node = 'pve'; status = 'running' }
                @{ type = 'storage'; id = 'storage/pve/local'; storage = 'local'; node = 'pve' }
              ) })
        }
        if ($Call.Query -match 'poolid=empty') {
          return New-FakeResponse -Data @(@{ poolid = 'empty' })
        }
        return New-FakeResponse -Data @(@{ poolid = 'lab' }, @{ poolid = 'empty' })
      }
    }
    New-FakeResponse -Status 501 -Reason "Unexpected path $Path in test" -Data $null
  }

  function Invoke-Streams {
    # Runs a script block and splits its output and error streams.
    param([scriptblock]$ScriptBlock)
    $all = @(& $ScriptBlock 2>&1)
    [pscustomobject]@{
      Output = @($all | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
      Errors = @($all | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    }
  }
}

Describe 'Get-PVEVM' {
  BeforeEach {
    Initialize-Inventory
  }

  It 'reads all guests in a single /cluster/resources call' {
    $null = Get-PVEVM
    $script:Fake.Calls.Count | Should -Be 1
    $script:Fake.Calls[0].Path | Should -Be '/cluster/resources'
    $script:Fake.Calls[0].Query | Should -Be 'type=vm'
  }

  It 'returns QEMU VMs only, without templates, sorted by VMId' {
    $vms = @(Get-PVEVM)
    $vms.VMId | Should -Be @(100, 101)
    $vms | ForEach-Object { $_.PSObject.TypeNames | Should -Contain 'PVEPS.VM' }
  }

  It 'maps the resource fields' {
    $vm = Get-PVEVM -VMId 100
    $vm.Name | Should -Be 'web01'
    $vm.Node | Should -Be 'pve'
    $vm.Status | Should -Be 'running'
    $vm.Cpus | Should -Be 2
    $vm.MemoryGB | Should -Be 4
    $vm.MemoryUsedGB | Should -Be 1
    $vm.DiskGB | Should -Be 32
    $vm.CpuUsagePercent | Should -Be 12.5
    $vm.Uptime | Should -Be ([timespan]::FromSeconds(90061))
    $vm.Tags | Should -Be @('prod', 'web')
    $vm.Pool | Should -Be 'lab'
    $vm.IsTemplate | Should -BeFalse
    $vm.Type | Should -Be 'qemu'
    $vm.Connection.Server | Should -Be 'pve'
  }

  It 'includes templates with -IncludeTemplate' {
    (Get-PVEVM -IncludeTemplate).VMId | Should -Be @(100, 101, 9000)
    (Get-PVEVM -VMId 9000 -IncludeTemplate).IsTemplate | Should -BeTrue
  }

  It 'filters by name with wildcards' {
    (Get-PVEVM -Name 'web*').VMId | Should -Be 100
    (Get-PVEVM -Name 'web01', 'db01').VMId | Should -Be @(100, 101)
  }

  It 'writes not-found for an exact name, but not for an unmatched wildcard' {
    $r = Invoke-Streams { Get-PVEVM -Name 'nosuchvm', 'zz*' }
    $r.Output.Count | Should -Be 0
    $r.Errors.Count | Should -Be 1
    $r.Errors[0].Exception.Message | Should -Be "VM with name 'nosuchvm' was not found on pve."
    $r.Errors[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
  }

  It 'hints at -IncludeTemplate when the name or ID is a template' {
    $r = Invoke-Streams { Get-PVEVM -Name 'tmpl-debian' }
    $r.Errors[0].Exception.Message | Should -BeLike '*It is a template; add -IncludeTemplate.'
    $r = Invoke-Streams { Get-PVEVM -VMId 9000 }
    $r.Errors[0].Exception.Message | Should -BeLike "VM with ID '9000' was not found*add -IncludeTemplate."
  }

  It 'returns the found VMs and reports only the missing IDs' {
    $r = Invoke-Streams { Get-PVEVM -VMId 100, 555 }
    $r.Output.VMId | Should -Be 100
    $r.Errors.Count | Should -Be 1
    $r.Errors[0].Exception.Message | Should -Be "VM with ID '555' was not found on pve."
  }

  It 'does not treat a container ID as a VM' {
    $r = Invoke-Streams { Get-PVEVM -VMId 200 }
    $r.Output.Count | Should -Be 0
    $r.Errors.Count | Should -Be 1
  }

  It 'rejects VM IDs outside 100-999999999' {
    { Get-PVEVM -VMId 99 } | Should -Throw
  }

  It 'filters by node' {
    @(Get-PVEVM -Node 'pve').Count | Should -Be 2
    @(Get-PVEVM -Node 'other').Count | Should -Be 0
  }

  It 'reports not-found cleanly when the server has no guests at all (strict mode)' {
    $script:Resources = @()
    $r = Invoke-Streams { Get-PVEVM -Name 'web01' }
    $r.Errors.Count | Should -Be 1
    $r.Errors[0].FullyQualifiedErrorId | Should -Be 'PVEObjectNotFound,Get-PVEVM'
  }

  It 'copes with a sparse resource entry (strict mode)' {
    $script:Resources = @(@{ type = 'qemu'; vmid = 300; node = 'pve'; status = 'stopped' })
    $vm = Get-PVEVM
    $vm.VMId | Should -Be 300
    $vm.Name | Should -Be ''
    $vm.MemoryGB | Should -BeNullOrEmpty
    $vm.Uptime | Should -BeNullOrEmpty
    $vm.Tags.Count | Should -Be 0
    $vm.IsTemplate | Should -BeFalse
  }

  It 'accepts piped node objects' {
    $vms = @(Get-PVENode -Name pve | Get-PVEVM)
    $vms.VMId | Should -Be @(100, 101)
  }

  It 'accepts piped VM objects, binding VMId, Node and the connection' {
    $vm = Get-PVEVM -VMId 101 | Get-PVEVM
    $vm.VMId | Should -Be 101
  }
}

Describe 'Get-PVEContainer' {
  BeforeEach {
    Initialize-Inventory
  }

  It 'returns LXC containers only, without templates' {
    $cts = @(Get-PVEContainer)
    $cts.VMId | Should -Be 200
    $cts[0].PSObject.TypeNames | Should -Contain 'PVEPS.Container'
    $cts[0].Type | Should -Be 'lxc'
    $cts[0].DiskUsedGB | Should -Be 1
    $cts[0].MemoryGB | Should -Be 0.5
  }

  It 'includes container templates with -IncludeTemplate' {
    (Get-PVEContainer -IncludeTemplate).VMId | Should -Be @(200, 9001)
  }

  It 'does not treat a VM ID as a container, and hints for templates' {
    (Invoke-Streams { Get-PVEContainer -VMId 100 }).Errors[0].Exception.Message | Should -Be "Container with ID '100' was not found on pve."
    (Invoke-Streams { Get-PVEContainer -Name 'tmpl-alpine' }).Errors[0].Exception.Message | Should -BeLike '*add -IncludeTemplate.'
  }
}

Describe 'Get-PVENode' {
  BeforeEach {
    Initialize-Inventory
  }

  It 'merges /nodes with the node status for online nodes' {
    $node = Get-PVENode -Name pve
    $node.Name | Should -Be 'pve'
    $node.Node | Should -Be 'pve' -Because 'Node is an alias of Name, for pipeline binding'
    $node.Status | Should -Be 'online'
    $node.Cpus | Should -Be 16
    $node.CpuUsagePercent | Should -Be 5.1
    $node.MemoryUsedGB | Should -Be 16
    $node.MemoryTotalGB | Should -Be 64
    $node.Uptime.TotalDays | Should -Be 14
    $node.Version | Should -Be 'pve-manager/9.2.1/abcdef'
    $node.Kernel | Should -Be '6.14.8-2-pve'
    $node.CpuModel | Should -Be 'AMD EPYC 7302P'
    $node.PSObject.TypeNames | Should -Contain 'PVEPS.Node'
  }

  It 'does not query status for an offline node, and leaves its details empty' {
    $nodes = @(Get-PVENode)
    $nodes.Name | Should -Be @('pve', 'pve-old')
    $script:Fake.Calls.Path | Should -Not -Contain '/nodes/pve-old/status'
    $nodes[1].Version | Should -BeNullOrEmpty
    $nodes[1].Uptime | Should -BeNullOrEmpty
  }

  It 'writes not-found for an unknown node name' {
    $r = Invoke-Streams { Get-PVENode -Name 'nope' }
    $r.Errors[0].Exception.Message | Should -Be "Node 'nope' was not found on pve."
  }
}

Describe 'Get-PVEStorage' {
  BeforeEach {
    Initialize-Inventory
  }

  It 'reads storage per online node only, sorted by name' {
    $storage = @(Get-PVEStorage)
    $script:Fake.Calls.Path | Should -Contain '/nodes/pve/storage'
    $script:Fake.Calls.Path | Should -Not -Contain '/nodes/pve-old/storage'
    $storage.Name | Should -Be @('local', 'local-lvm', 'usb-backup')
  }

  It 'maps capacity and content' {
    $lvm = Get-PVEStorage -Name local-lvm
    $lvm.Node | Should -Be 'pve'
    $lvm.Type | Should -Be 'lvmthin'
    $lvm.Content | Should -Be @('images', 'rootdir')
    $lvm.Active | Should -BeTrue
    $lvm.Shared | Should -BeFalse
    $lvm.CapacityGB | Should -Be 100
    $lvm.UsedGB | Should -Be 25
    $lvm.FreeGB | Should -Be 75
    $lvm.UsedPercent | Should -Be 25
  }

  It 'leaves capacity empty for inactive storage' {
    $usb = Get-PVEStorage -Name usb-backup
    $usb.Active | Should -BeFalse
    $usb.CapacityGB | Should -BeNullOrEmpty
    $usb.UsedPercent | Should -BeNullOrEmpty
  }

  It 'passes -Content to the API' {
    $null = Get-PVEStorage -Content iso
    ($script:Fake.Calls | Where-Object Path -EQ '/nodes/pve/storage').Query | Should -Be 'content=iso'
  }

  It 'writes not-found for an unknown storage name' {
    $r = Invoke-Streams { Get-PVEStorage -Name 'ceph-pool' }
    $r.Errors[0].Exception.Message | Should -Be "Storage 'ceph-pool' was not found on pve."
  }

  It 'accepts piped node objects' {
    @(Get-PVENode -Name pve | Get-PVEStorage).Count | Should -Be 3
  }
}

Describe 'Get-PVEPool' {
  BeforeEach {
    Initialize-Inventory
  }

  It 'lists pools and reads members with the poolid query (not the deprecated path)' {
    $pools = @(Get-PVEPool)
    $pools.Name | Should -Be @('empty', 'lab')
    $script:Fake.Calls.Path | Should -Not -Contain '/pools/lab'
    ($script:Fake.Calls | Where-Object Query -EQ 'poolid=lab').Count | Should -Be 1
  }

  It 'maps members' {
    $lab = Get-PVEPool -Name lab
    $lab.Comment | Should -Be 'Test lab'
    $lab.Members.Count | Should -Be 2
    $vm = $lab.Members | Where-Object Type -EQ 'qemu'
    $vm.VMId | Should -Be 100
    $vm.Name | Should -Be 'web01'
    "$vm" | Should -Be 'qemu/100 (web01)'
    ($lab.Members | Where-Object Type -EQ 'storage').Storage | Should -Be 'local'
    "$($lab.Members | Where-Object Type -EQ 'storage')" | Should -Be 'storage/pve/local'
  }

  It 'returns an empty member list for a pool without members' {
    $empty = Get-PVEPool -Name empty
    @($empty.Members).Count | Should -Be 0
  }

  It 'writes not-found for an unknown pool' {
    $r = Invoke-Streams { Get-PVEPool -Name 'prod' }
    $r.Errors[0].Exception.Message | Should -Be "Pool 'prod' was not found on pve."
  }
}
