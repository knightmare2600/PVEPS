# PVEPS

PowerShell module for managing Proxmox VE through its REST API, in the style of VMware PowerCLI.

Originally written by Einar Stenberg (2018). Version 2 is a rewrite for PowerShell 7 and Proxmox VE 9.x,
and is a clean break from the v1 cmdlets.

> **Status:** work in progress. Phase 0 (connection, authentication, request handling, tasks),
> Phase 1 (inventory) and Phase 2 (power) are in place. Lifecycle, hardware, snapshot, guest-agent, storage/backup and
> statistics cmdlets follow in later phases. Clustered PVE is not yet supported; development and testing
> target a standalone node.

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
| `Invoke-PVEApi` | Call any API endpoint directly, for anything not yet wrapped |

Power cmdlets take names (wildcards allowed), `-VMId`, or piped objects. They wait for the PVE task to
finish and write the guest with its live status; `-RunAsync` returns the tasks instead. A guest already
in the requested state is skipped with a warning. Every stop, shutdown, reset, reboot and suspend asks
for confirmation unless `-Confirm:$false` is given, and every power cmdlet honours `-WhatIf`.

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
Invoke-PVEApi -Path /cluster/resources -Parameters @{ type = 'vm' }
Invoke-PVEApi -Method POST -Path /nodes/pve01/qemu/9001/status/start -WhatIf
```

## Tests

```powershell
# Unit tests: offline, the HTTP layer is mocked.
Invoke-Pester ./tests -ExcludeTagFilter Integration

# Integration tests: read-only, run against a real server.
$env:PVEPS_TEST_SERVER = 'pve01.example.com'
$env:PVEPS_TEST_TOKEN_ID = 'pveps@pve!readonly'
$env:PVEPS_TEST_TOKEN_SECRET = '...'
$env:PVEPS_TEST_SKIPCERT = '1'
Invoke-Pester ./tests -TagFilter Integration -ExcludeTagFilter Power -Output Detailed
```

The header of `tests/Integration/Connection.Integration.Tests.ps1` lists every variable it reads.

### Power tests

The power tests change the power state of one dedicated test VM (and optionally one container). They
need a separate token that has rights only on a dedicated pool, so PVE refuses anything outside it, and
the tests themselves refuse any guest not in that pool or not named `pveps-test*`. On the node, as root
(choose a free VMID):

```
pveum pool add pveps-test --comment "PVEPS integration tests"
qm create 9990 --name pveps-test-vm --memory 512 --cores 1 --pool pveps-test
pveum acl modify /pool/pveps-test --users pveps@pve --roles PVEVMUser
pveum user token add pveps@pve power --privsep 1
pveum acl modify /pool/pveps-test --tokens 'pveps@pve!power' --roles PVEVMUser
```

The VM has no disk or OS, which is enough for start, stop, reset, suspend and resume. Clean shutdown
and reboot need a guest OS; set `PVEPS_TEST_POWER_GUESTOS=1` if the test VM has one.

```powershell
$env:PVEPS_TEST_POWER_TOKEN_ID = 'pveps@pve!power'
$env:PVEPS_TEST_POWER_TOKEN_SECRET = Read-Host 'Power token secret' -MaskInput
$env:PVEPS_TEST_POOL = 'pveps-test'
$env:PVEPS_TEST_POWER_VMID = '9990'
Invoke-Pester ./tests/Integration/Power.Integration.Tests.ps1 -Output Detailed
```

## Licence

GPLv3. See [LICENSE](LICENSE).
