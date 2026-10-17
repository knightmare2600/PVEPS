# PVEPS

PowerShell module for managing Proxmox VE through its REST API, in the style of VMware PowerCLI.

Originally written by Einar Stenberg (2018). Version 2 is a rewrite for PowerShell 7 and Proxmox VE 9.x,
and is a clean break from the v1 cmdlets.

> **Status:** work in progress. Phase 0 (connection, authentication, request handling, tasks),
> Phase 1 (inventory), Phase 2 (power), Phase 3 (lifecycle), Phase 4 (hardware), Phase 5 (snapshots)
> and Phase 6 (guest agent and console) are in place. Storage/backup and statistics cmdlets follow. Clustered PVE is not yet
> supported; development and testing target a standalone node.

## Requirements

- PowerShell 7.4 or later, on Linux, macOS or Windows
- Proxmox VE 9.x

## Getting started

```powershell
Import-Module ./PVEPS.psd1

# Username and password (the default). The realm is required. Omit -Password to be prompted.
Connect-PVE -Server pve01.example.com -User root@pam
Connect-PVE -Server pve01.example.com -User root@pam -Password 'secret'

# API token: add -Token. The user is the full token ID, the password is the token secret.
Connect-PVE -Server 192.0.2.10 -User 'automation@pve!pveps' -Token -SkipCertificateCheck

# A PSCredential works for either.
Connect-PVE -Server pve01.example.com -Credential (Get-Credential root@pam)
Connect-PVE -Server pve01.example.com -Credential $tokenCredential -Token
```

`-Password` accepts a plain string or a SecureString. A plain string typed at the prompt can end up in
shell history, so in interactive use leave `-Password` out and type it at the hidden prompt.

`-SkipCertificateCheck` applies only to that connection. It is needed for the self-signed certificate
that a fresh PVE install uses.

With ticket authentication, the module renews the ticket automatically before its two-hour lifetime
runs out. Users with two-factor authentication enabled must use an API token.

## Cmdlets

| Cmdlet | Purpose |
|---|---|
| `Connect-PVE` | Open a connection; the newest becomes the default unless `-NotDefault` is given |
| `Disconnect-PVE` | Close a connection (`-Server *` closes them all) |
| `Get-PVEConnection` | List open connections |
| `Get-PVETask` | Recent cluster tasks, a node's task list, or one task by UPID |
| `Wait-PVETask` | Wait for tasks to finish; failed tasks become errors |
| `Get-PVENode` | Nodes, with PVE version, kernel and CPU model |
| `Get-PVEVM` | QEMU VMs by name (wildcards), ID or node; templates only with `-IncludeTemplate` |
| `Get-PVEContainer` | LXC containers, with the same filters as `Get-PVEVM` |
| `Get-PVEStorage` | Storage per node, with capacity; filter by name or `-Content` |
| `Get-PVEPool` | Resource pools and their members |
| `Start-PVEVM` / `Start-PVEContainer` | Power on |
| `Stop-PVEVMGuest` / `Stop-PVEContainerGuest` | Clean shutdown of the guest OS |
| `Stop-PVEVM` / `Stop-PVEContainer` | Hard stop (power off) |
| `Restart-PVEVMGuest` / `Restart-PVEContainer` | Clean reboot |
| `Restart-PVEVM` | Hard reset |
| `Suspend-PVEVM` / `Resume-PVEVM` | Pause and resume; `Suspend-PVEVM -ToDisk` hibernates |
| `New-PVEVM` / `New-PVEContainer` | Create a VM (disks, NICs, ISO, UEFI) or a container from an OS template |
| `Set-PVEVM` / `Set-PVEContainer` | Change CPU, memory, name, tags, description, start-on-boot, protection, or any option by API name |
| `Copy-PVEVM` / `Copy-PVEContainer` | Clone a guest or template (linked or `-Full`) |
| `ConvertTo-PVEVMTemplate` / `ConvertTo-PVEContainerTemplate` | Turn a stopped guest into a template |
| `Move-PVEVM` / `Move-PVEContainer` | Move a guest's disks or volumes to another storage |
| `Remove-PVEVM` / `Remove-PVEContainer` | Delete a stopped guest and its disks |
| `Get/New/Set/Remove-PVEVMHardDisk` | List, add, grow or re-option, and detach or delete VM disks |
| `Get/New/Set/Remove-PVEVMNetworkAdapter` | VM network adapters: bridge, model, MAC, VLAN, link state |
| `Get/New/Set/Remove-PVEVMCDDrive` | VM CD drives; insert or eject ISOs |
| `Get-PVEVMCloudInit` / `Set-PVEVMCloudInit` | cloud-init user, SSH keys, IP and DNS settings; adds the drive |
| `Get/New/Set/Remove-PVEContainerVolume` | Container root file system and mount points (volumes or bind mounts) |
| `Get/New/Set/Remove-PVEContainerNetworkAdapter` | Container network adapters and their addresses |
| `Get/New/Set/Remove/Restore-PVEVMSnapshot` | VM snapshots (optionally with RAM); roll back |
| `Get/New/Set/Remove/Restore-PVEContainerSnapshot` | Container snapshots; roll back |
| `Get-PVEVMGuest` | OS, host name and IP addresses reported by the QEMU guest agent |
| `Invoke-PVEVMScript` | Run a command or script inside a VM through the guest agent |
| `Copy-PVEVMGuestFile` | Copy a file into (up to 45 KiB) or out of a VM through the guest agent |
| `Open-PVEVMConsole` / `Open-PVEContainerConsole` | Open the noVNC console in the browser, or `-UrlOnly` |
| `Invoke-PVEApi` | Call any API endpoint directly, for anything not yet wrapped |

Power cmdlets take names (wildcards allowed), `-VMId`, or piped objects. They wait for the PVE task to
finish and write the guest with its live status; `-RunAsync` returns the tasks instead. A guest already
in the requested state is skipped with a warning. Every stop, shutdown, reset, reboot and suspend asks
for confirmation unless `-Confirm:$false` is given, and every power cmdlet honours `-WhatIf`.

Lifecycle cmdlets work the same way. New guests get the next free ID unless `-VMId` is given, and land
on the server's only node unless `-Node` is given. Remove and convert-to-template refuse a guest that is
not stopped, and ask for confirmation; set, clone and move do not, but honour `-WhatIf`. A name or
wildcard matches templates only with `-IncludeTemplate`, so `Remove-PVEVM 'test*'` cannot delete a
template by accident; an ID always does what it says. `Set-*` warns when a running guest has changes
that PVE will only apply at the next start.

Hardware cmdlets take a guest (`-VMId`, `-VMName`, or piped guest objects) and, to change or remove
something, a `-Device` such as `scsi1`, `net0` or `mp0`; objects from the `Get-` cmdlets pipe straight
in. Each change rewrites only the options named and sends the digest of the configuration it was built
from, so PVE refuses it if the configuration changed in between. Removing a disk or mount point detaches
it by default, keeping the volume as an unused disk; `-DeletePermanently` deletes it.

Every cmdlet takes `-Server` (a connection object or a server name) and defaults to the default
connection. Objects carry the connection they came from, so pipelines work across servers.

As with PowerCLI, asking for a specific name or ID that does not exist writes a "not found" error, while
a wildcard that matches nothing returns nothing quietly.

```powershell
Get-PVEVM -Name 'web*'
Get-PVENode pve01 | Get-PVEContainer
Get-PVEStorage -Content iso
Get-PVEVM -Name 'test*' | Stop-PVEVMGuest -TimeoutSec 120 -ForceStop -Confirm:$false
Start-PVEVM -VMId 100, 101 -RunAsync | Wait-PVETask
Get-PVETask -Node pve01 -Source all -Limit 10
New-PVEVM web01 -Cores 2 -MemoryGB 4 -DiskGB 32 -Storage local-lvm -NetworkBridge vmbr0 -OSType l26 -PowerOn
Copy-PVEVM tmpl-debian13 -NewName web02 | Start-PVEVM
Get-PVEVM 'web*' | Set-PVEVM -Tags web, production -StartOnBoot $true
Move-PVEVM web01 -Storage fast-ssd -DeleteSource
Get-PVEVM db01 | New-PVEVMHardDisk -SizeGB 200 -Storage local-lvm -SSD -Discard
Set-PVEVMHardDisk -VMId 100 -Device scsi0 -SizeGB 64
Set-PVEVMCloudInit -VMId 100 -User debian -SshPublicKey (Get-Content ~/.ssh/id_ed25519.pub) -IPAddress dhcp -Storage local-lvm
Get-PVEVM 'web*' | New-PVEVMSnapshot -Snapshot before-upgrade
Restore-PVEVMSnapshot -VMId 100 -Snapshot before-upgrade -Confirm:$false
Get-PVEVM 'web*' | Invoke-PVEVMScript -ScriptText 'systemctl is-active nginx' | Select-Object VMName, ExitCode, StdOut
Get-PVEVM 'scratch-*' | Stop-PVEVM -Confirm:$false | Remove-PVEVM -Purge -Confirm:$false
Invoke-PVEApi -Path /cluster/resources -Parameters @{ type = 'vm' }
Invoke-PVEApi -Method POST -Path /nodes/pve01/qemu/9001/status/start -WhatIf
```

## Tests

```powershell
# Unit tests: offline, the HTTP layer is mocked.
Invoke-Pester ./tests -ExcludeTagFilter Integration

# Integration tests: read-only, run against a real server (token setup below).
$env:PVEPS_TEST_SERVER = 'pve01.example.com'
$env:PVEPS_TEST_TOKEN_ID = 'pveps@pve!readonly'
$env:PVEPS_TEST_TOKEN_SECRET = '...'
$env:PVEPS_TEST_SKIPCERT = '1'
Invoke-Pester ./tests -TagFilter Integration -ExcludeTagFilter Power, Lifecycle, Hardware, Snapshot, Agent -Output Detailed
```

The read-only tests need a token with audit rights. With privilege separation a token gets the
intersection of its own and its user's rights, so both get the role. On the node, as root:

```
pveum user add pveps@pve --comment "PVEPS integration tests"
pveum user token add pveps@pve readonly --privsep 1
pveum acl modify / --users pveps@pve --tokens 'pveps@pve!readonly' --roles PVEAuditor
```

The header of `tests/Integration/Connection.Integration.Tests.ps1` lists every variable it reads.

### Write tests

The power, lifecycle, hardware and snapshot tests change state, so they use a separate token whose
rights cover only a dedicated pool and the storage the tests use; PVE refuses anything else. These
commands add to the `pveps@pve` user created above. The tests also refuse any guest not in that pool or
not named `pveps-test*`. The lifecycle, hardware and snapshot tests create every guest they touch and
delete them again at the end. On the node, as root:

```
pveum pool add pveps-test --comment "PVEPS integration tests"
pveum user token add pveps@pve write --privsep 1
pveum acl modify /pool/pveps-test --users pveps@pve --tokens 'pveps@pve!write' --roles PVEVMAdmin
pveum acl modify /storage/local-lvm --users pveps@pve --tokens 'pveps@pve!write' --roles PVEDatastoreUser
```

Replace `local-lvm` with the test storage, and repeat that line for the second storage (Move tests) and
for the storage holding the container template (container tests). For `PVEPS_TEST_BRIDGE`, the token also
needs `SDN.Use` on the bridge; on PVE 8 and later, plain bridges sit in the `localnetwork` zone, so
`pveum acl modify /sdn/zones/localnetwork --users pveps@pve --tokens 'pveps@pve!write' --roles PVESDNUser`
grants it (unverified on 9.2; the create test fails with a permission error if not).

The power tests also need one test VM in the pool (choose a free VMID). It has no disk or OS, which is
enough for start, stop, reset, suspend and resume. Clean shutdown and reboot need a guest OS; set
`PVEPS_TEST_POWER_GUESTOS=1` if the test VM has one.

```
qm create 9990 --name pveps-test-vm --memory 512 --cores 1 --pool pveps-test
```

```powershell
$env:PVEPS_TEST_WRITE_TOKEN_ID = 'pveps@pve!write'
$env:PVEPS_TEST_WRITE_TOKEN_SECRET = Read-Host 'Write token secret' -MaskInput
$env:PVEPS_TEST_POOL = 'pveps-test'
$env:PVEPS_TEST_POWER_VMID = '9990'
$env:PVEPS_TEST_STORAGE = 'local-lvm'
# Optional: $env:PVEPS_TEST_STORAGE2, $env:PVEPS_TEST_BRIDGE, $env:PVEPS_TEST_CT_TEMPLATE, $env:PVEPS_TEST_ISO
Invoke-Pester ./tests/Integration/Power.Integration.Tests.ps1 -Output Detailed
Invoke-Pester ./tests/Integration/Lifecycle.Integration.Tests.ps1 -Output Detailed
Invoke-Pester ./tests/Integration/Hardware.Integration.Tests.ps1 -Output Detailed
Invoke-Pester ./tests/Integration/Snapshot.Integration.Tests.ps1 -Output Detailed
# Needs PVEPS_TEST_AGENT_VMID: a running pveps-test* VM in the pool with the guest agent installed.
Invoke-Pester ./tests/Integration/Agent.Integration.Tests.ps1 -Output Detailed
```

The header of each test file lists every variable it reads.

## Licence

GPLv3. See [LICENSE](LICENSE).
