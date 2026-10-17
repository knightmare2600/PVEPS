# PVEPS

PowerShell module for managing Proxmox VE through its REST API, in the style of VMware PowerCLI.

**Version 1.0.1** · **Licence: GPL-3.0** · **PowerShell 7.4 or later** · **Proxmox VE 9.x**

PVEPS was originally written by Einar Stenberg (2018). Version 1.0.1 is a complete rewrite for
PowerShell 7 and Proxmox VE 9.x by Robert McLay, and is a clean break from the original cmdlets. It has
86 cmdlets covering connections and tasks, inventory, power, lifecycle, hardware, snapshots, the QEMU
guest agent and console, storage and backups, and statistics and events. Anything not yet wrapped can be
reached through `Invoke-PVEApi`.

```powershell
Connect-PVE -Server pve01.example.com -User root@pam
Get-PVEVM -Name 'web*' | Stop-PVEVMGuest -TimeoutSec 120
Get-PVEVM web01 | New-PVEVMSnapshot -Snapshot before-upgrade
Get-PVEVM web01 | Get-PVEVMHardDisk
```

## Contents

- [Status and testing](#status-and-testing)
- [Requirements](#requirements)
- [Installation](#installation)
- [Getting started](#getting-started)
- [How the cmdlets work](#how-the-cmdlets-work)
- [Common tasks](#common-tasks)
- [Cmdlet index](#cmdlet-index)
- [Cmdlet reference](#cmdlet-reference)
- [Tests](#tests)
- [Building, packaging and publishing](#building-packaging-and-publishing)
- [Scope and limitations](#scope-and-limitations)
- [Version history](#version-history)
- [Credits and licence](#credits-and-licence)

## Status and testing

- **Windows and Linux:** tested, with PowerShell 7 against a Proxmox VE 9.2.21 node.
- **macOS:** not yet tested. The module has no platform-specific code apart from `Open-PVEVMConsole` and
  `Open-PVEContainerConsole`, which hand the console URL to the default browser through `Start-Process`
  (`-UrlOnly` avoids that).
- **Unit tests:** every cmdlet has Pester unit tests against a mocked HTTP layer; they run offline on any
  platform. See [Tests](#tests).
- **Integration tests:** read-only and write suites run against a real server, with the write suites
  confined to a dedicated resource pool and token. See [Tests](#tests).

## Requirements

| Requirement | Details |
|---|---|
| PowerShell | 7.4 or later (PowerShell Core edition only; Windows PowerShell 5.1 is not supported) |
| Operating system | Windows or Linux (tested); macOS (not yet tested) |
| Proxmox VE | 9.x (tested against 9.2.21); a standalone node. Clusters are not yet supported |
| Network | HTTPS to the PVE API, port 8006 by default |
| PVE account | A user (`user@realm`) with a password, or an API token, with the privileges for what you do (see [Permissions](#permissions)) |
| Pester 6 | Only to run the tests |
| Microsoft.PowerShell.PSResourceGet | Only to build or install the package (it ships with PowerShell 7.4 and later) |

## Installation

There are three ways to install PVEPS. They give the same module.

### 1. From the PowerShell Gallery

Once PVEPS is published to the PowerShell Gallery:

```powershell
Install-PSResource -Name PVEPS -Scope CurrentUser
# or, with the older PowerShellGet cmdlets:
Install-Module -Name PVEPS -Scope CurrentUser

Import-Module PVEPS

# Later:
Update-PSResource -Name PVEPS
Uninstall-PSResource -Name PVEPS
```

### 2. Build the package from a clone and install it

This installs into your PowerShell user module path, so `Import-Module PVEPS` works from any directory.
It needs no access to the PowerShell Gallery.

```powershell
git clone https://github.com/knightmare2600/PVEPS.git
cd PVEPS
pwsh ./build/Build-PVEPS.ps1 -Install
Import-Module PVEPS
```

The build also writes `out/PVEPS-1.0.1.zip` (a `PVEPS` folder) and `out/PVEPS.1.0.1.nupkg`, for copying
to other machines. Either unzip the zip into a folder listed in `$env:PSModulePath`, or install the
`.nupkg` from a local repository:

```powershell
Register-PSResourceRepository -Name PVEPSLocal -Uri /path/to/folder/with/nupkg -Trusted
Install-PSResource -Name PVEPS -Repository PVEPSLocal -Scope CurrentUser
```

### 3. Clone and import directly

```powershell
git clone https://github.com/knightmare2600/PVEPS.git
cd PVEPS
Import-Module ./PVEPS.psd1
```

Format and type data (how objects are displayed) load once per session, so after `git pull` start a new
`pwsh` session rather than relying on `Import-Module -Force`.

## Getting started

### Connecting

```powershell
# Username and password (the default). The realm is required. Omit -Password to be prompted.
Connect-PVE -Server pve01.example.com -User root@pam
Connect-PVE -Server pve01.example.com -User root@pam -Password 'secret'

# API token: add -Token. The user is the full token ID, the password is the token secret.
Connect-PVE -Server 192.0.2.10 -User 'automation@pve!pveps' -Token -SkipCertificateCheck

# A PSCredential works for either.
Connect-PVE -Server pve01.example.com -Credential (Get-Credential root@pam)
Connect-PVE -Server pve01.example.com -Credential $tokenCredential -Token

# A port other than 8006.
Connect-PVE -Server pve01.example.com -Port 443 -User root@pam

# What is connected, and closing connections.
Get-PVEConnection
Disconnect-PVE -Server pve01.example.com
Disconnect-PVE -Server * -Confirm:$false
```

`-Password` accepts a plain string or a SecureString. A plain string typed on the command line can end up
in shell history, so in interactive use leave `-Password` out and type it at the hidden prompt.

`-SkipCertificateCheck` applies only to that connection. It is needed for the self-signed certificate
that a fresh PVE install uses.

With ticket authentication, the module renews the ticket automatically before its two-hour lifetime
runs out. Users with two-factor authentication enabled must use an API token.

Connection objects never hold secrets: tickets, CSRF tokens and token secrets are kept inside the module,
so displaying, exporting or logging a connection cannot leak them.

### Permissions

PVE checks every request against the account's privileges, so PVEPS can do only what the user or token
is allowed to do. With privilege separation (`--privsep 1`, the default for new tokens), a token gets the
intersection of its own and its user's privileges, so grant the role to both. On the node, as root:

```
# Read-only: inventory, statistics, events, configuration.
pveum user add pveps@pve --comment "PVEPS"
pveum user token add pveps@pve readonly --privsep 1
pveum acl modify / --users pveps@pve --tokens 'pveps@pve!readonly' --roles PVEAuditor

# Managing guests in one pool, with disks on one storage.
pveum user token add pveps@pve admin --privsep 1
pveum acl modify /pool/<pool> --users pveps@pve --tokens 'pveps@pve!admin' --roles PVEVMAdmin
pveum acl modify /storage/<storage> --users pveps@pve --tokens 'pveps@pve!admin' --roles PVEDatastoreUser
```

The [write tests](#write-tests) section lists the further privileges for bridges, ISO and template
storage, and downloads by URL.

### A first session

```powershell
Get-PVENode | Format-List
Get-PVEStorage
Get-PVEVM
Get-PVEContainer
Get-PVEVM -VMId 100 | Get-PVEVMHardDisk
Get-PVETask | Select-Object -First 10
```

## How the cmdlets work

**Choosing guests.** Guest cmdlets take names (`-Name` or `-VMName`, wildcards allowed), IDs (`-VMId`),
or piped objects. Objects from `Get-PVEVM`, `Get-PVEContainer` and the device and snapshot cmdlets bind by
property name, so pipelines like `Get-PVEVM 'web*' | Get-PVEVMHardDisk | Set-PVEVMHardDisk -Cache none`
work without naming anything twice.

**Not found.** As with PowerCLI, asking for a specific name or ID that does not exist writes a "not found"
error, while a wildcard that matches nothing returns nothing quietly.

**Templates.** A name or wildcard matches templates only with `-IncludeTemplate`, so
`Remove-PVEVM 'test*'` cannot delete a template by accident. An ID always does what it says.

**Confirmation.** Every cmdlet that changes something supports `-WhatIf` and `-Confirm`. Those that stop,
reset, delete, roll back or overwrite ask for confirmation by default (ConfirmImpact High); add
`-Confirm:$false` in scripts. Each cmdlet's reference entry says which it is.

**Tasks.** PVE runs long operations as tasks. Cmdlets that start tasks wait for them and then write the
result (usually the guest with its live status). With `-RunAsync` they return the task objects at once;
`Wait-PVETask` waits for them later, and a failed task becomes an error. When several guests are given,
all the requests are sent first and then waited for together, so they run in parallel.

**Already in that state.** A power cmdlet given a guest that is already in the requested state (starting
a running VM, shutting down a stopped one) skips it with a warning and writes it unchanged, so pipelines
carry on.

**Configuration changes.** Hardware and settings cmdlets change only the options named. Each change sends
the digest of the configuration it was built from, so PVE refuses it if someone else changed the
configuration in between. `Set-*` warns when a running guest has changes that PVE applies only at the
next start.

**Devices.** Device cmdlets name devices as PVE does (`scsi0`, `net1`, `ide2`, `mp0`) through `-Device`.
Removing a disk or mount point detaches it by default, keeping the volume as an unused disk;
`-DeletePermanently` deletes it.

**Several servers.** Every cmdlet takes `-Server` (a connection object or a server name) and defaults to
the default connection: the newest one, unless it was opened with `-NotDefault`. Objects carry the
connection they came from, so pipelines work across servers.

**Output.** Cmdlets write typed objects (`PVEPS.VM`, `PVEPS.HardDisk`, `PVEPS.Task` and so on, listed in
each reference entry) with a compact table view. `Format-List` or `Select-Object *` shows every property.
Sizes are in GiB (`*GB` properties, as in PowerCLI), times are local `DateTime` values and durations are
`TimeSpan` values.

## Common tasks

```powershell
# Inventory
Get-PVEVM -Name 'web*'
Get-PVENode pve01 | Get-PVEContainer
Get-PVEStorage -Content iso
Get-PVEPool | Select-Object Name, Members

# Power
Get-PVEVM -Name 'test*' | Stop-PVEVMGuest -TimeoutSec 120 -ForceStop -Confirm:$false
Start-PVEVM -VMId 100, 101 -RunAsync | Wait-PVETask
Restart-PVEVMGuest -VMId 100 -TimeoutSec 180
Get-PVETask -Node pve01 -Source all -Limit 10

# Create, clone, change, move, delete
New-PVEVM web01 -Cores 2 -MemoryGB 4 -DiskGB 32 -Storage local-lvm -NetworkBridge vmbr0 -OSType l26 -PowerOn
Copy-PVEVM tmpl-debian13 -NewName web02 | Start-PVEVM
Get-PVEVM 'web*' | Set-PVEVM -Tags web, production -StartOnBoot $true
Move-PVEVM web01 -Storage fast-ssd -DeleteSource
Get-PVEVM 'scratch-*' | Stop-PVEVM -Confirm:$false | Remove-PVEVM -Purge -Confirm:$false

# Hardware and cloud-init
Get-PVEVM db01 | New-PVEVMHardDisk -SizeGB 200 -Storage local-lvm -SSD -Discard
Set-PVEVMHardDisk -VMId 100 -Device scsi0 -SizeGB 64
Set-PVEVMCloudInit -VMId 100 -User debian -SshPublicKey (Get-Content ~/.ssh/id_ed25519.pub) -IPAddress dhcp -Storage local-lvm

# Snapshots
Get-PVEVM 'web*' | New-PVEVMSnapshot -Snapshot before-upgrade
Restore-PVEVMSnapshot -VMId 100 -Snapshot before-upgrade -Confirm:$false

# Guest agent
Get-PVEVM 'web*' | Invoke-PVEVMScript -ScriptText 'systemctl is-active nginx' | Select-Object VMName, ExitCode, StdOut
Get-PVEVMGuest -VMId 100 | Select-Object HostName, OSName, IPAddress

# Storage, backup and restore
Get-PVEApplianceTemplate 'debian-13-standard*' | Save-PVEApplianceTemplate -Storage local
Get-PVEVM web01 | Backup-PVEVM -Storage local -Mode snapshot
Get-PVEBackup -VMId 100 -Latest | Restore-PVEBackup -VMId 150 -Unique

# Statistics and events
Get-PVEVMStat -VMId 100 -Timeframe day -Metric cpu, mem
Get-PVEEvent -Start (Get-Date).AddHours(-1)

# Anything else, through the raw API
Invoke-PVEApi -Path /cluster/resources -Parameters @{ type = 'vm' }
Invoke-PVEApi -Method POST -Path /nodes/pve01/qemu/9001/status/start -WhatIf
```

## Cmdlet index

Each entry links to its full reference: syntax, every parameter, output type and examples. The same text
is available in the shell with `Get-Help <cmdlet> -Full`.

<!-- cmdlet-index:start -->
**[Connections and the raw API](#connections-and-the-raw-api)**

| Cmdlet | Purpose |
|---|---|
| [`Connect-PVE`](#connect-pve) | Opens a connection to a Proxmox VE server or cluster node. |
| [`Disconnect-PVE`](#disconnect-pve) | Closes one or more Proxmox VE connections. |
| [`Get-PVEConnection`](#get-pveconnection) | Lists the open Proxmox VE connections in this session. |
| [`Invoke-PVEApi`](#invoke-pveapi) | Calls any Proxmox VE API endpoint directly, using an open connection's authentication. |

**[Tasks](#tasks)**

| Cmdlet | Purpose |
|---|---|
| [`Get-PVETask`](#get-pvetask) | Gets Proxmox VE tasks: recent cluster-wide tasks, the task list of specific nodes, or specific tasks by UPID. |
| [`Wait-PVETask`](#wait-pvetask) | Waits for Proxmox VE tasks to finish. |

**[Inventory](#inventory)**

| Cmdlet | Purpose |
|---|---|
| [`Get-PVENode`](#get-pvenode) | Gets Proxmox VE nodes. |
| [`Get-PVEVM`](#get-pvevm) | Gets QEMU virtual machines. |
| [`Get-PVEContainer`](#get-pvecontainer) | Gets LXC containers. |
| [`Get-PVEStorage`](#get-pvestorage) | Gets storage (datastores) and their capacity, per node. |
| [`Get-PVEPool`](#get-pvepool) | Gets resource pools and their members. |

**[VM power](#vm-power)**

| Cmdlet | Purpose |
|---|---|
| [`Start-PVEVM`](#start-pvevm) | Starts QEMU virtual machines. |
| [`Stop-PVEVMGuest`](#stop-pvevmguest) | Shuts down the guest operating system of QEMU virtual machines cleanly. |
| [`Stop-PVEVM`](#stop-pvevm) | Powers off QEMU virtual machines immediately (hard stop). |
| [`Restart-PVEVMGuest`](#restart-pvevmguest) | Reboots QEMU virtual machines cleanly. |
| [`Restart-PVEVM`](#restart-pvevm) | Resets QEMU virtual machines (hard restart). |
| [`Suspend-PVEVM`](#suspend-pvevm) | Suspends (pauses) QEMU virtual machines, or hibernates them to disk. |
| [`Resume-PVEVM`](#resume-pvevm) | Resumes QEMU virtual machines paused with Suspend-PVEVM. |

**[Container power](#container-power)**

| Cmdlet | Purpose |
|---|---|
| [`Start-PVEContainer`](#start-pvecontainer) | Starts LXC containers. |
| [`Stop-PVEContainerGuest`](#stop-pvecontainerguest) | Shuts down LXC containers cleanly. |
| [`Stop-PVEContainer`](#stop-pvecontainer) | Stops LXC containers immediately (hard stop). |
| [`Restart-PVEContainer`](#restart-pvecontainer) | Reboots LXC containers cleanly. |

**[VM lifecycle](#vm-lifecycle)**

| Cmdlet | Purpose |
|---|---|
| [`New-PVEVM`](#new-pvevm) | Creates a QEMU virtual machine. |
| [`Set-PVEVM`](#set-pvevm) | Changes the configuration of QEMU virtual machines. |
| [`Copy-PVEVM`](#copy-pvevm) | Clones a VM or VM template into a new VM. |
| [`Move-PVEVM`](#move-pvevm) | Moves the storage of VMs to another storage. |
| [`ConvertTo-PVEVMTemplate`](#convertto-pvevmtemplate) | Converts VMs into templates. |
| [`Remove-PVEVM`](#remove-pvevm) | Deletes QEMU virtual machines and their disks. |

**[Container lifecycle](#container-lifecycle)**

| Cmdlet | Purpose |
|---|---|
| [`New-PVEContainer`](#new-pvecontainer) | Creates an LXC container from an OS template. |
| [`Set-PVEContainer`](#set-pvecontainer) | Changes the configuration of LXC containers. |
| [`Copy-PVEContainer`](#copy-pvecontainer) | Clones a container or container template into a new container. |
| [`Move-PVEContainer`](#move-pvecontainer) | Moves the storage of containers to another storage. |
| [`ConvertTo-PVEContainerTemplate`](#convertto-pvecontainertemplate) | Converts containers into templates. |
| [`Remove-PVEContainer`](#remove-pvecontainer) | Deletes LXC containers and their volumes. |

**[VM hardware](#vm-hardware)**

| Cmdlet | Purpose |
|---|---|
| [`Get-PVEVMHardDisk`](#get-pvevmharddisk) | Gets the hard disks of QEMU virtual machines. |
| [`New-PVEVMHardDisk`](#new-pvevmharddisk) | Adds a hard disk to QEMU virtual machines. |
| [`Set-PVEVMHardDisk`](#set-pvevmharddisk) | Grows QEMU hard disks or changes their options. |
| [`Remove-PVEVMHardDisk`](#remove-pvevmharddisk) | Detaches hard disks from QEMU virtual machines, or deletes them. |
| [`Get-PVEVMNetworkAdapter`](#get-pvevmnetworkadapter) | Gets the network adapters of QEMU virtual machines. |
| [`New-PVEVMNetworkAdapter`](#new-pvevmnetworkadapter) | Adds a network adapter to QEMU virtual machines. |
| [`Set-PVEVMNetworkAdapter`](#set-pvevmnetworkadapter) | Changes QEMU network adapters: bridge, VLAN, link state, model, MAC and other options. |
| [`Remove-PVEVMNetworkAdapter`](#remove-pvevmnetworkadapter) | Removes network adapters from QEMU virtual machines. |
| [`Get-PVEVMCDDrive`](#get-pvevmcddrive) | Gets the CD drives of QEMU virtual machines. |
| [`New-PVEVMCDDrive`](#new-pvevmcddrive) | Adds a CD drive to QEMU virtual machines, empty or with an ISO. |
| [`Set-PVEVMCDDrive`](#set-pvevmcddrive) | Inserts an ISO into, or ejects the media from, QEMU CD drives. |
| [`Remove-PVEVMCDDrive`](#remove-pvevmcddrive) | Removes CD drives from QEMU virtual machines. |
| [`Get-PVEVMCloudInit`](#get-pvevmcloudinit) | Gets the cloud-init settings of QEMU virtual machines. |
| [`Set-PVEVMCloudInit`](#set-pvevmcloudinit) | Changes the cloud-init settings of QEMU virtual machines, and adds a cloud-init drive if needed. |

**[Container hardware](#container-hardware)**

| Cmdlet | Purpose |
|---|---|
| [`Get-PVEContainerVolume`](#get-pvecontainervolume) | Gets the root file system and mount points of LXC containers. |
| [`New-PVEContainerVolume`](#new-pvecontainervolume) | Adds a mount point to LXC containers: a new volume, or a bind mount of a host directory. |
| [`Set-PVEContainerVolume`](#set-pvecontainervolume) | Grows LXC container volumes or changes their mount options. |
| [`Remove-PVEContainerVolume`](#remove-pvecontainervolume) | Detaches mount points from LXC containers, or deletes their volumes. |
| [`Get-PVEContainerNetworkAdapter`](#get-pvecontainernetworkadapter) | Gets the network adapters of LXC containers. |
| [`New-PVEContainerNetworkAdapter`](#new-pvecontainernetworkadapter) | Adds a network adapter to LXC containers. |
| [`Set-PVEContainerNetworkAdapter`](#set-pvecontainernetworkadapter) | Changes LXC container network adapters: bridge, addresses, VLAN, link state and other options. |
| [`Remove-PVEContainerNetworkAdapter`](#remove-pvecontainernetworkadapter) | Removes network adapters from LXC containers. |

**[Snapshots](#snapshots)**

| Cmdlet | Purpose |
|---|---|
| [`Get-PVEVMSnapshot`](#get-pvevmsnapshot) | Gets the snapshots of QEMU virtual machines. |
| [`New-PVEVMSnapshot`](#new-pvevmsnapshot) | Takes a snapshot of QEMU virtual machines. |
| [`Set-PVEVMSnapshot`](#set-pvevmsnapshot) | Changes the description of VM snapshots. |
| [`Restore-PVEVMSnapshot`](#restore-pvevmsnapshot) | Rolls VMs back to a snapshot. |
| [`Remove-PVEVMSnapshot`](#remove-pvevmsnapshot) | Deletes VM snapshots. |
| [`Get-PVEContainerSnapshot`](#get-pvecontainersnapshot) | Gets the snapshots of LXC containers. |
| [`New-PVEContainerSnapshot`](#new-pvecontainersnapshot) | Takes a snapshot of LXC containers. |
| [`Set-PVEContainerSnapshot`](#set-pvecontainersnapshot) | Changes the description of container snapshots. |
| [`Restore-PVEContainerSnapshot`](#restore-pvecontainersnapshot) | Rolls containers back to a snapshot. |
| [`Remove-PVEContainerSnapshot`](#remove-pvecontainersnapshot) | Deletes container snapshots. |

**[Guest agent and console](#guest-agent-and-console)**

| Cmdlet | Purpose |
|---|---|
| [`Get-PVEVMGuest`](#get-pvevmguest) | Gets what the QEMU guest agent reports from inside VMs: OS, host name and IP addresses. |
| [`Invoke-PVEVMScript`](#invoke-pvevmscript) | Runs a command inside running VMs through the QEMU guest agent and returns its output. |
| [`Copy-PVEVMGuestFile`](#copy-pvevmguestfile) | Copies a file between this computer and a VM, through the QEMU guest agent. |
| [`Open-PVEVMConsole`](#open-pvevmconsole) | Opens the noVNC console of VMs in the default web browser. |
| [`Open-PVEContainerConsole`](#open-pvecontainerconsole) | Opens the noVNC console of containers in the default web browser. |

**[Storage content and templates](#storage-content-and-templates)**

| Cmdlet | Purpose |
|---|---|
| [`Get-PVEStorageContent`](#get-pvestoragecontent) | Lists what is stored on PVE storages: ISO images, container templates, backups, disk images and more. |
| [`Import-PVEStorageContent`](#import-pvestoragecontent) | Puts an ISO image, container template or import file onto a PVE storage, from a URL or a local file. |
| [`Set-PVEStorageContent`](#set-pvestoragecontent) | Changes the notes or protection of stored volumes. |
| [`Remove-PVEStorageContent`](#remove-pvestoragecontent) | Deletes volumes from storage: ISO images, templates, backups, or unused disk images. |
| [`Get-PVEApplianceTemplate`](#get-pveappliancetemplate) | Lists the container templates PVE can download (the appliance catalogue that pveam uses). |
| [`Save-PVEApplianceTemplate`](#save-pveappliancetemplate) | Downloads container templates from the PVE appliance catalogue onto a storage. |

**[Backup and restore](#backup-and-restore)**

| Cmdlet | Purpose |
|---|---|
| [`Backup-PVEVM`](#backup-pvevm) | Backs up VMs with vzdump. |
| [`Backup-PVEContainer`](#backup-pvecontainer) | Backs up containers with vzdump. |
| [`Get-PVEBackup`](#get-pvebackup) | Lists backups, optionally of particular guests, newest first. |
| [`Restore-PVEBackup`](#restore-pvebackup) | Restores a VM or container from a backup. |

**[Statistics and events](#statistics-and-events)**

| Cmdlet | Purpose |
|---|---|
| [`Get-PVEVMStat`](#get-pvevmstat) | Gets performance statistics of VMs from PVE's round-robin database. |
| [`Get-PVEContainerStat`](#get-pvecontainerstat) | Gets performance statistics of containers from PVE's round-robin database. |
| [`Get-PVENodeStat`](#get-pvenodestat) | Gets performance statistics of nodes from PVE's round-robin database. |
| [`Get-PVEStorageStat`](#get-pvestoragestat) | Gets usage statistics of storages from PVE's round-robin database. |
| [`Get-PVEEvent`](#get-pveevent) | Gets recent entries of the PVE cluster log: logins, task starts and ends, and other events. |
<!-- cmdlet-index:end -->

## Cmdlet reference

This reference is generated from the cmdlets' comment-based help by `build/Update-PVEReadme.ps1`; edit
the help in `Public/`, not this section. The parameters common to all cmdlets (`-Verbose`,
`-ErrorAction` and the rest; see `Get-Help about_CommonParameters`) are not repeated here.

<!-- cmdlet-reference:start -->
### Connections and the raw API

#### Connect-PVE

Opens a connection to a Proxmox VE server or cluster node.

Authenticates, verifies the connection by reading /version, and returns a PVEPS.Connection object.
Unless -NotDefault is given, the new connection becomes the default used by every cmdlet that is not
passed -Server.

Credentials can be given as -User and -Password, or as a PSCredential with -Credential. If -Password is
left out, it is prompted for without echoing.

By default the credentials are a user name and password (ticket authentication). The ticket is renewed
automatically before it expires, and the credential is held in memory for the life of the connection so
the module can log in again if renewal fails. Users with two-factor authentication enabled cannot use
ticket authentication; use an API token.

With -Token, the same inputs are an API token instead: the user name is the full token ID
(user@realm!tokenname) and the password is the token secret.

**Syntax**

```text
# Parameter set: UserPassword (default)
Connect-PVE [-Server] <string> -User <string> [-Port <int>] [-Password <Object>] [-Token]
    [-SkipCertificateCheck] [-NotDefault] [<CommonParameters>]

# Parameter set: Credential
Connect-PVE [-Server] <string> -Credential <pscredential> [-Port <int>] [-Token] [-SkipCertificateCheck]
    [-NotDefault] [<CommonParameters>]
```

**Parameters**

- **`-Server`** `String`
  Host name or IP address (IPv4 or IPv6) of the PVE node. Do not include `https://` or a port.

  _Required: yes · Position: first_
- **`-Port`** `Int32`
  API port. Defaults to 8006.

  _Required: no · Position: named · Range: 1 to 65535 · Default: 8006_
- **`-User`** `String`
  User name with realm (for example root@pam or admin@pve), or with -Token the full token ID
  (for example automation@pve!pveps).

  _Required: yes · Parameter set: UserPassword · Position: named · Alias: -Username_
- **`-Password`** `Object`
  Password, or with -Token the token secret. Accepts a string or a SecureString. Prompted for if omitted.
  A plain string typed on the command line can end up in shell history; prefer the prompt or a
  SecureString in interactive use.

  _Required: no · Parameter set: UserPassword · Position: named_
- **`-Credential`** `PSCredential`
  PSCredential holding the user name and password, or with -Token the token ID and secret.

  _Required: yes · Parameter set: Credential · Position: named_
- **`-Token`** `SwitchParameter`
  Treat the user name and password as an API token ID and secret instead of a login.

  _Required: no · Position: named_
- **`-SkipCertificateCheck`** `SwitchParameter`
  Do not validate the server's TLS certificate, for this connection only. Needed for the self-signed
  certificate a fresh PVE install uses.

  _Required: no · Position: named_
- **`-NotDefault`** `SwitchParameter`
  Do not make this connection the default.

  _Required: no · Position: named_

**Output:** `PVEPS.Connection`

**Examples**

```powershell
Connect-PVE -Server pve01.example.com -User root@pam
Prompts for the password.
Connect-PVE -Server pve01.example.com -User root@pam -Password 'secret' -SkipCertificateCheck
Connect-PVE -Server 192.0.2.10 -User 'automation@pve!pveps' -Password $tokenSecret -Token
Connect-PVE -Server pve01.example.com -Credential (Get-Credential root@pam)
```

[Back to the cmdlet index](#cmdlet-index)

#### Disconnect-PVE

Closes one or more Proxmox VE connections.

Discards the ticket, CSRF token, stored credential or token secret held for the connection. The PVE API
has no logout endpoint, so an issued ticket stays valid on the server until it expires (two hours after
it was issued or last renewed).

If the default connection is closed, the most recently opened remaining connection becomes the default.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
Disconnect-PVE [[-Server] <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Server`** `Object[]`
  Connection objects, or server names (wildcards allowed; '\*' closes every connection). Defaults to the
  default connection.

  _Required: no · Position: first · Pipeline: by value_

**Examples**

```powershell
Disconnect-PVE
Disconnect-PVE -Server *
```

[Back to the cmdlet index](#cmdlet-index)

#### Get-PVEConnection

Lists the open Proxmox VE connections in this session.

Writes the PVEPS.Connection objects that Connect-PVE created and Disconnect-PVE has not closed, in the
order they were opened. -Default writes only the default connection: the one cmdlets use when -Server
is not given (the newest connection, unless it was opened with -NotDefault). The objects hold no
secrets; tickets, CSRF tokens and token secrets are kept inside the module.

**Syntax**

```text
# Parameter set: All (default)
Get-PVEConnection [[-Server] <string>] [<CommonParameters>]

# Parameter set: Default
Get-PVEConnection -Default [<CommonParameters>]
```

**Parameters**

- **`-Server`** `String`
  Server name filter; wildcards allowed.

  _Required: no · Parameter set: All · Position: first · Default: '\*'_
- **`-Default`** `SwitchParameter`
  Return only the default connection.

  _Required: yes · Parameter set: Default · Position: named_

**Output:** `PVEPS.Connection`

**Examples**

```powershell
Get-PVEConnection
Get-PVEConnection -Default
```

[Back to the cmdlet index](#cmdlet-index)

#### Invoke-PVEApi

Calls any Proxmox VE API endpoint directly, using an open connection's authentication.

An escape hatch for endpoints PVEPS does not yet wrap. Paths are as shown in the PVE API viewer
(`https://<node>:8006/pve-docs/api-viewer/`), without the /api2/json prefix. Returns the response's "data"
member as-is. Non-GET calls honour -WhatIf and -Confirm.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
Invoke-PVEApi [-Path] <string> [-Method <string>] [-Parameters <hashtable>] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Path`** `String`
  API path, for example '/nodes/pve01/qemu'. Values in the path must already be URL-escaped.

  _Required: yes · Position: first_
- **`-Method`** `String`
  HTTP method. Defaults to GET.

  _Required: no · Position: named · Values: GET, POST, PUT, DELETE · Default: 'GET'_
- **`-Parameters`** `Hashtable`
  API parameters. Sent as a query string for GET/DELETE and as a form body for POST/PUT. Booleans are
  sent as 1/0.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection.

  _Required: no · Position: named_

**Examples**

```powershell
Invoke-PVEApi -Path /cluster/resources -Parameters @{ type = 'vm' }
Invoke-PVEApi -Method POST -Path /nodes/pve01/qemu/9001/status/start -WhatIf
```

[Back to the cmdlet index](#cmdlet-index)

### Tasks

#### Get-PVETask

Gets Proxmox VE tasks: recent cluster-wide tasks, the task list of specific nodes, or specific tasks by UPID.

- No node or UPID: GET /cluster/tasks (recent tasks across the cluster).
- -Node: GET /nodes/{node}/tasks, with optional filters.
- -Upid: GET /nodes/{node}/tasks/{upid}/status. The node is read from the UPID.
Every task object carries its connection, so it can be piped to Wait-PVETask against the right server.

**Syntax**

```text
# Parameter set: Cluster (default)
Get-PVETask [-Server <Object[]>] [<CommonParameters>]

# Parameter set: Upid
Get-PVETask [-Upid] <string[]> [-Server <Object[]>] [<CommonParameters>]

# Parameter set: Node
Get-PVETask -Node <string[]> [-VMId <int>] [-ErrorsOnly] [-Source <string>] [-Limit <int>]
    [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-Upid`** `String[]`
  Task identifier(s), as returned by asynchronous PVE operations.

  _Required: yes · Parameter set: Upid · Position: first · Pipeline: by value and by property name_
- **`-Node`** `String[]`
  Node name(s) whose task list to read.

  _Required: yes · Parameter set: Node · Position: named_
- **`-VMId`** `Int32`
  Only tasks for this guest ID (with -Node).

  _Required: no · Parameter set: Node · Position: named · Range: 1 to 999999999_
- **`-ErrorsOnly`** `SwitchParameter`
  Only tasks that ended in error (with -Node).

  _Required: no · Parameter set: Node · Position: named_
- **`-Source`** `String`
  archive (finished, the PVE default), active (running), or all (with -Node).

  _Required: no · Parameter set: Node · Position: named · Values: archive, active, all_
- **`-Limit`** `Int32`
  Maximum number of tasks per node (with -Node).

  _Required: no · Parameter set: Node · Position: named · Range: 1 to 2147483647_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Task`

**Examples**

```powershell
Get-PVETask
Get-PVETask -Node pve01 -VMId 9001 -Source all
Get-PVETask -Upid 'UPID:pve01:0001A2B3:...'
```

[Back to the cmdlet index](#cmdlet-index)

#### Wait-PVETask

Waits for Proxmox VE tasks to finish.

Polls each task's status until it stops, starting at 0.5 s between polls and backing off to 5 s. Every
task piped in is waited on at the same time.

- A task that ends with OK is written to the output.
- A task that ends with WARNINGS is written to the output, with a warning.
- A task that ends with any other exit status is a non-terminating error. The task object is the
  error's TargetObject and is not written to the output, so a following pipeline stage only receives
  tasks that succeeded.
- A task still running when -TimeoutSec runs out is a non-terminating error. The task itself is not
  cancelled.

**Syntax**

```text
Wait-PVETask [-Upid] <string[]> [-Server <Object[]>] [-TimeoutSec <int>] [<CommonParameters>]
```

**Parameters**

- **`-Upid`** `String[]`
  Task UPID(s). Binds from piped task objects or plain UPID strings.

  _Required: yes · Position: first · Pipeline: by value and by property name_
- **`-Server`** `Object[]`
  Connection to use for plain UPID strings. Task objects carry their own connection. Defaults to the
  default connection.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_
- **`-TimeoutSec`** `Int32`
  Maximum seconds to wait. 0 (the default) waits without limit.

  _Required: no · Position: named · Range: 0 to 2147483647 · Default: 0_

**Output:** `PVEPS.Task`

**Examples**

```powershell
Get-PVETask -Upid $upid | Wait-PVETask -TimeoutSec 300
```

[Back to the cmdlet index](#cmdlet-index)

### Inventory

#### Get-PVENode

Gets Proxmox VE nodes.

Lists nodes from /nodes and, for each online node, adds details from /nodes/{node}/status: PVE version,
running kernel, CPU model, sockets and physical cores, load average, root file system and swap usage,
and boot mode. Offline nodes are returned with those fields empty.

The swap fields are not in the API schema; they are read as a PVE 9.2.21 node returns them. SecureBoot
is empty unless the node booted through EFI (according to the API schema).

A non-wildcard -Name that matches no node is reported as a non-terminating "not found" error.

Node objects have both a Name and a Node property (Node is an alias of Name), so they can be piped to
Get-PVEVM, Get-PVEContainer and Get-PVEStorage.

**Syntax**

```text
Get-PVENode [[-Name] <string[]>] [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  Node name(s). Wildcards allowed.

  _Required: no · Position: first · Wildcards: yes_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Node`

**Examples**

```powershell
Get-PVENode
Get-PVENode pve01 | Get-PVEVM
```

[Back to the cmdlet index](#cmdlet-index)

#### Get-PVEVM

Gets QEMU virtual machines.

Reads every VM in a single /cluster/resources call. Templates are left out unless -IncludeTemplate is
given, as PowerCLI's Get-VM leaves templates out.

A non-wildcard -Name, or a -VMId, that matches no VM is reported as a non-terminating "not found" error.

**Syntax**

```text
Get-PVEVM [[-Name] <string[]>] [-VMId <int[]>] [-Node <string[]>] [-IncludeTemplate] [-Server <Object[]>]
    [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: no · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  VM ID(s).

  _Required: no · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-Node`** `String[]`
  Only VMs on these node(s). Wildcards allowed. Binds from piped PVEPS.Node objects.

  _Required: no · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-IncludeTemplate`** `SwitchParameter`
  Include VM templates.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VM`

**Examples**

```powershell
Get-PVEVM
Get-PVEVM -Name 'web*'
Get-PVEVM -VMId 100, 101
Get-PVENode pve01 | Get-PVEVM
```

[Back to the cmdlet index](#cmdlet-index)

#### Get-PVEContainer

Gets LXC containers.

Reads every container in a single /cluster/resources call. Templates are left out unless
-IncludeTemplate is given.

A non-wildcard -Name, or a -VMId, that matches no container is reported as a non-terminating "not found"
error.

**Syntax**

```text
Get-PVEContainer [[-Name] <string[]>] [-VMId <int[]>] [-Node <string[]>] [-IncludeTemplate]
    [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  Container name(s) (host names). Wildcards allowed.

  _Required: no · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  Container ID(s).

  _Required: no · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-Node`** `String[]`
  Only containers on these node(s). Wildcards allowed. Binds from piped PVEPS.Node objects.

  _Required: no · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-IncludeTemplate`** `SwitchParameter`
  Include container templates.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Container`

**Examples**

```powershell
Get-PVEContainer
Get-PVEContainer -Name 'dns*' | Where-Object Status -EQ 'running'
```

[Back to the cmdlet index](#cmdlet-index)

#### Get-PVEStorage

Gets storage (datastores) and their capacity, per node.

Reads /nodes/{node}/storage for each node, which reports space as seen from that node. A storage defined
for several nodes appears once per node. Capacity fields are empty for storage that is not active.

A non-wildcard -Name that matches no storage is reported as a non-terminating "not found" error.

**Syntax**

```text
Get-PVEStorage [[-Name] <string[]>] [-Node <string[]>] [-Content <string>] [-Server <Object[]>]
    [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  Storage ID(s), for example local or local-lvm. Wildcards allowed.

  _Required: no · Position: first · Wildcards: yes_
- **`-Node`** `String[]`
  Only these node(s). Wildcards allowed. Binds from piped PVEPS.Node objects. Defaults to every node.

  _Required: no · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-Content`** `String`
  Only storage that accepts this content type, for example images (VM disks), rootdir (container
  volumes), iso, vztmpl (container templates), backup, snippets or import.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Storage`

**Examples**

```powershell
Get-PVEStorage
Get-PVEStorage -Content iso
```

[Back to the cmdlet index](#cmdlet-index)

#### Get-PVEPool

Gets resource pools and their members.

Lists pools from /pools, then reads each matching pool's members with GET /pools?poolid=&lt;id&gt; (the
per-pool path /pools/{poolid} is deprecated in the API). Only pools the caller has Pool.Audit on are
visible.

A non-wildcard -Name that matches no pool is reported as a non-terminating "not found" error.

**Syntax**

```text
Get-PVEPool [[-Name] <string[]>] [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  Pool ID(s). Wildcards allowed.

  _Required: no · Position: first · Wildcards: yes_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Pool`

**Examples**

```powershell
Get-PVEPool
(Get-PVEPool lab).Members | Where-Object Type -EQ 'qemu'
```

[Back to the cmdlet index](#cmdlet-index)

### VM power

#### Start-PVEVM

Starts QEMU virtual machines.

Starts each VM and, unless -RunAsync is given, waits for the start task to finish and writes the VM
with its live status. A VM that is already running is skipped with a warning and written unchanged.
Also resumes a VM that was suspended to disk with Suspend-PVEVM -ToDisk.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Start-PVEVM -VMId <int[]> [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
Start-PVEVM [-Name] <string[]> [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-RunAsync`** `SwitchParameter`
  Return the PVE task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VM`, `PVEPS.Task`

**Examples**

```powershell
Start-PVEVM web01
Get-PVEVM -Name 'web*' | Start-PVEVM
Start-PVEVM -VMId 100, 101 -RunAsync | Wait-PVETask
```

[Back to the cmdlet index](#cmdlet-index)

#### Stop-PVEVMGuest

Shuts down the guest operating system of QEMU virtual machines cleanly.

Sends the guest OS a shutdown request (the PVE API describes it as an ACPI event, like pressing the
power button). The guest OS must respond; if it has not shut down when the timeout runs out, the task
fails unless -ForceStop is given.

Prompts for confirmation by default (ConfirmImpact High). A VM that is not running is skipped with a
warning and written unchanged.

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Stop-PVEVMGuest -VMId <int[]> [-TimeoutSec <int>] [-ForceStop] [-RunAsync] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]

# Parameter set: Name
Stop-PVEVMGuest [-Name] <string[]> [-TimeoutSec <int>] [-ForceStop] [-RunAsync] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-TimeoutSec`** `Int32`
  Seconds PVE waits for the guest to shut down. PVE's own default applies when omitted.

  _Required: no · Position: named · Range: 1 to 2147483647_
- **`-ForceStop`** `SwitchParameter`
  Power the VM off if it has not shut down when the timeout runs out.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the PVE task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VM`, `PVEPS.Task`

**Examples**

```powershell
Stop-PVEVMGuest web01
Get-PVEVM -Node pve | Stop-PVEVMGuest -TimeoutSec 120 -ForceStop -Confirm:$false
```

[Back to the cmdlet index](#cmdlet-index)

#### Stop-PVEVM

Powers off QEMU virtual machines immediately (hard stop).

The QEMU process exits at once, like pulling the power plug; the guest OS gets no chance to shut down
and data not yet written can be lost. For a clean shutdown use Stop-PVEVMGuest.

Prompts for confirmation by default (ConfirmImpact High); use -Confirm:$false in scripts. A VM that is
not running is skipped with a warning and written unchanged.

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Stop-PVEVM -VMId <int[]> [-OverruleShutdown] [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]

# Parameter set: Name
Stop-PVEVM [-Name] <string[]> [-OverruleShutdown] [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-OverruleShutdown`** `SwitchParameter`
  Abort a guest shutdown that is already in progress for the VM before stopping it.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the PVE task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VM`, `PVEPS.Task`

**Examples**

```powershell
Stop-PVEVM web01
Get-PVEVM -Name 'test*' | Stop-PVEVM -Confirm:$false
```

[Back to the cmdlet index](#cmdlet-index)

#### Restart-PVEVMGuest

Reboots QEMU virtual machines cleanly.

PVE shuts the guest down cleanly (as Stop-PVEVMGuest) and starts it again. Because
the VM is started fresh, pending configuration changes are applied.

Prompts for confirmation by default (ConfirmImpact High). A VM that is not running is skipped with a
warning and written unchanged.

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Restart-PVEVMGuest -VMId <int[]> [-TimeoutSec <int>] [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]

# Parameter set: Name
Restart-PVEVMGuest [-Name] <string[]> [-TimeoutSec <int>] [-RunAsync] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-TimeoutSec`** `Int32`
  Seconds PVE waits for the shutdown half of the reboot. PVE's own default applies when omitted.

  _Required: no · Position: named · Range: 1 to 2147483647_
- **`-RunAsync`** `SwitchParameter`
  Return the PVE task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VM`, `PVEPS.Task`

**Examples**

```powershell
Restart-PVEVMGuest web01
```

[Back to the cmdlet index](#cmdlet-index)

#### Restart-PVEVM

Resets QEMU virtual machines (hard restart).

Like pressing a physical reset button: the guest restarts immediately without shutting down, and data
not yet written can be lost. For a clean restart use Restart-PVEVMGuest.

Prompts for confirmation by default (ConfirmImpact High). A VM that is not running is skipped with a
warning and written unchanged.

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Restart-PVEVM -VMId <int[]> [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
Restart-PVEVM [-Name] <string[]> [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-RunAsync`** `SwitchParameter`
  Return the PVE task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VM`, `PVEPS.Task`

**Examples**

```powershell
Restart-PVEVM web01 -Confirm:$false
```

[Back to the cmdlet index](#cmdlet-index)

#### Suspend-PVEVM

Suspends (pauses) QEMU virtual machines, or hibernates them to disk.

Without -ToDisk, the VM is paused in memory; resume it with Resume-PVEVM. PVE still reports a paused VM
with Status 'running', because the QEMU process is still running.

With -ToDisk, the VM's memory is saved to a state volume and the VM stops (Status 'stopped', Lock
'suspended'); resume it with Start-PVEVM. This needs VM.Config.Disk on the VM and
Datastore.AllocateSpace on the state storage, as well as VM.PowerMgmt.

Prompts for confirmation by default (ConfirmImpact High). A VM that is not running is skipped with a
warning and written unchanged.

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Suspend-PVEVM -VMId <int[]> [-ToDisk] [-StateStorage <string>] [-RunAsync] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]

# Parameter set: Name
Suspend-PVEVM [-Name] <string[]> [-ToDisk] [-StateStorage <string>] [-RunAsync] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-ToDisk`** `SwitchParameter`
  Hibernate: save memory to disk and stop the VM.

  _Required: no · Position: named_
- **`-StateStorage`** `String`
  Storage for the saved memory state (with -ToDisk). PVE chooses when omitted.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the PVE task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VM`, `PVEPS.Task`

**Examples**

```powershell
Suspend-PVEVM web01
Suspend-PVEVM web01 -ToDisk -StateStorage local-lvm
```

[Back to the cmdlet index](#cmdlet-index)

#### Resume-PVEVM

Resumes QEMU virtual machines paused with Suspend-PVEVM.

Resumes a VM paused in memory. A VM hibernated with Suspend-PVEVM -ToDisk is stopped, not paused;
resume that with Start-PVEVM. PVE rejects the request for a VM that is not paused, and that rejection
is reported as an error.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Resume-PVEVM -VMId <int[]> [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
Resume-PVEVM [-Name] <string[]> [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-RunAsync`** `SwitchParameter`
  Return the PVE task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VM`, `PVEPS.Task`

**Examples**

```powershell
Resume-PVEVM web01
```

[Back to the cmdlet index](#cmdlet-index)

### Container power

#### Start-PVEContainer

Starts LXC containers.

Starts each container and, unless -RunAsync is given, waits for the start task to finish and writes the
container with its live status. A container that is already running is skipped with a warning and
written unchanged.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Start-PVEContainer -VMId <int[]> [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
Start-PVEContainer [-Name] <string[]> [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-RunAsync`** `SwitchParameter`
  Return the PVE task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Container`, `PVEPS.Task`

**Examples**

```powershell
Start-PVEContainer dns01
Get-PVEContainer | Where-Object Status -EQ 'stopped' | Start-PVEContainer
```

[Back to the cmdlet index](#cmdlet-index)

#### Stop-PVEContainerGuest

Shuts down LXC containers cleanly.

Asks the container's init system to shut down (see lxc-stop(1)). If the container has not stopped when
the timeout runs out, the task fails unless -ForceStop is given.

Prompts for confirmation by default (ConfirmImpact High). A container that is not running is skipped
with a warning and written unchanged.

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Stop-PVEContainerGuest -VMId <int[]> [-TimeoutSec <int>] [-ForceStop] [-RunAsync] [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
Stop-PVEContainerGuest [-Name] <string[]> [-TimeoutSec <int>] [-ForceStop] [-RunAsync] [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-TimeoutSec`** `Int32`
  Seconds PVE waits for the shutdown. PVE's own default applies when omitted.

  _Required: no · Position: named · Range: 1 to 2147483647_
- **`-ForceStop`** `SwitchParameter`
  Stop the container if it has not shut down when the timeout runs out.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the PVE task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Container`, `PVEPS.Task`

**Examples**

```powershell
Stop-PVEContainerGuest dns01
Get-PVEContainer | Stop-PVEContainerGuest -TimeoutSec 60 -ForceStop -Confirm:$false
```

[Back to the cmdlet index](#cmdlet-index)

#### Stop-PVEContainer

Stops LXC containers immediately (hard stop).

Every process in the container is stopped abruptly. For a clean shutdown use Stop-PVEContainerGuest.

Prompts for confirmation by default (ConfirmImpact High). A container that is not running is skipped
with a warning and written unchanged.

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Stop-PVEContainer -VMId <int[]> [-OverruleShutdown] [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]

# Parameter set: Name
Stop-PVEContainer [-Name] <string[]> [-OverruleShutdown] [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-OverruleShutdown`** `SwitchParameter`
  Abort a shutdown that is already in progress for the container before stopping it.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the PVE task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Container`, `PVEPS.Task`

**Examples**

```powershell
Stop-PVEContainer dns01 -Confirm:$false
```

[Back to the cmdlet index](#cmdlet-index)

#### Restart-PVEContainer

Reboots LXC containers cleanly.

PVE shuts the container down cleanly and starts it again, applying pending configuration changes.
LXC has no hard reset; to force a restart, use Stop-PVEContainer then Start-PVEContainer.

Prompts for confirmation by default (ConfirmImpact High). A container that is not running is skipped
with a warning and written unchanged.

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Restart-PVEContainer -VMId <int[]> [-TimeoutSec <int>] [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]

# Parameter set: Name
Restart-PVEContainer [-Name] <string[]> [-TimeoutSec <int>] [-RunAsync] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-TimeoutSec`** `Int32`
  Seconds PVE waits for the shutdown half of the reboot. PVE's own default applies when omitted.

  _Required: no · Position: named · Range: 1 to 2147483647_
- **`-RunAsync`** `SwitchParameter`
  Return the PVE task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Container`, `PVEPS.Task`

**Examples**

```powershell
Restart-PVEContainer dns01
```

[Back to the cmdlet index](#cmdlet-index)

### VM lifecycle

#### New-PVEVM

Creates a QEMU virtual machine.

Creates the VM with POST /nodes/{node}/qemu, waits for the create task, and writes the new VM with its
live status. Options not given are left to PVE's own defaults (for example 512 MiB of memory, one core,
no disk, no network device).

What the parameters add to the configuration:
- -DiskGB: one new disk per value on -Storage, on the -DiskBus bus (scsi0, scsi1, ...). With the scsi
  bus the controller is set to virtio-scsi-single (PVE's own default is lsi).
- -NetworkBridge: one network device per bridge (net0, net1, ...), of model -NetworkModel.
- -IsoImage: a CD drive (ide2) with that ISO.
- -Bios ovmf: also an EFI vars disk (efidisk0, efitype 4m) on -Storage.
- A boot order of the first disk, then the CD drive, then the first network device, for the ones that
  exist.
- -Parameter: any other create options, by their API names. Applied last, so they override the above.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
New-PVEVM [-Name] <string> [-VMId <int>] [-Node <string>] [-Cores <int>] [-Sockets <int>] [-MemoryGB <double>]
    [-DiskGB <int[]>] [-DiskBus <string>] [-Storage <string>] [-NetworkBridge <string[]>]
    [-NetworkModel <string>] [-IsoImage <string>] [-OSType <string>] [-Bios <string>] [-Machine <string>]
    [-CpuType <string>] [-GuestAgent] [-Pool <string>] [-Tags <string[]>] [-Description <string>]
    [-StartOnBoot] [-PowerOn] [-Parameter <hashtable>] [-RunAsync] [-Server <Object>] [-WhatIf] [-Confirm]
    [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String`
  VM name. PVE requires a valid DNS name.

  _Required: yes · Position: first_
- **`-VMId`** `Int32`
  ID for the VM. Defaults to the next free ID. PVE checks a given ID is free before the VM is created.

  _Required: no · Position: named · Range: 100 to 999999999_
- **`-Node`** `String`
  Node to create the VM on. Can be omitted when the server has a single node.

  _Required: no · Position: named_
- **`-Cores`** `Int32`
  Cores per socket.

  _Required: no · Position: named · Range: 1 to 2147483647_
- **`-Sockets`** `Int32`
  CPU sockets.

  _Required: no · Position: named · Range: 1 to 2147483647_
- **`-MemoryGB`** `Double`
  Memory in GiB, sent to PVE in whole MiB (for example 1.5 is 1536 MiB).

  _Required: no · Position: named · Range: 0.015625 to 1.7976931348623157E+308_
- **`-DiskGB`** `Int32[]`
  Size in GiB of each new disk to create on -Storage. One disk per value.

  _Required: no · Position: named · Range: 1 to 2147483647_
- **`-DiskBus`** `String`
  Bus for the new disks: scsi (the default), virtio, sata or ide.

  _Required: no · Position: named · Values: scsi, virtio, sata, ide · Default: 'scsi'_
- **`-Storage`** `String`
  Storage for the new disks and the EFI vars disk. Required with -DiskGB and with -Bios ovmf.

  _Required: no · Position: named_
- **`-NetworkBridge`** `String[]`
  Bridge for each network device, for example vmbr0. One device per value.

  _Required: no · Position: named_
- **`-NetworkModel`** `String`
  Network device model. Defaults to virtio.

  _Required: no · Position: named · Values: e1000, e1000-82540em, e1000-82544gc, e1000-82545em, e1000e, i82551, i82557b, i82559er, ne2k_isa, ne2k_pci, pcnet, rtl8139, virtio, vmxnet3 · Default: 'virtio'_
- **`-IsoImage`** `String`
  ISO volume to insert in a CD drive, for example local:iso/debian-13.1.0-amd64-netinst.iso.

  _Required: no · Position: named_
- **`-OSType`** `String`
  Guest OS type, which PVE uses to enable OS-specific optimisations. From the PVE API documentation: l26
  is a Linux 2.6 - 7.x kernel; win10 is Windows 10/2016/2019; win11 is Windows 11/2022/2025; other is
  unspecified.

  _Required: no · Position: named · Values: other, wxp, w2k, w2k3, w2k8, wvista, win7, win8, win10, win11, l24, l26, solaris_
- **`-Bios`** `String`
  seabios (PVE's default) or ovmf (UEFI).

  _Required: no · Position: named · Values: seabios, ovmf_
- **`-Machine`** `String`
  QEMU machine type, for example q35 or pc (i440fx).

  _Required: no · Position: named_
- **`-CpuType`** `String`
  Emulated CPU type, for example host or x86-64-v2-AES.

  _Required: no · Position: named_
- **`-GuestAgent`** `SwitchParameter`
  Enable the QEMU guest agent device. The agent itself has to be installed in the guest.

  _Required: no · Position: named_
- **`-Pool`** `String`
  Resource pool to add the VM to.

  _Required: no · Position: named_
- **`-Tags`** `String[]`
  Tags for the VM.

  _Required: no · Position: named_
- **`-Description`** `String`
  Description (notes) shown in the VM's summary.

  _Required: no · Position: named_
- **`-StartOnBoot`** `SwitchParameter`
  Start the VM when the node boots.

  _Required: no · Position: named_
- **`-PowerOn`** `SwitchParameter`
  Start the VM once it has been created.

  _Required: no · Position: named_
- **`-Parameter`** `Hashtable`
  Further create options by their API names, for example @{ balloon = 0; vga = 'serial0' }.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the create task at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object`
  Connection to use. Defaults to the default connection.

  _Required: no · Position: named · Alias: -Connection_

**Output:** `PVEPS.VM`, `PVEPS.Task`

**Examples**

```powershell
New-PVEVM -Name web01 -Cores 2 -MemoryGB 4 -DiskGB 32 -Storage local-lvm -NetworkBridge vmbr0 -OSType l26
New-PVEVM web02 -DiskGB 32, 100 -Storage local-lvm -IsoImage local:iso/debian-13.1.0-amd64-netinst.iso -PowerOn
New-PVEVM win01 -OSType win11 -Bios ovmf -Machine q35 -MemoryGB 8 -DiskGB 80 -Storage local-lvm -Parameter @{ tpmstate0 = 'local-lvm:1,version=v2.0' }
```

[Back to the cmdlet index](#cmdlet-index)

#### Set-PVEVM

Changes the configuration of QEMU virtual machines.

Sends the changes with POST /nodes/{node}/qemu/{vmid}/config, waits for the task, and writes each VM
with its live status.

On a running VM, PVE either applies a change at once or stores it as pending until the VM is next
started, depending on the option and the VM's hotplug settings. After the change, a warning lists the
options still pending on a running VM (read from GET .../pending).

Only the options given are changed. -Parameter reaches any other option by its API name.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Set-PVEVM -VMId <int[]> [-NewName <string>] [-Cores <int>] [-Sockets <int>] [-MemoryGB <double>]
    [-CpuType <string>] [-OSType <string>] [-Description <string>] [-Tags <string[]>] [-StartOnBoot <bool>]
    [-Protection <bool>] [-GuestAgent <bool>] [-Parameter <hashtable>] [-Delete <string[]>] [-RunAsync]
    [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
Set-PVEVM [-Name] <string[]> [-IncludeTemplate] [-NewName <string>] [-Cores <int>] [-Sockets <int>]
    [-MemoryGB <double>] [-CpuType <string>] [-OSType <string>] [-Description <string>] [-Tags <string[]>]
    [-StartOnBoot <bool>] [-Protection <bool>] [-GuestAgent <bool>] [-Parameter <hashtable>]
    [-Delete <string[]>] [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-IncludeTemplate`** `SwitchParameter`
  Let -Name match templates as well as VMs.

  _Required: no · Parameter set: Name · Position: named_
- **`-NewName`** `String`
  New name for the VM. Only allowed when exactly one VM is targeted.

  _Required: no · Position: named_
- **`-Cores`** `Int32`
  Cores per socket.

  _Required: no · Position: named · Range: 1 to 2147483647_
- **`-Sockets`** `Int32`
  CPU sockets.

  _Required: no · Position: named · Range: 1 to 2147483647_
- **`-MemoryGB`** `Double`
  Memory in GiB, sent to PVE in whole MiB.

  _Required: no · Position: named · Range: 0.015625 to 1.7976931348623157E+308_
- **`-CpuType`** `String`
  Emulated CPU type, for example host or x86-64-v2-AES.

  _Required: no · Position: named_
- **`-OSType`** `String`
  Guest OS type (see New-PVEVM).

  _Required: no · Position: named · Values: other, wxp, w2k, w2k3, w2k8, wvista, win7, win8, win10, win11, l24, l26, solaris_
- **`-Description`** `String`
  Description (notes). An empty string removes it.

  _Required: no · Position: named_
- **`-Tags`** `String[]`
  Tags, replacing the current ones. An empty array removes all tags.

  _Required: no · Position: named_
- **`-StartOnBoot`** `Boolean`
  Whether the VM starts when the node boots.

  _Required: no · Position: named_
- **`-Protection`** `Boolean`
  Whether the protection flag is set. While set, PVE refuses to delete the VM or its disks.

  _Required: no · Position: named_
- **`-GuestAgent`** `Boolean`
  Whether the QEMU guest agent device is enabled.

  _Required: no · Position: named_
- **`-Parameter`** `Hashtable`
  Further options by their API names, for example @{ balloon = 2048 }. Applied last.

  _Required: no · Position: named_
- **`-Delete`** `String[]`
  Option names to remove from the configuration, so their PVE defaults apply, for example 'balloon'.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VM`, `PVEPS.Task`

**Examples**

```powershell
Set-PVEVM -VMId 100 -Cores 4 -MemoryGB 8
Get-PVEVM -Name 'web*' | Set-PVEVM -Tags web, production -StartOnBoot $true
Set-PVEVM web01 -NewName web01-old -Protection $false
```

[Back to the cmdlet index](#cmdlet-index)

#### Copy-PVEVM

Clones a VM or VM template into a new VM.

Clones the source with POST /nodes/{node}/qemu/{vmid}/clone, waits for the clone task, and writes the
new VM with its live status. The new VM is created on the source's node.

From the API documentation: a clone of a normal VM is always a full clone (a full copy of every
disk); for a template, PVE tries to make a linked clone by default, whose disks share the template's
base image. -Full asks for a full clone of a template. -Storage and -Format apply to full clones.

The source can be named by ID or name (templates included), or piped in. Exactly one source is
cloned per call.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Copy-PVEVM -VMId <int> -NewName <string> [-NewVMId <int>] [-Full] [-Storage <string>] [-Format <string>]
    [-Pool <string>] [-Description <string>] [-Snapshot <string>] [-RunAsync] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]

# Parameter set: Name
Copy-PVEVM [-Name] <string> -NewName <string> [-NewVMId <int>] [-Full] [-Storage <string>] [-Format <string>]
    [-Pool <string>] [-Description <string>] [-Snapshot <string>] [-RunAsync] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String`
  Name of the source VM or template.

  _Required: yes · Parameter set: Name · Position: first_
- **`-VMId`** `Int32`
  ID of the source VM or template. Binds from a piped PVEPS.VM object.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-NewName`** `String`
  Name for the new VM.

  _Required: yes · Position: named_
- **`-NewVMId`** `Int32`
  ID for the new VM. Defaults to the next free ID.

  _Required: no · Position: named · Range: 100 to 999999999_
- **`-Full`** `SwitchParameter`
  Make a full clone of a template instead of a linked clone.

  _Required: no · Position: named_
- **`-Storage`** `String`
  Target storage for a full clone.

  _Required: no · Position: named_
- **`-Format`** `String`
  Disk format for a full clone: raw, qcow2 or vmdk. If the target storage does not support it, PVE uses
  the storage's default format.

  _Required: no · Position: named · Values: raw, qcow2, vmdk_
- **`-Pool`** `String`
  Resource pool to add the new VM to.

  _Required: no · Position: named_
- **`-Description`** `String`
  Description for the new VM.

  _Required: no · Position: named_
- **`-Snapshot`** `String`
  Clone the source as it was at this snapshot.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the clone task at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from a piped object.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VM`, `PVEPS.Task`

**Examples**

```powershell
Copy-PVEVM tmpl-debian13 -NewName web03
Copy-PVEVM -VMId 9000 -NewName web04 -NewVMId 104 -Full -Storage local-lvm -Pool web | Start-PVEVM
```

[Back to the cmdlet index](#cmdlet-index)

#### Move-PVEVM

Moves the storage of VMs to another storage.

Moves each VM's disks (ide, sata, scsi and virtio disks, the EFI vars disk and the TPM state disk; CD
drives are left alone) to -Storage, one at a time with POST /nodes/{node}/qemu/{vmid}/move_disk,
waiting for each to finish. Writes each VM with its live status when its moves are done.

By default PVE keeps each source volume after the copy, as an unusedN entry in the configuration;
-DeleteSource deletes it once the copy has succeeded. PVE can move the disks of a running VM.

Moving guests between nodes needs a cluster and is not covered by this cmdlet yet.

Prompts for confirmation at ConfirmImpact Medium, so not by default.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Move-PVEVM -VMId <int[]> -Storage <string> [-Disk <string[]>] [-DeleteSource] [-Format <string>]
    [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
Move-PVEVM [-Name] <string[]> -Storage <string> [-IncludeTemplate] [-Disk <string[]>] [-DeleteSource]
    [-Format <string>] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-IncludeTemplate`** `SwitchParameter`
  Let -Name match templates as well as VMs.

  _Required: no · Parameter set: Name · Position: named_
- **`-Storage`** `String`
  Target storage.

  _Required: yes · Position: named_
- **`-Disk`** `String[]`
  Disks to move, for example scsi0, virtio1, efidisk0. Defaults to every disk not already on -Storage.

  _Required: no · Position: named_
- **`-DeleteSource`** `SwitchParameter`
  Delete each source volume after it has been copied.

  _Required: no · Position: named_
- **`-Format`** `String`
  Disk format on the target storage: raw, qcow2 or vmdk. If the target storage does not support it, PVE
  uses the storage's default format.

  _Required: no · Position: named · Values: raw, qcow2, vmdk_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VM`

**Examples**

```powershell
Move-PVEVM -VMId 100 -Storage local-zfs
Get-PVEVM -Name 'db*' | Move-PVEVM -Storage fast-ssd -Disk scsi1 -DeleteSource
```

[Back to the cmdlet index](#cmdlet-index)

#### ConvertTo-PVEVMTemplate

Converts VMs into templates.

Converts each VM with POST /nodes/{node}/qemu/{vmid}/template and writes it with its live status
(IsTemplate true). A template cannot be started; Copy-PVEVM makes new VMs from it. Treat the
conversion as one-way: this module has no cmdlet that turns a template back into a VM.

Prompts for confirmation by default (ConfirmImpact High). A VM that is not stopped is an error and is
left alone; stop it first. One that is already a template is skipped with a warning and written
unchanged.

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
ConvertTo-PVEVMTemplate -VMId <int[]> [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]

# Parameter set: Name
ConvertTo-PVEVMTemplate [-Name] <string[]> [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-RunAsync`** `SwitchParameter`
  Return the task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VM`, `PVEPS.Task`

**Examples**

```powershell
ConvertTo-PVEVMTemplate -VMId 9000
Get-PVEVM -Name 'golden-*' | Stop-PVEVMGuest -Confirm:$false | ConvertTo-PVEVMTemplate -Confirm:$false
```

[Back to the cmdlet index](#cmdlet-index)

#### Remove-PVEVM

Deletes QEMU virtual machines and their disks.

Deletes each VM with DELETE /nodes/{node}/qemu/{vmid}, which PVE documents as destroying the VM and all
the volumes it uses or owns, and removing its VM-specific permissions and firewall rules. This cannot
be undone.

Prompts for confirmation by default (ConfirmImpact High). A VM that is not stopped is an error and is
left alone; stop it first. A VM with the protection flag set is refused by PVE.

Templates are deleted when named by ID or piped in. A name or wildcard matches templates only with
-IncludeTemplate.

Writes nothing on success (with -RunAsync, the delete tasks).

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Remove-PVEVM -VMId <int[]> [-Purge] [-DestroyUnreferencedDisks] [-RunAsync] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]

# Parameter set: Name
Remove-PVEVM [-Name] <string[]> [-IncludeTemplate] [-Purge] [-DestroyUnreferencedDisks] [-RunAsync]
    [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-IncludeTemplate`** `SwitchParameter`
  Let -Name match templates as well as VMs.

  _Required: no · Parameter set: Name · Position: named_
- **`-Purge`** `SwitchParameter`
  Also remove the VM ID from backup jobs, replication jobs and HA.

  _Required: no · Position: named_
- **`-DestroyUnreferencedDisks`** `SwitchParameter`
  Also destroy disks on any enabled storage that carry the VM's ID but are not in its configuration.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the delete task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Task`

**Examples**

```powershell
Remove-PVEVM -VMId 105
Get-PVEVM -Name 'scratch-*' | Stop-PVEVM -Confirm:$false | Remove-PVEVM -Purge -Confirm:$false
```

[Back to the cmdlet index](#cmdlet-index)

### Container lifecycle

#### New-PVEContainer

Creates an LXC container from an OS template.

Creates the container with POST /nodes/{node}/lxc, waits for the create task, and writes the new
container with its live status. Options not given are left to PVE's own defaults (for example 512 MiB
of memory and 512 MiB of swap). Containers are created unprivileged unless -Privileged is given; this
module sends unprivileged=1 explicitly, because the API schema lists a default of 0 while its own
description says creation defaults to 1.

What the parameters add to the configuration:
- -Storage and -DiskGB: the root file system (rootfs), a new volume of -DiskGB GiB on -Storage.
- -NetworkBridge: one network device, eth0, on that bridge, with -IPAddress (DHCP by default),
  -Gateway and -IPv6Address.
- -Nesting: the nesting feature. The API documentation says systemd needs it to isolate services, and
  that it exposes procfs and sysfs contents of the host to the guest.
- -Parameter: any other create options, by their API names. Applied last, so they override the above.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
New-PVEContainer [-Name] <string> -OSTemplate <string> -Storage <string> [-VMId <int>] [-Node <string>]
    [-DiskGB <int>] [-Cores <int>] [-MemoryGB <double>] [-SwapGB <double>] [-Password <Object>]
    [-SshPublicKey <string[]>] [-Privileged] [-NetworkBridge <string>] [-IPAddress <string>]
    [-Gateway <string>] [-IPv6Address <string>] [-Nesting] [-Pool <string>] [-Tags <string[]>]
    [-Description <string>] [-StartOnBoot] [-PowerOn] [-Parameter <hashtable>] [-RunAsync] [-Server <Object>]
    [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String`
  Host name of the container. PVE requires a valid DNS name.

  _Required: yes · Position: first_
- **`-OSTemplate`** `String`
  OS template volume, for example local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst. Get-PVEStorage
  -Content vztmpl lists the storages that hold templates.

  _Required: yes · Position: named_
- **`-VMId`** `Int32`
  ID for the container. Defaults to the next free ID. PVE checks a given ID is free before the container
  is created.

  _Required: no · Position: named · Range: 100 to 999999999_
- **`-Node`** `String`
  Node to create the container on. Can be omitted when the server has a single node.

  _Required: no · Position: named_
- **`-Storage`** `String`
  Storage for the root file system.

  _Required: yes · Position: named_
- **`-DiskGB`** `Int32`
  Size of the root file system in GiB. Defaults to 8.

  _Required: no · Position: named · Range: 1 to 2147483647 · Default: 8_
- **`-Cores`** `Int32`
  CPU cores the container may use. PVE's default is all of the host's cores.

  _Required: no · Position: named · Range: 1 to 8192_
- **`-MemoryGB`** `Double`
  Memory in GiB, sent to PVE in whole MiB.

  _Required: no · Position: named · Range: 0.015625 to 1.7976931348623157E+308_
- **`-SwapGB`** `Double`
  Swap in GiB, sent to PVE in whole MiB. 0 disables swap.

  _Required: no · Position: named · Range: 0 to 1.7976931348623157E+308_
- **`-Password`** `Object`
  Root password inside the container. Accepts a string or a SecureString.

  _Required: no · Position: named_
- **`-SshPublicKey`** `String[]`
  Public SSH keys (OpenSSH format) for root inside the container. One key per value.

  _Required: no · Position: named_
- **`-Privileged`** `SwitchParameter`
  Create a privileged container instead of an unprivileged one.

  _Required: no · Position: named_
- **`-NetworkBridge`** `String`
  Bridge for the container's eth0 network device, for example vmbr0.

  _Required: no · Position: named_
- **`-IPAddress`** `String`
  IPv4 address for eth0 in CIDR notation (192.0.2.10/24), dhcp, or manual. Defaults to dhcp. Needs
  -NetworkBridge.

  _Required: no · Position: named · Default: 'dhcp'_
- **`-Gateway`** `String`
  IPv4 gateway for eth0. Needs -NetworkBridge.

  _Required: no · Position: named_
- **`-IPv6Address`** `String`
  IPv6 address for eth0 in CIDR notation, auto, dhcp, or manual. Needs -NetworkBridge.

  _Required: no · Position: named_
- **`-Nesting`** `SwitchParameter`
  Enable the nesting feature (see the description).

  _Required: no · Position: named_
- **`-Pool`** `String`
  Resource pool to add the container to.

  _Required: no · Position: named_
- **`-Tags`** `String[]`
  Tags for the container.

  _Required: no · Position: named_
- **`-Description`** `String`
  Description (notes) shown in the container's summary.

  _Required: no · Position: named_
- **`-StartOnBoot`** `SwitchParameter`
  Start the container when the node boots.

  _Required: no · Position: named_
- **`-PowerOn`** `SwitchParameter`
  Start the container once it has been created.

  _Required: no · Position: named_
- **`-Parameter`** `Hashtable`
  Further create options by their API names, for example @{ timezone = 'host'; nameserver = '192.0.2.53' }.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the create task at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object`
  Connection to use. Defaults to the default connection.

  _Required: no · Position: named · Alias: -Connection_

**Output:** `PVEPS.Container`, `PVEPS.Task`

**Examples**

```powershell
New-PVEContainer -Name dns01 -OSTemplate local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst -Storage local-lvm -NetworkBridge vmbr0 -SshPublicKey (Get-Content ~/.ssh/id_ed25519.pub)
New-PVEContainer proxy01 -OSTemplate $template -Storage local-lvm -DiskGB 16 -MemoryGB 1 -NetworkBridge vmbr0 -IPAddress 192.0.2.20/24 -Gateway 192.0.2.1 -Nesting -PowerOn
```

[Back to the cmdlet index](#cmdlet-index)

#### Set-PVEContainer

Changes the configuration of LXC containers.

Sends the changes with PUT /nodes/{node}/lxc/{vmid}/config (a synchronous call; there is no task) and
writes each container with its live status.

On a running container, PVE either applies a change at once or stores it as pending until the
container is next started. After the change, a warning lists the options still pending on a running
container (read from GET .../pending).

Only the options given are changed. -Parameter reaches any other option by its API name.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Set-PVEContainer -VMId <int[]> [-NewName <string>] [-Cores <int>] [-MemoryGB <double>] [-SwapGB <double>]
    [-Description <string>] [-Tags <string[]>] [-StartOnBoot <bool>] [-Protection <bool>]
    [-Parameter <hashtable>] [-Delete <string[]>] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]

# Parameter set: Name
Set-PVEContainer [-Name] <string[]> [-IncludeTemplate] [-NewName <string>] [-Cores <int>] [-MemoryGB <double>]
    [-SwapGB <double>] [-Description <string>] [-Tags <string[]>] [-StartOnBoot <bool>] [-Protection <bool>]
    [-Parameter <hashtable>] [-Delete <string[]>] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-IncludeTemplate`** `SwitchParameter`
  Let -Name match templates as well as containers.

  _Required: no · Parameter set: Name · Position: named_
- **`-NewName`** `String`
  New host name for the container. Only allowed when exactly one container is targeted.

  _Required: no · Position: named_
- **`-Cores`** `Int32`
  CPU cores the container may use.

  _Required: no · Position: named · Range: 1 to 8192_
- **`-MemoryGB`** `Double`
  Memory in GiB, sent to PVE in whole MiB.

  _Required: no · Position: named · Range: 0.015625 to 1.7976931348623157E+308_
- **`-SwapGB`** `Double`
  Swap in GiB, sent to PVE in whole MiB. 0 disables swap.

  _Required: no · Position: named · Range: 0 to 1.7976931348623157E+308_
- **`-Description`** `String`
  Description (notes). An empty string removes it.

  _Required: no · Position: named_
- **`-Tags`** `String[]`
  Tags, replacing the current ones. An empty array removes all tags.

  _Required: no · Position: named_
- **`-StartOnBoot`** `Boolean`
  Whether the container starts when the node boots.

  _Required: no · Position: named_
- **`-Protection`** `Boolean`
  Whether the protection flag is set. While set, PVE refuses to delete the container or its volumes.

  _Required: no · Position: named_
- **`-Parameter`** `Hashtable`
  Further options by their API names, for example @{ timezone = 'host' }. Applied last.

  _Required: no · Position: named_
- **`-Delete`** `String[]`
  Option names to remove from the configuration, so their PVE defaults apply, for example 'cores'.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Container`

**Examples**

```powershell
Set-PVEContainer -VMId 200 -Cores 2 -MemoryGB 1
Get-PVEContainer -Name 'dns*' | Set-PVEContainer -Tags dns, production -StartOnBoot $true
```

[Back to the cmdlet index](#cmdlet-index)

#### Copy-PVEContainer

Clones a container or container template into a new container.

Clones the source with POST /nodes/{node}/lxc/{vmid}/clone, waits for the clone task, and writes the
new container with its live status. The new container is created on the source's node.

From the API documentation: a clone of a normal container is always a full clone (a full copy of every
disk); for a template, PVE tries to make a linked clone by default, whose disks share the template's
base image. -Full asks for a full clone of a template. -Storage applies to full clones.

The source can be named by ID or name (templates included), or piped in. Exactly one source is
cloned per call.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Copy-PVEContainer -VMId <int> -NewName <string> [-NewVMId <int>] [-Full] [-Storage <string>] [-Pool <string>]
    [-Description <string>] [-Snapshot <string>] [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]

# Parameter set: Name
Copy-PVEContainer [-Name] <string> -NewName <string> [-NewVMId <int>] [-Full] [-Storage <string>]
    [-Pool <string>] [-Description <string>] [-Snapshot <string>] [-RunAsync] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String`
  Name of the source container or template.

  _Required: yes · Parameter set: Name · Position: first_
- **`-VMId`** `Int32`
  ID of the source container or template. Binds from a piped PVEPS.Container object.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-NewName`** `String`
  Host name for the new container.

  _Required: yes · Position: named_
- **`-NewVMId`** `Int32`
  ID for the new container. Defaults to the next free ID.

  _Required: no · Position: named · Range: 100 to 999999999_
- **`-Full`** `SwitchParameter`
  Make a full clone of a template instead of a linked clone.

  _Required: no · Position: named_
- **`-Storage`** `String`
  Target storage for a full clone.

  _Required: no · Position: named_
- **`-Pool`** `String`
  Resource pool to add the new container to.

  _Required: no · Position: named_
- **`-Description`** `String`
  Description for the new container.

  _Required: no · Position: named_
- **`-Snapshot`** `String`
  Clone the source as it was at this snapshot.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the clone task at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from a piped object.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Container`, `PVEPS.Task`

**Examples**

```powershell
Copy-PVEContainer tmpl-debian13 -NewName dns02
Copy-PVEContainer -VMId 9100 -NewName dns03 -Full -Storage local-lvm | Start-PVEContainer
```

[Back to the cmdlet index](#cmdlet-index)

#### Move-PVEContainer

Moves the storage of containers to another storage.

Moves each container's volumes (the root file system and mount points backed by a storage volume; bind
mounts and device mounts are left alone) to -Storage, one at a time with POST
/nodes/{node}/lxc/{vmid}/move_volume, waiting for each to finish. Writes each container with its live
status when its moves are done.

By default PVE keeps each source volume after the copy, as an unusedN entry in the configuration;
-DeleteSource deletes it once the copy has succeeded. Whether PVE moves the volumes of a running
container is unverified; if it refuses, the error says so.

Moving guests between nodes needs a cluster and is not covered by this cmdlet yet.

Prompts for confirmation at ConfirmImpact Medium, so not by default.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Move-PVEContainer -VMId <int[]> -Storage <string> [-Volume <string[]>] [-DeleteSource] [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
Move-PVEContainer [-Name] <string[]> -Storage <string> [-IncludeTemplate] [-Volume <string[]>] [-DeleteSource]
    [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-IncludeTemplate`** `SwitchParameter`
  Let -Name match templates as well as containers.

  _Required: no · Parameter set: Name · Position: named_
- **`-Storage`** `String`
  Target storage.

  _Required: yes · Position: named_
- **`-Volume`** `String[]`
  Volumes to move: rootfs and/or mp0, mp1, ... Defaults to every volume not already on -Storage.

  _Required: no · Position: named_
- **`-DeleteSource`** `SwitchParameter`
  Delete each source volume after it has been copied.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Container`

**Examples**

```powershell
Move-PVEContainer -VMId 200 -Storage local-zfs
Move-PVEContainer dns01 -Storage fast-ssd -Volume mp0 -DeleteSource
```

[Back to the cmdlet index](#cmdlet-index)

#### ConvertTo-PVEContainerTemplate

Converts containers into templates.

Converts each container with POST /nodes/{node}/lxc/{vmid}/template and writes it with its live status
(IsTemplate true). A template cannot be started; Copy-PVEContainer makes new containers from it. Treat the
conversion as one-way: this module has no cmdlet that turns a template back into a container.

Prompts for confirmation by default (ConfirmImpact High). A container that is not stopped is an error and is
left alone; stop it first. One that is already a template is skipped with a warning and written
unchanged.

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
ConvertTo-PVEContainerTemplate -VMId <int[]> [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]

# Parameter set: Name
ConvertTo-PVEContainerTemplate [-Name] <string[]> [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-RunAsync`** `SwitchParameter`
  Return the task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Container`, `PVEPS.Task`

**Examples**

```powershell
ConvertTo-PVEContainerTemplate -VMId 9100
Get-PVEContainer -Name 'golden-*' | Stop-PVEContainerGuest -Confirm:$false | ConvertTo-PVEContainerTemplate -Confirm:$false
```

[Back to the cmdlet index](#cmdlet-index)

#### Remove-PVEContainer

Deletes LXC containers and their volumes.

Deletes each container with DELETE /nodes/{node}/lxc/{vmid}, which PVE documents as destroying the
container and all the files it uses. This cannot be undone.

Prompts for confirmation by default (ConfirmImpact High). A container that is not stopped is an error
and is left alone; stop it first. A container with the protection flag set is refused by PVE.

Templates are deleted when named by ID or piped in. A name or wildcard matches templates only with
-IncludeTemplate.

Writes nothing on success (with -RunAsync, the delete tasks).

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Remove-PVEContainer -VMId <int[]> [-Purge] [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]

# Parameter set: Name
Remove-PVEContainer [-Name] <string[]> [-IncludeTemplate] [-Purge] [-RunAsync] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Name`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-IncludeTemplate`** `SwitchParameter`
  Let -Name match templates as well as containers.

  _Required: no · Parameter set: Name · Position: named_
- **`-Purge`** `SwitchParameter`
  Also remove the container from backup jobs, replication jobs and HA. PVE always removes its ACLs and
  firewall entries.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the delete task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Task`

**Examples**

```powershell
Remove-PVEContainer -VMId 205
Get-PVEContainer -Name 'scratch-*' | Stop-PVEContainer -Confirm:$false | Remove-PVEContainer -Purge -Confirm:$false
```

[Back to the cmdlet index](#cmdlet-index)

### VM hardware

#### Get-PVEVMHardDisk

Gets the hard disks of QEMU virtual machines.

Reads each VM's configuration and writes one PVEPS.HardDisk object per ide, sata, scsi or virtio disk
(CD drives are listed by Get-PVEVMCDDrive). The configuration PVE returns has pending changes applied.

Device is the configuration key (for example scsi0); Options holds every option of the entry as PVE
wrote it.

**Syntax**

```text
# Parameter set: Id (default)
Get-PVEVMHardDisk -VMId <int[]> [-Device <string[]>] [-Server <Object[]>] [<CommonParameters>]

# Parameter set: Name
Get-PVEVMHardDisk [-VMName] <string[]> [-Device <string[]>] [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed. Templates are included.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Device`** `String[]`
  Disk(s) to return, for example scsi0 or 'virtio\*'. All disks if omitted.

  _Required: no · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.HardDisk`

**Examples**

```powershell
Get-PVEVM web01 | Get-PVEVMHardDisk
Get-PVEVMHardDisk -VMName '*' | Where-Object Storage -EQ 'local-lvm' | Measure-Object -Property SizeGB -Sum
```

[Back to the cmdlet index](#cmdlet-index)

#### New-PVEVMHardDisk

Adds a hard disk to QEMU virtual machines.

Adds a new disk of -SizeGB GiB on -Storage, or attaches an existing volume given as -Volume (for
example one listed as unusedN after Remove-PVEVMHardDisk), with POST /nodes/{node}/qemu/{vmid}/config.
Writes the new PVEPS.HardDisk object.

The disk goes on the -Bus bus at the lowest free index unless -Index is given. On a running VM, PVE
hot-plugs the disk if the VM's hotplug settings allow it; otherwise the disk is pending until the VM is
next started, and a warning says so.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
New-PVEVMHardDisk -VMId <int[]> [-SizeGB <int>] [-Storage <string>] [-Volume <string>] [-Bus <string>]
    [-Index <int>] [-Format <string>] [-Cache <string>] [-SSD] [-Discard] [-IOThread] [-NoBackup]
    [-Parameter <hashtable>] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
New-PVEVMHardDisk [-VMName] <string[]> [-SizeGB <int>] [-Storage <string>] [-Volume <string>] [-Bus <string>]
    [-Index <int>] [-Format <string>] [-Cache <string>] [-SSD] [-Discard] [-IOThread] [-NoBackup]
    [-Parameter <hashtable>] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-SizeGB`** `Int32`
  Size of the new disk in GiB. Needs -Storage.

  _Required: no · Position: named · Range: 1 to 2147483647_
- **`-Storage`** `String`
  Storage for the new disk.

  _Required: no · Position: named_
- **`-Volume`** `String`
  An existing volume to attach instead of creating a disk, for example local-lvm:vm-100-disk-3.

  _Required: no · Position: named_
- **`-Bus`** `String`
  scsi (the default), virtio, sata or ide.

  _Required: no · Position: named · Values: scsi, virtio, sata, ide · Default: 'scsi'_
- **`-Index`** `Int32`
  Index on the bus, for example 2 for scsi2. Defaults to the lowest free index.

  _Required: no · Position: named · Range: 0 to 30_
- **`-Format`** `String`
  Disk format on file-based storage: raw, qcow2 or vmdk.

  _Required: no · Position: named · Values: raw, qcow2, vmdk_
- **`-Cache`** `String`
  Cache mode: none, writethrough, writeback, unsafe or directsync.

  _Required: no · Position: named · Values: none, writethrough, writeback, unsafe, directsync_
- **`-SSD`** `SwitchParameter`
  Present the disk to the guest as an SSD.

  _Required: no · Position: named_
- **`-Discard`** `SwitchParameter`
  Pass discard/TRIM requests from the guest to the storage.

  _Required: no · Position: named_
- **`-IOThread`** `SwitchParameter`
  Give the disk its own I/O thread.

  _Required: no · Position: named_
- **`-NoBackup`** `SwitchParameter`
  Leave the disk out of backups (backup=0).

  _Required: no · Position: named_
- **`-Parameter`** `Hashtable`
  Further drive options by their API names, for example @{ iops_rd = 500 }.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.HardDisk`

**Examples**

```powershell
New-PVEVMHardDisk -VMId 100 -SizeGB 50 -Storage local-lvm -SSD -Discard
Get-PVEVM db01 | New-PVEVMHardDisk -SizeGB 200 -Storage bulk -Bus virtio -IOThread
```

[Back to the cmdlet index](#cmdlet-index)

#### Set-PVEVMHardDisk

Grows QEMU hard disks or changes their options.

-SizeGB grows the disk with PUT /nodes/{node}/qemu/{vmid}/resize. PVE does not shrink disks, so a
size below the current one is an error and nothing is sent; the current size is skipped with a warning.
Growing the disk does not grow the partitions or file systems inside the guest.

The other parameters rewrite the disk's entry with POST .../config, keeping every option not named.
On a running VM some option changes are pending until the next start, and a warning says so.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Set-PVEVMHardDisk -VMId <int[]> -Device <string[]> [-SizeGB <double>] [-Cache <string>] [-SSD <bool>]
    [-Discard <bool>] [-IOThread <bool>] [-Backup <bool>] [-Parameter <hashtable>] [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
Set-PVEVMHardDisk [-VMName] <string[]> -Device <string[]> [-SizeGB <double>] [-Cache <string>] [-SSD <bool>]
    [-Discard <bool>] [-IOThread <bool>] [-Backup <bool>] [-Parameter <hashtable>] [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID. Binds from piped PVEPS.HardDisk or PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Device`** `String[]`
  Disk(s) to change, for example scsi0. Binds from piped PVEPS.HardDisk objects.

  _Required: yes · Position: named · Pipeline: by property name_
- **`-SizeGB`** `Double`
  New size in GiB, larger than the current size. Fractions are allowed (the API accepts them).

  _Required: no · Position: named · Range: 0.001 to 1.7976931348623157E+308_
- **`-Cache`** `String`
  Cache mode: none, writethrough, writeback, unsafe or directsync.

  _Required: no · Position: named · Values: none, writethrough, writeback, unsafe, directsync_
- **`-SSD`** `Boolean`
  Whether the disk is presented to the guest as an SSD.

  _Required: no · Position: named_
- **`-Discard`** `Boolean`
  Whether discard/TRIM requests are passed to the storage.

  _Required: no · Position: named_
- **`-IOThread`** `Boolean`
  Whether the disk has its own I/O thread.

  _Required: no · Position: named_
- **`-Backup`** `Boolean`
  Whether the disk is included in backups.

  _Required: no · Position: named_
- **`-Parameter`** `Hashtable`
  Further drive options by their API names. A $null value removes the option, for example
  @{ iops_rd = $null }.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.HardDisk`

**Examples**

```powershell
Set-PVEVMHardDisk -VMId 100 -Device scsi0 -SizeGB 64
Get-PVEVM db* | Get-PVEVMHardDisk -Device scsi1 | Set-PVEVMHardDisk -Discard $true -SSD $true
```

[Back to the cmdlet index](#cmdlet-index)

#### Remove-PVEVMHardDisk

Detaches hard disks from QEMU virtual machines, or deletes them.

By default the disk is detached with POST /nodes/{node}/qemu/{vmid}/config (delete=&lt;disk&gt;): PVE removes
it from the VM and keeps the volume as an unusedN entry, so its data survives and New-PVEVMHardDisk
-Volume can attach it again. -DeletePermanently also sends force=1, which the API documents as forcing
physical removal of the volume. That cannot be undone.

Prompts for confirmation by default (ConfirmImpact High). On a running VM, PVE hot-unplugs the disk if
it can; otherwise the removal is pending until the next start, and a warning says so. Writes nothing.

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Remove-PVEVMHardDisk -VMId <int[]> -Device <string[]> [-DeletePermanently] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]

# Parameter set: Name
Remove-PVEVMHardDisk [-VMName] <string[]> -Device <string[]> [-DeletePermanently] [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID. Binds from piped PVEPS.HardDisk objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Device`** `String[]`
  Disk(s) to remove, for example scsi1. Binds from piped PVEPS.HardDisk objects.

  _Required: yes · Position: named · Pipeline: by property name_
- **`-DeletePermanently`** `SwitchParameter`
  Delete the volume instead of keeping it as an unused disk.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `System.Void`

**Examples**

```powershell
Remove-PVEVMHardDisk -VMId 100 -Device scsi1
Get-PVEVMHardDisk -VMId 100 -Device scsi2 | Remove-PVEVMHardDisk -DeletePermanently -Confirm:$false
```

[Back to the cmdlet index](#cmdlet-index)

#### Get-PVEVMNetworkAdapter

Gets the network adapters of QEMU virtual machines.

Reads each VM's configuration and writes one PVEPS.VMNetworkAdapter object per netN entry. The
configuration PVE returns has pending changes applied.

Device is the configuration key (for example net0); Options holds every option of the entry.

**Syntax**

```text
# Parameter set: Id (default)
Get-PVEVMNetworkAdapter -VMId <int[]> [-Device <string[]>] [-Server <Object[]>] [<CommonParameters>]

# Parameter set: Name
Get-PVEVMNetworkAdapter [-VMName] <string[]> [-Device <string[]>] [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed. Templates are included.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Device`** `String[]`
  Adapter(s) to return, for example net0. All adapters if omitted.

  _Required: no · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VMNetworkAdapter`

**Examples**

```powershell
Get-PVEVM web01 | Get-PVEVMNetworkAdapter
Get-PVEVMNetworkAdapter -VMName '*' | Where-Object Bridge -EQ 'vmbr1'
```

[Back to the cmdlet index](#cmdlet-index)

#### New-PVEVMNetworkAdapter

Adds a network adapter to QEMU virtual machines.

Adds a netN entry at the lowest free index (or -Index) with POST /nodes/{node}/qemu/{vmid}/config, and
writes the new PVEPS.VMNetworkAdapter object. PVE generates the MAC address unless -MacAddress is
given. On a running VM, PVE hot-plugs the adapter if the VM's hotplug settings allow it; otherwise it
is pending until the next start, and a warning says so.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
New-PVEVMNetworkAdapter -VMId <int[]> -Bridge <string> [-Model <string>] [-MacAddress <string>]
    [-VlanTag <int>] [-Firewall] [-Disconnected] [-Mtu <int>] [-Queues <int>] [-RateLimitMBps <double>]
    [-Index <int>] [-Parameter <hashtable>] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
New-PVEVMNetworkAdapter [-VMName] <string[]> -Bridge <string> [-Model <string>] [-MacAddress <string>]
    [-VlanTag <int>] [-Firewall] [-Disconnected] [-Mtu <int>] [-Queues <int>] [-RateLimitMBps <double>]
    [-Index <int>] [-Parameter <hashtable>] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Bridge`** `String`
  Bridge to connect the adapter to, for example vmbr0.

  _Required: yes · Position: named_
- **`-Model`** `String`
  Adapter model. Defaults to virtio.

  _Required: no · Position: named · Values: e1000, e1000-82540em, e1000-82544gc, e1000-82545em, e1000e, i82551, i82557b, i82559er, ne2k_isa, ne2k_pci, pcnet, rtl8139, virtio, vmxnet3 · Default: 'virtio'_
- **`-MacAddress`** `String`
  MAC address, for example BC:24:11:12:34:56. Generated by PVE if omitted.

  _Required: no · Position: named_
- **`-VlanTag`** `Int32`
  VLAN tag for the adapter's traffic (1 to 4094).

  _Required: no · Position: named · Range: 1 to 4094_
- **`-Firewall`** `SwitchParameter`
  Enable the PVE firewall on this adapter.

  _Required: no · Position: named_
- **`-Disconnected`** `SwitchParameter`
  Add the adapter with its link down (unplugged).

  _Required: no · Position: named_
- **`-Mtu`** `Int32`
  MTU (VirtIO only). 1 uses the bridge's MTU.

  _Required: no · Position: named · Range: 1 to 65520_
- **`-Queues`** `Int32`
  Number of packet queues.

  _Required: no · Position: named · Range: 0 to 64_
- **`-RateLimitMBps`** `Double`
  Rate limit in megabytes per second.

  _Required: no · Position: named · Range: 0 to 1.7976931348623157E+308_
- **`-Index`** `Int32`
  Index of the adapter, for example 1 for net1. Defaults to the lowest free index.

  _Required: no · Position: named · Range: 0 to 2147483647_
- **`-Parameter`** `Hashtable`
  Further adapter options by their API names.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VMNetworkAdapter`

**Examples**

```powershell
New-PVEVMNetworkAdapter -VMId 100 -Bridge vmbr0 -VlanTag 20
Get-PVEVM 'router*' | New-PVEVMNetworkAdapter -Bridge vmbr1 -Firewall
```

[Back to the cmdlet index](#cmdlet-index)

#### Set-PVEVMNetworkAdapter

Changes QEMU network adapters: bridge, VLAN, link state, model, MAC and other options.

Rewrites each adapter's netN entry with POST /nodes/{node}/qemu/{vmid}/config, keeping every option not
named (changing -Model keeps the MAC address). Writes each adapter as now configured. On a running VM
some changes are pending until the next start, and a warning says so.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Set-PVEVMNetworkAdapter -VMId <int[]> -Device <string[]> [-Bridge <string>] [-Model <string>]
    [-MacAddress <string>] [-VlanTag <int>] [-Connected <bool>] [-Firewall <bool>] [-Mtu <int>]
    [-Queues <int>] [-RateLimitMBps <double>] [-Parameter <hashtable>] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]

# Parameter set: Name
Set-PVEVMNetworkAdapter [-VMName] <string[]> -Device <string[]> [-Bridge <string>] [-Model <string>]
    [-MacAddress <string>] [-VlanTag <int>] [-Connected <bool>] [-Firewall <bool>] [-Mtu <int>]
    [-Queues <int>] [-RateLimitMBps <double>] [-Parameter <hashtable>] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID. Binds from piped PVEPS.VMNetworkAdapter or PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Device`** `String[]`
  Adapter(s) to change, for example net0. Binds from piped PVEPS.VMNetworkAdapter objects.

  _Required: yes · Position: named · Pipeline: by property name_
- **`-Bridge`** `String`
  Bridge to connect the adapter to.

  _Required: no · Position: named_
- **`-Model`** `String`
  Adapter model.

  _Required: no · Position: named · Values: e1000, e1000-82540em, e1000-82544gc, e1000-82545em, e1000e, i82551, i82557b, i82559er, ne2k_isa, ne2k_pci, pcnet, rtl8139, virtio, vmxnet3_
- **`-MacAddress`** `String`
  MAC address.

  _Required: no · Position: named_
- **`-VlanTag`** `Int32`
  VLAN tag (1 to 4094); 0 removes the tag.

  _Required: no · Position: named · Range: 0 to 4094_
- **`-Connected`** `Boolean`
  $false takes the link down (unplugs the adapter); $true brings it up.

  _Required: no · Position: named_
- **`-Firewall`** `Boolean`
  Whether the PVE firewall applies to this adapter.

  _Required: no · Position: named_
- **`-Mtu`** `Int32`
  MTU (VirtIO only); 0 removes the setting.

  _Required: no · Position: named · Range: 0 to 65520_
- **`-Queues`** `Int32`
  Number of packet queues; 0 removes the setting.

  _Required: no · Position: named · Range: 0 to 64_
- **`-RateLimitMBps`** `Double`
  Rate limit in megabytes per second; 0 removes the limit.

  _Required: no · Position: named · Range: 0 to 1.7976931348623157E+308_
- **`-Parameter`** `Hashtable`
  Further adapter options by their API names; a $null value removes the option.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VMNetworkAdapter`

**Examples**

```powershell
Set-PVEVMNetworkAdapter -VMId 100 -Device net0 -VlanTag 30
Get-PVEVM lab* | Get-PVEVMNetworkAdapter -Device net1 | Set-PVEVMNetworkAdapter -Connected $false
```

[Back to the cmdlet index](#cmdlet-index)

#### Remove-PVEVMNetworkAdapter

Removes network adapters from QEMU virtual machines.

Removes each netN entry with POST /nodes/{node}/qemu/{vmid}/config (delete=netN). Its MAC address is
lost with it. Prompts for confirmation by default (ConfirmImpact High). On a running VM, PVE hot-unplugs
the adapter if it can; otherwise the removal is pending until the next start, and a warning says so.
Writes nothing.

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Remove-PVEVMNetworkAdapter -VMId <int[]> -Device <string[]> [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]

# Parameter set: Name
Remove-PVEVMNetworkAdapter [-VMName] <string[]> -Device <string[]> [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID. Binds from piped PVEPS.VMNetworkAdapter objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Device`** `String[]`
  Adapter(s) to remove, for example net1. Binds from piped PVEPS.VMNetworkAdapter objects.

  _Required: yes · Position: named · Pipeline: by property name_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `System.Void`

**Examples**

```powershell
Remove-PVEVMNetworkAdapter -VMId 100 -Device net1
```

[Back to the cmdlet index](#cmdlet-index)

#### Get-PVEVMCDDrive

Gets the CD drives of QEMU virtual machines.

Reads each VM's configuration and writes one PVEPS.CDDrive object per drive with media=cdrom.
Cloud-init drives are left out (see Get-PVEVMCloudInit). IsoImage is the inserted ISO, or $null for an
empty drive.

**Syntax**

```text
# Parameter set: Id (default)
Get-PVEVMCDDrive -VMId <int[]> [-Device <string[]>] [-Server <Object[]>] [<CommonParameters>]

# Parameter set: Name
Get-PVEVMCDDrive [-VMName] <string[]> [-Device <string[]>] [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed. Templates are included.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Device`** `String[]`
  Drive(s) to return, for example ide2. All CD drives if omitted.

  _Required: no · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.CDDrive`

**Examples**

```powershell
Get-PVEVM web01 | Get-PVEVMCDDrive
Get-PVEVMCDDrive -VMName '*' | Where-Object IsoImage
```

[Back to the cmdlet index](#cmdlet-index)

#### New-PVEVMCDDrive

Adds a CD drive to QEMU virtual machines, empty or with an ISO.

Adds a drive with media=cdrom on the -Bus bus at the lowest free index (or -Index), with POST
/nodes/{node}/qemu/{vmid}/config, and writes the new PVEPS.CDDrive object.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
New-PVEVMCDDrive -VMId <int[]> [-IsoImage <string>] [-Bus <string>] [-Index <int>] [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
New-PVEVMCDDrive [-VMName] <string[]> [-IsoImage <string>] [-Bus <string>] [-Index <int>] [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-IsoImage`** `String`
  ISO volume to insert, for example local:iso/debian-13.1.0-amd64-netinst.iso. The drive is empty if
  omitted.

  _Required: no · Position: named_
- **`-Bus`** `String`
  ide (the default), sata or scsi.

  _Required: no · Position: named · Values: ide, sata, scsi · Default: 'ide'_
- **`-Index`** `Int32`
  Index on the bus, for example 2 for ide2. Defaults to the lowest free index.

  _Required: no · Position: named · Range: 0 to 30_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.CDDrive`

**Examples**

```powershell
New-PVEVMCDDrive -VMId 100 -IsoImage local:iso/virtio-win.iso
```

[Back to the cmdlet index](#cmdlet-index)

#### Set-PVEVMCDDrive

Inserts an ISO into, or ejects the media from, QEMU CD drives.

Rewrites each drive's entry with POST /nodes/{node}/qemu/{vmid}/config, keeping its other options, and
writes the drive as now configured.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: IdIso (default)
Set-PVEVMCDDrive -VMId <int[]> -Device <string[]> -IsoImage <string> [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]

# Parameter set: IdEject
Set-PVEVMCDDrive -VMId <int[]> -Device <string[]> -NoMedia [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]

# Parameter set: NameEject
Set-PVEVMCDDrive [-VMName] <string[]> -Device <string[]> -NoMedia [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]

# Parameter set: NameIso
Set-PVEVMCDDrive [-VMName] <string[]> -Device <string[]> -IsoImage <string> [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID. Binds from piped PVEPS.CDDrive or PVEPS.VM objects.

  _Required: yes · Parameter sets: IdEject, IdIso · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter sets: NameEject, NameIso · Position: first · Wildcards: yes_
- **`-Device`** `String[]`
  Drive(s) to change, for example ide2. Binds from piped PVEPS.CDDrive objects.

  _Required: yes · Position: named · Pipeline: by property name_
- **`-IsoImage`** `String`
  ISO volume to insert, for example local:iso/debian-13.1.0-amd64-netinst.iso.

  _Required: yes · Parameter sets: NameIso, IdIso · Position: named_
- **`-NoMedia`** `SwitchParameter`
  Eject the media, leaving the drive empty.

  _Required: yes · Parameter sets: NameEject, IdEject · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.CDDrive`

**Examples**

```powershell
Set-PVEVMCDDrive -VMId 100 -Device ide2 -IsoImage local:iso/virtio-win.iso
Get-PVEVMCDDrive -VMName '*' | Where-Object IsoImage | Set-PVEVMCDDrive -NoMedia
```

[Back to the cmdlet index](#cmdlet-index)

#### Remove-PVEVMCDDrive

Removes CD drives from QEMU virtual machines.

Removes each drive entry with POST /nodes/{node}/qemu/{vmid}/config (delete=&lt;drive&gt;). The ISO itself is
not touched. To keep the drive and only take the ISO out, use Set-PVEVMCDDrive -NoMedia. On a running
VM the removal can be pending until the next start, and a warning says so. Writes nothing.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Remove-PVEVMCDDrive -VMId <int[]> -Device <string[]> [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]

# Parameter set: Name
Remove-PVEVMCDDrive [-VMName] <string[]> -Device <string[]> [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID. Binds from piped PVEPS.CDDrive objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Device`** `String[]`
  Drive(s) to remove, for example ide2. Binds from piped PVEPS.CDDrive objects.

  _Required: yes · Position: named · Pipeline: by property name_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `System.Void`

**Examples**

```powershell
Remove-PVEVMCDDrive -VMId 100 -Device ide2
```

[Back to the cmdlet index](#cmdlet-index)

#### Get-PVEVMCloudInit

Gets the cloud-init settings of QEMU virtual machines.

Writes one PVEPS.CloudInit object per VM: the cloud-init drive (if any), user, whether a password is
set, SSH keys, per-adapter IP configuration, DNS settings, and IsPending, which says whether the drive
still holds older settings than the configuration.

**Syntax**

```text
# Parameter set: Id (default)
Get-PVEVMCloudInit -VMId <int[]> [-Server <Object[]>] [<CommonParameters>]

# Parameter set: Name
Get-PVEVMCloudInit [-VMName] <string[]> [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed. Templates are included.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.CloudInit`

**Examples**

```powershell
Get-PVEVM web01 | Get-PVEVMCloudInit
(Get-PVEVMCloudInit -VMId 100).IPConfig
```

[Back to the cmdlet index](#cmdlet-index)

#### Set-PVEVMCloudInit

Changes the cloud-init settings of QEMU virtual machines, and adds a cloud-init drive if needed.

Sends the settings with POST /nodes/{node}/qemu/{vmid}/config and writes the VM's PVEPS.CloudInit
object. Only the settings given are changed. An empty value ('' or @()) removes a setting.

The IP settings apply to one network adapter, -NetworkIndex (net0 by default), and are merged with
that adapter's current ipconfigN: -Gateway alone keeps the current address.

cloud-init needs a cloud-init drive. With -Storage, a VM without one gets one (on -DriveBus, at the
lowest free index); without -Storage, such a VM gets a warning, because the settings are saved but
unused until a drive is added. -Regenerate rewrites the drive's contents at once
(PUT /nodes/{node}/qemu/{vmid}/cloudinit); Get-PVEVMCloudInit shows in IsPending whether the drive is
out of date.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Set-PVEVMCloudInit -VMId <int[]> [-User <string>] [-Password <Object>] [-SshPublicKey <string[]>]
    [-NetworkIndex <int>] [-IPAddress <string>] [-Gateway <string>] [-IPv6Address <string>]
    [-Gateway6 <string>] [-Nameserver <string[]>] [-SearchDomain <string[]>] [-Upgrade <bool>]
    [-Type <string>] [-Storage <string>] [-DriveBus <string>] [-Regenerate] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]

# Parameter set: Name
Set-PVEVMCloudInit [-VMName] <string[]> [-User <string>] [-Password <Object>] [-SshPublicKey <string[]>]
    [-NetworkIndex <int>] [-IPAddress <string>] [-Gateway <string>] [-IPv6Address <string>]
    [-Gateway6 <string>] [-Nameserver <string[]>] [-SearchDomain <string[]>] [-Upgrade <bool>]
    [-Type <string>] [-Storage <string>] [-DriveBus <string>] [-Regenerate] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-User`** `String`
  User whose password and SSH keys cloud-init sets, instead of the image's default user.

  _Required: no · Position: named_
- **`-Password`** `Object`
  Password for that user. Accepts a string or a SecureString. The API documentation advises SSH keys
  instead, and notes that older cloud-init versions do not support hashed passwords.

  _Required: no · Position: named_
- **`-SshPublicKey`** `String[]`
  Public SSH keys (OpenSSH format), one per element. Replaces the current keys.

  _Required: no · Position: named_
- **`-NetworkIndex`** `Int32`
  Index of the network adapter the IP settings are for. Defaults to 0 (net0).

  _Required: no · Position: named · Range: 0 to 2147483647 · Default: 0_
- **`-IPAddress`** `String`
  IPv4 address in CIDR notation (192.0.2.10/24), or dhcp.

  _Required: no · Position: named_
- **`-Gateway`** `String`
  IPv4 gateway.

  _Required: no · Position: named_
- **`-IPv6Address`** `String`
  IPv6 address in CIDR notation, dhcp, or auto (stateless autoconfiguration; needs cloud-init 19.4 or
  newer according to the API documentation).

  _Required: no · Position: named_
- **`-Gateway6`** `String`
  IPv6 gateway.

  _Required: no · Position: named_
- **`-Nameserver`** `String[]`
  DNS server addresses.

  _Required: no · Position: named_
- **`-SearchDomain`** `String[]`
  DNS search domains.

  _Required: no · Position: named_
- **`-Upgrade`** `Boolean`
  Whether cloud-init upgrades packages after the first boot.

  _Required: no · Position: named_
- **`-Type`** `String`
  cloud-init data format: nocloud, configdrive2 or opennebula. By default PVE picks it from the OS type.

  _Required: no · Position: named · Values: nocloud, configdrive2, opennebula_
- **`-Storage`** `String`
  Storage for a cloud-init drive, added if the VM has none.

  _Required: no · Position: named_
- **`-DriveBus`** `String`
  Bus for an added cloud-init drive: ide (the default), sata or scsi.

  _Required: no · Position: named · Values: ide, sata, scsi · Default: 'ide'_
- **`-Regenerate`** `SwitchParameter`
  Rewrite the cloud-init drive's contents after the change.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.CloudInit`

**Examples**

```powershell
Set-PVEVMCloudInit -VMId 100 -User debian -SshPublicKey (Get-Content ~/.ssh/id_ed25519.pub) -IPAddress dhcp -Storage local-lvm
Set-PVEVMCloudInit -VMId 100 -IPAddress 192.0.2.10/24 -Gateway 192.0.2.1 -Nameserver 192.0.2.53 -Regenerate
```

[Back to the cmdlet index](#cmdlet-index)

### Container hardware

#### Get-PVEContainerVolume

Gets the root file system and mount points of LXC containers.

Reads each container's configuration and writes one PVEPS.ContainerVolume object for rootfs and one
per mpN mount point, including bind mounts (IsBindMount). The configuration PVE returns has pending
changes applied.

**Syntax**

```text
# Parameter set: Id (default)
Get-PVEContainerVolume -VMId <int[]> [-Device <string[]>] [-Server <Object[]>] [<CommonParameters>]

# Parameter set: Name
Get-PVEContainerVolume [-VMName] <string[]> [-Device <string[]>] [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  Container name(s). Wildcards allowed. Templates are included.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Device`** `String[]`
  Volume(s) to return: rootfs, mp0, 'mp\*' and so on. All if omitted.

  _Required: no · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.ContainerVolume`

**Examples**

```powershell
Get-PVEContainer dns01 | Get-PVEContainerVolume
Get-PVEContainerVolume -VMName '*' -Device rootfs | Sort-Object SizeGB
```

[Back to the cmdlet index](#cmdlet-index)

#### New-PVEContainerVolume

Adds a mount point to LXC containers: a new volume, or a bind mount of a host directory.

Adds an mpN entry at the lowest free index (or -Index) with PUT /nodes/{node}/lxc/{vmid}/config, and
writes the new PVEPS.ContainerVolume object. -SizeGB with -Storage creates a new volume; -HostPath
bind-mounts a directory of the host. The API documentation restricts mount points that are not storage
volumes (bind mounts) to root@pam.

On a running container the mount point can be pending until the next start, and a warning says so.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
New-PVEContainerVolume -VMId <int[]> -Path <string> [-SizeGB <int>] [-Storage <string>] [-HostPath <string>]
    [-ReadOnly] [-Backup] [-Index <int>] [-Parameter <hashtable>] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]

# Parameter set: Name
New-PVEContainerVolume [-VMName] <string[]> -Path <string> [-SizeGB <int>] [-Storage <string>]
    [-HostPath <string>] [-ReadOnly] [-Backup] [-Index <int>] [-Parameter <hashtable>] [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Path`** `String`
  Mount path inside the container, for example /srv/data.

  _Required: yes · Position: named_
- **`-SizeGB`** `Int32`
  Size of the new volume in GiB. Needs -Storage.

  _Required: no · Position: named · Range: 1 to 2147483647_
- **`-Storage`** `String`
  Storage for the new volume.

  _Required: no · Position: named_
- **`-HostPath`** `String`
  Host directory to bind-mount instead of creating a volume.

  _Required: no · Position: named_
- **`-ReadOnly`** `SwitchParameter`
  Mount read-only.

  _Required: no · Position: named_
- **`-Backup`** `SwitchParameter`
  Include the mount point in backups. The API documentation says this applies only to volume mount
  points.

  _Required: no · Position: named_
- **`-Index`** `Int32`
  Index of the mount point, for example 1 for mp1. Defaults to the lowest free index.

  _Required: no · Position: named · Range: 0 to 255_
- **`-Parameter`** `Hashtable`
  Further mount point options by their API names, for example @{ mountoptions = 'noatime' }.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.ContainerVolume`

**Examples**

```powershell
New-PVEContainerVolume -VMId 200 -Path /srv/data -SizeGB 20 -Storage local-lvm -Backup
New-PVEContainerVolume -VMId 200 -Path /mnt/media -HostPath /tank/media -ReadOnly
```

[Back to the cmdlet index](#cmdlet-index)

#### Set-PVEContainerVolume

Grows LXC container volumes or changes their mount options.

-SizeGB grows the root file system or a mount point volume with PUT /nodes/{node}/lxc/{vmid}/resize.
PVE does not shrink volumes, so a size below the current one is an error and nothing is sent; the
current size is skipped with a warning.

The other parameters rewrite the entry with PUT .../config, keeping every option not named.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Set-PVEContainerVolume -VMId <int[]> -Device <string[]> [-SizeGB <double>] [-Path <string>] [-ReadOnly <bool>]
    [-Backup <bool>] [-Parameter <hashtable>] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
Set-PVEContainerVolume [-VMName] <string[]> -Device <string[]> [-SizeGB <double>] [-Path <string>]
    [-ReadOnly <bool>] [-Backup <bool>] [-Parameter <hashtable>] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  Container ID. Binds from piped PVEPS.ContainerVolume or PVEPS.Container objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Device`** `String[]`
  Volume(s) to change: rootfs or mpN. Binds from piped PVEPS.ContainerVolume objects.

  _Required: yes · Position: named · Pipeline: by property name_
- **`-SizeGB`** `Double`
  New size in GiB, larger than the current size. Fractions are allowed (the API accepts them).

  _Required: no · Position: named · Range: 0.001 to 1.7976931348623157E+308_
- **`-Path`** `String`
  New mount path inside the container (mount points only).

  _Required: no · Position: named_
- **`-ReadOnly`** `Boolean`
  Whether the volume is mounted read-only.

  _Required: no · Position: named_
- **`-Backup`** `Boolean`
  Whether the mount point is included in backups.

  _Required: no · Position: named_
- **`-Parameter`** `Hashtable`
  Further options by their API names; a $null value removes the option.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.ContainerVolume`

**Examples**

```powershell
Set-PVEContainerVolume -VMId 200 -Device rootfs -SizeGB 16
Get-PVEContainerVolume -VMId 200 -Device mp0 | Set-PVEContainerVolume -Backup $true
```

[Back to the cmdlet index](#cmdlet-index)

#### Remove-PVEContainerVolume

Detaches mount points from LXC containers, or deletes their volumes.

By default the mount point is removed with PUT /nodes/{node}/lxc/{vmid}/config (delete=mpN). For a
volume mount point PVE keeps the volume as an unusedN entry, so its data survives. -DeletePermanently
then deletes that unusedN entry as well, to delete the volume; that cannot be undone. (For VMs the API
documents that removing an unusedN entry always removes the volume physically; for containers this is
unverified until the lifecycle integration test checks the storage content.) A bind mount has no
volume; removing it only removes the entry.

The root file system cannot be removed. Prompts for confirmation by default (ConfirmImpact High). On a
running container the removal can be pending until the next start; a warning says so, and
-DeletePermanently then cannot find the unused entry until the container has restarted. Writes nothing.

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Remove-PVEContainerVolume -VMId <int[]> -Device <string[]> [-DeletePermanently] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]

# Parameter set: Name
Remove-PVEContainerVolume [-VMName] <string[]> -Device <string[]> [-DeletePermanently] [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  Container ID. Binds from piped PVEPS.ContainerVolume objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Device`** `String[]`
  Mount point(s) to remove, for example mp1. Binds from piped PVEPS.ContainerVolume objects.

  _Required: yes · Position: named · Pipeline: by property name_
- **`-DeletePermanently`** `SwitchParameter`
  Delete the volume instead of keeping it as an unused entry.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `System.Void`

**Examples**

```powershell
Remove-PVEContainerVolume -VMId 200 -Device mp1
Get-PVEContainerVolume -VMId 200 -Device mp2 | Remove-PVEContainerVolume -DeletePermanently -Confirm:$false
```

[Back to the cmdlet index](#cmdlet-index)

#### Get-PVEContainerNetworkAdapter

Gets the network adapters of LXC containers.

Reads each container's configuration and writes one PVEPS.ContainerNetworkAdapter object per netN
entry, with the interface name, bridge, MAC and IP settings. The configuration PVE returns has pending
changes applied.

**Syntax**

```text
# Parameter set: Id (default)
Get-PVEContainerNetworkAdapter -VMId <int[]> [-Device <string[]>] [-Server <Object[]>] [<CommonParameters>]

# Parameter set: Name
Get-PVEContainerNetworkAdapter [-VMName] <string[]> [-Device <string[]>] [-Server <Object[]>]
    [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  Container name(s). Wildcards allowed. Templates are included.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Device`** `String[]`
  Adapter(s) to return, for example net0. All adapters if omitted.

  _Required: no · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.ContainerNetworkAdapter`

**Examples**

```powershell
Get-PVEContainer dns01 | Get-PVEContainerNetworkAdapter
Get-PVEContainerNetworkAdapter -VMName '*' | Select-Object VMName, InterfaceName, IPAddress
```

[Back to the cmdlet index](#cmdlet-index)

#### New-PVEContainerNetworkAdapter

Adds a network adapter to LXC containers.

Adds a netN entry at the lowest free index (or -Index) with PUT /nodes/{node}/lxc/{vmid}/config, and
writes the new PVEPS.ContainerNetworkAdapter object. The interface inside the container is named
eth&lt;index&gt; unless -InterfaceName is given; it gets its IPv4 address by DHCP unless -IPAddress is given.
PVE generates the MAC address unless -MacAddress is given.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
New-PVEContainerNetworkAdapter -VMId <int[]> -Bridge <string> [-InterfaceName <string>] [-IPAddress <string>]
    [-Gateway <string>] [-IPv6Address <string>] [-Gateway6 <string>] [-VlanTag <int>] [-Firewall]
    [-MacAddress <string>] [-Mtu <int>] [-RateLimitMBps <double>] [-Disconnected] [-Index <int>]
    [-Parameter <hashtable>] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
New-PVEContainerNetworkAdapter [-VMName] <string[]> -Bridge <string> [-InterfaceName <string>]
    [-IPAddress <string>] [-Gateway <string>] [-IPv6Address <string>] [-Gateway6 <string>] [-VlanTag <int>]
    [-Firewall] [-MacAddress <string>] [-Mtu <int>] [-RateLimitMBps <double>] [-Disconnected] [-Index <int>]
    [-Parameter <hashtable>] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Bridge`** `String`
  Bridge to connect the adapter to, for example vmbr0.

  _Required: yes · Position: named_
- **`-InterfaceName`** `String`
  Interface name inside the container. Defaults to eth&lt;index&gt;.

  _Required: no · Position: named_
- **`-IPAddress`** `String`
  IPv4 address in CIDR notation (192.0.2.10/24), dhcp, or manual. Defaults to dhcp.

  _Required: no · Position: named · Default: 'dhcp'_
- **`-Gateway`** `String`
  IPv4 gateway.

  _Required: no · Position: named_
- **`-IPv6Address`** `String`
  IPv6 address in CIDR notation, auto, dhcp, or manual.

  _Required: no · Position: named_
- **`-Gateway6`** `String`
  IPv6 gateway.

  _Required: no · Position: named_
- **`-VlanTag`** `Int32`
  VLAN tag (1 to 4094).

  _Required: no · Position: named · Range: 1 to 4094_
- **`-Firewall`** `SwitchParameter`
  Enable the PVE firewall on this adapter.

  _Required: no · Position: named_
- **`-MacAddress`** `String`
  MAC address, for example BC:24:11:12:34:56.

  _Required: no · Position: named_
- **`-Mtu`** `Int32`
  MTU of the interface.

  _Required: no · Position: named · Range: 1 to 65535_
- **`-RateLimitMBps`** `Double`
  Rate limit in megabytes per second.

  _Required: no · Position: named · Range: 0 to 1.7976931348623157E+308_
- **`-Disconnected`** `SwitchParameter`
  Add the adapter with its link down.

  _Required: no · Position: named_
- **`-Index`** `Int32`
  Index of the adapter, for example 1 for net1. Defaults to the lowest free index.

  _Required: no · Position: named · Range: 0 to 2147483647_
- **`-Parameter`** `Hashtable`
  Further adapter options by their API names.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.ContainerNetworkAdapter`

**Examples**

```powershell
New-PVEContainerNetworkAdapter -VMId 200 -Bridge vmbr1 -IPAddress 198.51.100.5/24
```

[Back to the cmdlet index](#cmdlet-index)

#### Set-PVEContainerNetworkAdapter

Changes LXC container network adapters: bridge, addresses, VLAN, link state and other options.

Rewrites each adapter's netN entry with PUT /nodes/{node}/lxc/{vmid}/config, keeping every option not
named, and writes the adapter as now configured. An empty string removes an address or gateway.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Set-PVEContainerNetworkAdapter -VMId <int[]> -Device <string[]> [-Bridge <string>] [-InterfaceName <string>]
    [-IPAddress <string>] [-Gateway <string>] [-IPv6Address <string>] [-Gateway6 <string>] [-VlanTag <int>]
    [-Connected <bool>] [-Firewall <bool>] [-MacAddress <string>] [-Mtu <int>] [-RateLimitMBps <double>]
    [-Parameter <hashtable>] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
Set-PVEContainerNetworkAdapter [-VMName] <string[]> -Device <string[]> [-Bridge <string>]
    [-InterfaceName <string>] [-IPAddress <string>] [-Gateway <string>] [-IPv6Address <string>]
    [-Gateway6 <string>] [-VlanTag <int>] [-Connected <bool>] [-Firewall <bool>] [-MacAddress <string>]
    [-Mtu <int>] [-RateLimitMBps <double>] [-Parameter <hashtable>] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  Container ID. Binds from piped PVEPS.ContainerNetworkAdapter or PVEPS.Container objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Device`** `String[]`
  Adapter(s) to change, for example net0. Binds from piped PVEPS.ContainerNetworkAdapter objects.

  _Required: yes · Position: named · Pipeline: by property name_
- **`-Bridge`** `String`
  Bridge to connect the adapter to.

  _Required: no · Position: named_
- **`-InterfaceName`** `String`
  Interface name inside the container.

  _Required: no · Position: named_
- **`-IPAddress`** `String`
  IPv4 address in CIDR notation, dhcp, or manual.

  _Required: no · Position: named_
- **`-Gateway`** `String`
  IPv4 gateway.

  _Required: no · Position: named_
- **`-IPv6Address`** `String`
  IPv6 address in CIDR notation, auto, dhcp, or manual.

  _Required: no · Position: named_
- **`-Gateway6`** `String`
  IPv6 gateway.

  _Required: no · Position: named_
- **`-VlanTag`** `Int32`
  VLAN tag (1 to 4094); 0 removes the tag.

  _Required: no · Position: named · Range: 0 to 4094_
- **`-Connected`** `Boolean`
  $false takes the link down; $true brings it up.

  _Required: no · Position: named_
- **`-Firewall`** `Boolean`
  Whether the PVE firewall applies to this adapter.

  _Required: no · Position: named_
- **`-MacAddress`** `String`
  MAC address.

  _Required: no · Position: named_
- **`-Mtu`** `Int32`
  MTU; 0 removes the setting.

  _Required: no · Position: named · Range: 0 to 65535_
- **`-RateLimitMBps`** `Double`
  Rate limit in megabytes per second; 0 removes the limit.

  _Required: no · Position: named · Range: 0 to 1.7976931348623157E+308_
- **`-Parameter`** `Hashtable`
  Further adapter options by their API names; a $null value removes the option.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.ContainerNetworkAdapter`

**Examples**

```powershell
Set-PVEContainerNetworkAdapter -VMId 200 -Device net0 -IPAddress 192.0.2.20/24 -Gateway 192.0.2.1
```

[Back to the cmdlet index](#cmdlet-index)

#### Remove-PVEContainerNetworkAdapter

Removes network adapters from LXC containers.

Removes each netN entry with PUT /nodes/{node}/lxc/{vmid}/config (delete=netN). Its MAC address is
lost with it. Prompts for confirmation by default (ConfirmImpact High). On a running container, PVE
hot-unplugs the adapter if it can; otherwise the removal is pending until the next start, and a
warning says so. Writes nothing.

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Remove-PVEContainerNetworkAdapter -VMId <int[]> -Device <string[]> [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]

# Parameter set: Name
Remove-PVEContainerNetworkAdapter [-VMName] <string[]> -Device <string[]> [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  Container ID. Binds from piped PVEPS.ContainerNetworkAdapter objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Device`** `String[]`
  Adapter(s) to remove, for example net1. Binds from piped PVEPS.ContainerNetworkAdapter objects.

  _Required: yes · Position: named · Pipeline: by property name_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `System.Void`

**Examples**

```powershell
Remove-PVEContainerNetworkAdapter -VMId 200 -Device net1
```

[Back to the cmdlet index](#cmdlet-index)

### Snapshots

#### Get-PVEVMSnapshot

Gets the snapshots of QEMU virtual machines.

Writes one PVEPS.Snapshot object per snapshot, oldest first, from GET
/nodes/{node}/qemu/{vmid}/snapshot. IsCurrent marks the snapshot the VM is running from (the parent of
its current state). IncludesMemory says whether the snapshot saved the RAM (vmstate).

**Syntax**

```text
# Parameter set: Id (default)
Get-PVEVMSnapshot -VMId <int[]> [-Snapshot <string[]>] [-Server <Object[]>] [<CommonParameters>]

# Parameter set: Name
Get-PVEVMSnapshot [-VMName] <string[]> [-Snapshot <string[]>] [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM or PVEPS.Snapshot objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed. Templates are included.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Snapshot`** `String[]`
  Snapshot name(s) to return. Wildcards allowed. All snapshots if omitted.

  _Required: no · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Snapshot`

**Examples**

```powershell
Get-PVEVM web01 | Get-PVEVMSnapshot
Get-PVEVMSnapshot -VMName '*' | Where-Object Created -LT (Get-Date).AddDays(-30)
```

[Back to the cmdlet index](#cmdlet-index)

#### New-PVEVMSnapshot

Takes a snapshot of QEMU virtual machines.

Takes the snapshot with POST /nodes/{node}/qemu/{vmid}/snapshot, waits for the task, and writes the new
PVEPS.Snapshot object. Several VMs get a snapshot of the same name, and are waited on together. The
storage of every disk must support snapshots, or PVE refuses.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
New-PVEVMSnapshot -VMId <int[]> -Snapshot <string> [-Description <string>] [-IncludeMemory] [-RunAsync]
    [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
New-PVEVMSnapshot [-VMName] <string[]> -Snapshot <string> [-Description <string>] [-IncludeMemory] [-RunAsync]
    [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM or PVEPS.Snapshot objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Snapshot`** `String`
  Name of the new snapshot: up to 40 characters, in the format the API schema calls pve-configid, which
  PVE checks.

  _Required: yes · Position: named_
- **`-Description`** `String`
  Description of the snapshot.

  _Required: no · Position: named_
- **`-IncludeMemory`** `SwitchParameter`
  Also save the VM's RAM (vmstate). The API documents that rolling back to such a snapshot starts the
  VM.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Snapshot`, `PVEPS.Task`

**Examples**

```powershell
New-PVEVMSnapshot -VMId 100 -Snapshot before-upgrade -Description 'Before the upgrade'
Get-PVEVM 'web*' | New-PVEVMSnapshot -Snapshot nightly
```

[Back to the cmdlet index](#cmdlet-index)

#### Set-PVEVMSnapshot

Changes the description of VM snapshots.

Sends the description with PUT /nodes/{node}/qemu/{vmid}/snapshot/{snapname}/config and writes the
snapshot as it now is. The description is the only snapshot property the API can change.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Set-PVEVMSnapshot -VMId <int[]> -Snapshot <string[]> -Description <string> [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]

# Parameter set: Name
Set-PVEVMSnapshot [-VMName] <string[]> -Snapshot <string[]> -Description <string> [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM or PVEPS.Snapshot objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Snapshot`** `String[]`
  Snapshot name(s). Wildcards allowed. Binds from piped PVEPS.Snapshot objects.

  _Required: yes · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-Description`** `String`
  New description. An empty string clears it.

  _Required: yes · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Snapshot`

**Examples**

```powershell
Set-PVEVMSnapshot -VMId 100 -Snapshot before-upgrade -Description 'Kept until the upgrade is signed off'
```

[Back to the cmdlet index](#cmdlet-index)

#### Restore-PVEVMSnapshot

Rolls VMs back to a snapshot.

Rolls back with POST /nodes/{node}/qemu/{vmid}/snapshot/{snapname}/rollback, waits for the task, and
writes the VM with its live status. Everything since the snapshot is lost, which is why this prompts
for
confirmation by default (ConfirmImpact High). The snapshot itself is kept.

Exactly one snapshot per VM: a name or pattern matching several snapshots of one VM is an error for
that
VM.

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Restore-PVEVMSnapshot -VMId <int[]> -Snapshot <string[]> [-PowerOn] [-RunAsync] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]

# Parameter set: Name
Restore-PVEVMSnapshot [-VMName] <string[]> -Snapshot <string[]> [-PowerOn] [-RunAsync] [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM or PVEPS.Snapshot objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Snapshot`** `String[]`
  Snapshot name. Wildcards allowed. Binds from piped PVEPS.Snapshot objects.

  _Required: yes · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-PowerOn`** `SwitchParameter`
  Start the VM after rolling back (the API documents that a VM is started anyway after rolling back to a
  snapshot that includes RAM).

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VM`, `PVEPS.Task`

**Examples**

```powershell
Restore-PVEVMSnapshot -VMId 100 -Snapshot before-upgrade
Get-PVEVMSnapshot -VMId 100 | Where-Object IsCurrent | Restore-PVEVMSnapshot -PowerOn -Confirm:$false
```

[Back to the cmdlet index](#cmdlet-index)

#### Remove-PVEVMSnapshot

Deletes VM snapshots.

Deletes each snapshot with DELETE /nodes/{node}/qemu/{vmid}/snapshot/{snapname} and waits for the
tasks.
The VM's current state is not changed. Prompts for confirmation by default (ConfirmImpact High). Writes
nothing (with -RunAsync, the tasks).

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Remove-PVEVMSnapshot -VMId <int[]> -Snapshot <string[]> [-Force] [-RunAsync] [-Server <Object[]>] [-WhatIf]
    [-Confirm] [<CommonParameters>]

# Parameter set: Name
Remove-PVEVMSnapshot [-VMName] <string[]> -Snapshot <string[]> [-Force] [-RunAsync] [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM or PVEPS.Snapshot objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Snapshot`** `String[]`
  Snapshot name(s). Wildcards allowed. Binds from piped PVEPS.Snapshot objects.

  _Required: yes · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-Force`** `SwitchParameter`
  Remove the snapshot from the configuration even if removing the disk snapshots fails (the API's force
  option). Disk snapshots left behind then have to be cleaned up on the storage by hand.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Task`

**Examples**

```powershell
Remove-PVEVMSnapshot -VMId 100 -Snapshot before-upgrade
Get-PVEVMSnapshot -VMName '*' | Where-Object Created -LT (Get-Date).AddDays(-30) | Remove-PVEVMSnapshot -Confirm:$false
```

[Back to the cmdlet index](#cmdlet-index)

#### Get-PVEContainerSnapshot

Gets the snapshots of LXC containers.

Writes one PVEPS.Snapshot object per snapshot, oldest first, from GET
/nodes/{node}/lxc/{vmid}/snapshot. IsCurrent marks the snapshot the container is running from (the
parent of
its current state).

**Syntax**

```text
# Parameter set: Id (default)
Get-PVEContainerSnapshot -VMId <int[]> [-Snapshot <string[]>] [-Server <Object[]>] [<CommonParameters>]

# Parameter set: Name
Get-PVEContainerSnapshot [-VMName] <string[]> [-Snapshot <string[]>] [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container or PVEPS.Snapshot objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  Container name(s). Wildcards allowed. Templates are included.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Snapshot`** `String[]`
  Snapshot name(s) to return. Wildcards allowed. All snapshots if omitted.

  _Required: no · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Snapshot`

**Examples**

```powershell
Get-PVEContainer dns01 | Get-PVEContainerSnapshot
Get-PVEContainerSnapshot -VMName '*' | Where-Object Created -LT (Get-Date).AddDays(-30)
```

[Back to the cmdlet index](#cmdlet-index)

#### New-PVEContainerSnapshot

Takes a snapshot of LXC containers.

Takes the snapshot with POST /nodes/{node}/lxc/{vmid}/snapshot, waits for the task, and writes the new
PVEPS.Snapshot object. Several containers get a snapshot of the same name, and are waited on together.
The
storage of every disk must support snapshots, or PVE refuses.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
New-PVEContainerSnapshot -VMId <int[]> -Snapshot <string> [-Description <string>] [-RunAsync]
    [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
New-PVEContainerSnapshot [-VMName] <string[]> -Snapshot <string> [-Description <string>] [-RunAsync]
    [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container or PVEPS.Snapshot objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Snapshot`** `String`
  Name of the new snapshot: up to 40 characters, in the format the API schema calls pve-configid, which
  PVE checks.

  _Required: yes · Position: named_
- **`-Description`** `String`
  Description of the snapshot.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Snapshot`, `PVEPS.Task`

**Examples**

```powershell
New-PVEContainerSnapshot -VMId 200 -Snapshot before-upgrade -Description 'Before the upgrade'
Get-PVEContainer 'web*' | New-PVEContainerSnapshot -Snapshot nightly
```

[Back to the cmdlet index](#cmdlet-index)

#### Set-PVEContainerSnapshot

Changes the description of container snapshots.

Sends the description with PUT /nodes/{node}/lxc/{vmid}/snapshot/{snapname}/config and writes the
snapshot as it now is. The description is the only snapshot property the API can change.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Set-PVEContainerSnapshot -VMId <int[]> -Snapshot <string[]> -Description <string> [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
Set-PVEContainerSnapshot [-VMName] <string[]> -Snapshot <string[]> -Description <string> [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container or PVEPS.Snapshot objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Snapshot`** `String[]`
  Snapshot name(s). Wildcards allowed. Binds from piped PVEPS.Snapshot objects.

  _Required: yes · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-Description`** `String`
  New description. An empty string clears it.

  _Required: yes · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Snapshot`

**Examples**

```powershell
Set-PVEContainerSnapshot -VMId 200 -Snapshot before-upgrade -Description 'Kept until the upgrade is signed off'
```

[Back to the cmdlet index](#cmdlet-index)

#### Restore-PVEContainerSnapshot

Rolls containers back to a snapshot.

Rolls back with POST /nodes/{node}/lxc/{vmid}/snapshot/{snapname}/rollback, waits for the task, and
writes the container with its live status. Everything since the snapshot is lost, which is why this
prompts for
confirmation by default (ConfirmImpact High). The snapshot itself is kept.

Exactly one snapshot per container: a name or pattern matching several snapshots of one container is
an error for that
container.

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Restore-PVEContainerSnapshot -VMId <int[]> -Snapshot <string[]> [-PowerOn] [-RunAsync] [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
Restore-PVEContainerSnapshot [-VMName] <string[]> -Snapshot <string[]> [-PowerOn] [-RunAsync]
    [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container or PVEPS.Snapshot objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Snapshot`** `String[]`
  Snapshot name. Wildcards allowed. Binds from piped PVEPS.Snapshot objects.

  _Required: yes · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-PowerOn`** `SwitchParameter`
  Start the container after rolling back.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Container`, `PVEPS.Task`

**Examples**

```powershell
Restore-PVEContainerSnapshot -VMId 200 -Snapshot before-upgrade
Get-PVEContainerSnapshot -VMId 200 | Where-Object IsCurrent | Restore-PVEContainerSnapshot -PowerOn -Confirm:$false
```

[Back to the cmdlet index](#cmdlet-index)

#### Remove-PVEContainerSnapshot

Deletes container snapshots.

Deletes each snapshot with DELETE /nodes/{node}/lxc/{vmid}/snapshot/{snapname} and waits for the tasks.
The container's current state is not changed. Prompts for confirmation by default (ConfirmImpact
High). Writes
nothing (with -RunAsync, the tasks).

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Remove-PVEContainerSnapshot -VMId <int[]> -Snapshot <string[]> [-Force] [-RunAsync] [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
Remove-PVEContainerSnapshot [-VMName] <string[]> -Snapshot <string[]> [-Force] [-RunAsync]
    [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container or PVEPS.Snapshot objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Snapshot`** `String[]`
  Snapshot name(s). Wildcards allowed. Binds from piped PVEPS.Snapshot objects.

  _Required: yes · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-Force`** `SwitchParameter`
  Remove the snapshot from the configuration even if removing the disk snapshots fails (the API's force
  option). Disk snapshots left behind then have to be cleaned up on the storage by hand.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Task`

**Examples**

```powershell
Remove-PVEContainerSnapshot -VMId 200 -Snapshot before-upgrade
Get-PVEContainerSnapshot -VMName '*' | Where-Object Created -LT (Get-Date).AddDays(-30) | Remove-PVEContainerSnapshot -Confirm:$false
```

[Back to the cmdlet index](#cmdlet-index)

### Guest agent and console

#### Get-PVEVMGuest

Gets what the QEMU guest agent reports from inside VMs: OS, host name and IP addresses.

For each VM, writes one PVEPS.VMGuest object. State is:
- Running: the agent answered (POST .../agent/ping), and the other properties come from it.
- AgentNotRunning: the VM runs but the agent did not answer (not installed, not started, or the agent
  option is off in the VM's configuration).
- VMNotRunning: the VM is not running.

The details come from the agent's get-osinfo, get-host-name, network-get-interfaces and info calls. An
older agent that lacks one of them leaves those properties empty. IPAddress lists every address except
loopback ones; Interfaces has the per-interface detail.

**Syntax**

```text
# Parameter set: Id (default)
Get-PVEVMGuest -VMId <int[]> [-Server <Object[]>] [<CommonParameters>]

# Parameter set: Name
Get-PVEVMGuest [-VMName] <string[]> [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VMGuest`

**Examples**

```powershell
Get-PVEVM web01 | Get-PVEVMGuest
Get-PVEVMGuest -VMName '*' | Where-Object State -EQ 'Running' | Select-Object VMName, HostName, OSName, IPAddress
```

[Back to the cmdlet index](#cmdlet-index)

#### Invoke-PVEVMScript

Runs a command inside running VMs through the QEMU guest agent and returns its output.

Starts the command with POST /nodes/{node}/qemu/{vmid}/agent/exec on every VM, then polls
GET .../agent/exec-status for each until it exits or -TimeoutSec runs out. Writes one
PVEPS.VMScriptResult per VM with the exit code, standard output and standard error. A non-zero exit
code is a result, not an error. A command still running at the timeout is an error
(PVEGuestCommandTimeout); it keeps running in the guest.

-Command runs a program directly with the given arguments. -ScriptText runs text through an
interpreter chosen by -ScriptType:
- Bash: /bin/bash -c &lt;text&gt;      - Sh: /bin/sh -c &lt;text&gt;
- PowerShell: powershell.exe -NoProfile -NonInteractive -Command &lt;text&gt;
- Pwsh: pwsh -NoProfile -NonInteractive -Command &lt;text&gt;
- Cmd: cmd.exe /c &lt;text&gt;

The VM must be running, with the agent installed and running in the guest. The API documentation
requires the VM.GuestAgent.Unrestricted privilege for exec.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: IdScript (default)
Invoke-PVEVMScript -VMId <int[]> -ScriptText <string> [-ScriptType <string>] [-InputData <string>]
    [-TimeoutSec <int>] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: IdCommand
Invoke-PVEVMScript -VMId <int[]> -Command <string[]> [-InputData <string>] [-TimeoutSec <int>]
    [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: NameCommand
Invoke-PVEVMScript [-VMName] <string[]> -Command <string[]> [-InputData <string>] [-TimeoutSec <int>]
    [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: NameScript
Invoke-PVEVMScript [-VMName] <string[]> -ScriptText <string> [-ScriptType <string>] [-InputData <string>]
    [-TimeoutSec <int>] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter sets: IdCommand, IdScript · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter sets: NameCommand, NameScript · Position: first · Wildcards: yes_
- **`-Command`** `String[]`
  Program and arguments, one per element, for example 'ls', '-l', '/etc'.

  _Required: yes · Parameter sets: NameCommand, IdCommand · Position: named_
- **`-ScriptText`** `String`
  Script text to run through the -ScriptType interpreter.

  _Required: yes · Parameter sets: NameScript, IdScript · Position: named_
- **`-ScriptType`** `String`
  Bash (the default), Sh, PowerShell, Pwsh or Cmd.

  _Required: no · Parameter sets: NameScript, IdScript · Position: named · Values: Bash, Sh, PowerShell, Pwsh, Cmd · Default: 'Bash'_
- **`-InputData`** `String`
  Text passed to the command as standard input.

  _Required: no · Position: named_
- **`-TimeoutSec`** `Int32`
  Seconds to wait for the command to exit. Defaults to 300.

  _Required: no · Position: named · Range: 1 to 2147483647 · Default: 300_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VMScriptResult`

**Examples**

```powershell
Invoke-PVEVMScript -VMId 100 -ScriptText 'uptime; df -h /'
Get-PVEVM 'web*' | Invoke-PVEVMScript -Command systemctl, is-active, nginx | Select-Object VMName, ExitCode, StdOut
Invoke-PVEVMScript -VMName win01 -ScriptType PowerShell -ScriptText 'Get-Service W32Time'
```

[Back to the cmdlet index](#cmdlet-index)

#### Copy-PVEVMGuestFile

Copies a file between this computer and a VM, through the QEMU guest agent.

-LocalToGuest writes the local file into each VM with POST /nodes/{node}/qemu/{vmid}/agent/file-write.
The API limits the content to 61440 characters; the file is sent base64-encoded (so any bytes copy
unchanged), which limits it to 46080 bytes. A larger file is an error and nothing is sent. The guest
file is replaced if it exists. Writes nothing.

-GuestToLocal reads the guest file with GET .../agent/file-read, in chunks (the API limits one read to
16777216 bytes), and writes it to -Destination. Exactly one VM. An existing local file is an error
unless -Force is given. Writes the local file's FileInfo.

The VM must be running, with the agent running in the guest. The API documentation requires
VM.GuestAgent.FileWrite or FileRead (or Unrestricted).

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: IdToGuest (default)
Copy-PVEVMGuestFile -VMId <int[]> -Source <string> -Destination <string> -LocalToGuest [-Server <Object[]>]
    [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: IdToLocal
Copy-PVEVMGuestFile -VMId <int[]> -Source <string> -Destination <string> -GuestToLocal [-Force]
    [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: NameToLocal
Copy-PVEVMGuestFile [-VMName] <string[]> -Source <string> -Destination <string> -GuestToLocal [-Force]
    [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: NameToGuest
Copy-PVEVMGuestFile [-VMName] <string[]> -Source <string> -Destination <string> -LocalToGuest
    [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter sets: IdToLocal, IdToGuest · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter sets: NameToLocal, NameToGuest · Position: first · Wildcards: yes_
- **`-Source`** `String`
  The file to copy: a local path with -LocalToGuest, a guest path with -GuestToLocal.

  _Required: yes · Position: named_
- **`-Destination`** `String`
  Where to put it: a guest path with -LocalToGuest, a local path with -GuestToLocal.

  _Required: yes · Position: named_
- **`-LocalToGuest`** `SwitchParameter`
  Copy from this computer into the VM.

  _Required: yes · Parameter sets: NameToGuest, IdToGuest · Position: named_
- **`-GuestToLocal`** `SwitchParameter`
  Copy from the VM to this computer.

  _Required: yes · Parameter sets: NameToLocal, IdToLocal · Position: named_
- **`-Force`** `SwitchParameter`
  With -GuestToLocal, replace an existing local file.

  _Required: no · Parameter sets: NameToLocal, IdToLocal · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `System.IO.FileInfo`

**Examples**

```powershell
Copy-PVEVMGuestFile -VMId 100 -LocalToGuest -Source ./motd -Destination /etc/motd
Copy-PVEVMGuestFile -VMId 100 -GuestToLocal -Source /var/log/syslog -Destination ./syslog-web01.txt
```

[Back to the cmdlet index](#cmdlet-index)

#### Open-PVEVMConsole

Opens the noVNC console of VMs in the default web browser.

Builds the console URL the PVE web interface itself opens (pve-manager's openVNCViewer:
`https://<server>:<port>/?console=kvm&novnc=1&vmid=<id>&vmname=<name>&node=<node>&resize=off&cmd=`)
and opens it with Start-Process, which hands it to the system's default browser. The browser needs its
own PVE web interface session; the module's connection is not passed to it.

-UrlOnly writes the URL instead of opening it, for example to open it elsewhere.

**Syntax**

```text
# Parameter set: Id (default)
Open-PVEVMConsole -VMId <int[]> [-UrlOnly] [-Server <Object[]>] [<CommonParameters>]

# Parameter set: Name
Open-PVEVMConsole [-VMName] <string[]> [-UrlOnly] [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-UrlOnly`** `SwitchParameter`
  Write the URL instead of opening a browser.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `System.String`

**Examples**

```powershell
Open-PVEVMConsole web01
Get-PVEVM -VMId 100 | Open-PVEVMConsole -UrlOnly
```

[Back to the cmdlet index](#cmdlet-index)

#### Open-PVEContainerConsole

Opens the noVNC console of containers in the default web browser.

Builds the console URL the PVE web interface itself opens (pve-manager's openVNCViewer:
`https://<server>:<port>/?console=lxc&novnc=1&vmid=<id>&vmname=<name>&node=<node>&resize=off&cmd=`)
and opens it with Start-Process, which hands it to the system's default browser. The browser needs its
own PVE web interface session; the module's connection is not passed to it.

-UrlOnly writes the URL instead of opening it, for example to open it elsewhere.

**Syntax**

```text
# Parameter set: Id (default)
Open-PVEContainerConsole -VMId <int[]> [-UrlOnly] [-Server <Object[]>] [<CommonParameters>]

# Parameter set: Name
Open-PVEContainerConsole [-VMName] <string[]> [-UrlOnly] [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-UrlOnly`** `SwitchParameter`
  Write the URL instead of opening a browser.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `System.String`

**Examples**

```powershell
Open-PVEContainerConsole dns01
Get-PVEContainer -VMId 100 | Open-PVEContainerConsole -UrlOnly
```

[Back to the cmdlet index](#cmdlet-index)

### Storage content and templates

#### Get-PVEStorageContent

Lists what is stored on PVE storages: ISO images, container templates, backups, disk images and more.

Finds the storages with Get-PVEStorage (all of them unless -Storage or -Node narrows it, and only those
that hold -Content if it is given), then lists each one's content with
GET /nodes/{node}/storage/{storage}/content. Inactive storages are skipped with a warning, since PVE
cannot list them. Writes PVEPS.StorageContent objects, newest first per storage.

**Syntax**

```text
Get-PVEStorageContent [[-Storage] <string[]>] [-Node <string[]>] [-Content <string>] [-VMId <int>]
    [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-Storage`** `String[]`
  Storage name(s). Wildcards allowed. Binds from piped PVEPS.Storage objects.

  _Required: no · Position: first · Pipeline: by property name · Wildcards: yes · Alias: -Name_
- **`-Node`** `String[]`
  Node name(s). Wildcards allowed. Binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-Content`** `String`
  Only this type: iso, vztmpl, backup, images, rootdir, snippets or import.

  _Required: no · Position: named_
- **`-VMId`** `Int32`
  Only volumes and backups belonging to this guest ID.

  _Required: no · Position: named · Range: 1 to 999999999_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.StorageContent`

**Examples**

```powershell
Get-PVEStorageContent -Content iso
Get-PVEStorage local-lvm | Get-PVEStorageContent | Sort-Object SizeGB -Descending | Select-Object -First 10
Get-PVEStorageContent -Content backup -VMId 100
```

[Back to the cmdlet index](#cmdlet-index)

#### Import-PVEStorageContent

Puts an ISO image, container template or import file onto a PVE storage, from a URL or a local file.

-Url makes the node download the file itself (POST /nodes/{node}/storage/{storage}/download-url), which
is usually fastest. -Path uploads a local file (POST .../upload, multipart). Either way the cmdlet waits
for PVE's task, then writes the stored PVEPS.StorageContent object.

-Checksum with -ChecksumAlgorithm makes PVE verify the file and fail the task on a mismatch. The API
documentation warns that PVE normalises the file name; if the stored name differs, a warning says so.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Url (default)
Import-PVEStorageContent [-Url] <string> -Storage <string> -Content <string> [-FileName <string>]
    [-Checksum <string>] [-ChecksumAlgorithm <string>] [-Compression <string>] [-SkipCertificateCheck]
    [-Node <string>] [-RunAsync] [-Server <Object>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Path
Import-PVEStorageContent -Path <string> -Storage <string> -Content <string> [-FileName <string>]
    [-Checksum <string>] [-ChecksumAlgorithm <string>] [-Node <string>] [-RunAsync] [-Server <Object>]
    [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Url`** `String`
  URL for the node to download from.

  _Required: yes · Parameter set: Url · Position: first_
- **`-Path`** `String`
  Local file to upload.

  _Required: yes · Parameter set: Path · Position: named_
- **`-Storage`** `String`
  Target storage. It must allow the content type.

  _Required: yes · Position: named_
- **`-Content`** `String`
  iso, vztmpl (container template) or import.

  _Required: yes · Position: named · Values: iso, vztmpl, import_
- **`-FileName`** `String`
  Name to store the file under. Defaults to the last part of the URL, or the local file's name.

  _Required: no · Position: named_
- **`-Checksum`** `String`
  Expected checksum of the file.

  _Required: no · Position: named_
- **`-ChecksumAlgorithm`** `String`
  md5, sha1, sha224, sha256, sha384 or sha512.

  _Required: no · Position: named · Values: md5, sha1, sha224, sha256, sha384, sha512_
- **`-Compression`** `String`
  With -Url: decompress the download with this algorithm (for example zst or gz).

  _Required: no · Parameter set: Url · Position: named_
- **`-SkipCertificateCheck`** `SwitchParameter`
  With -Url: the node does not verify the download server's TLS certificate.

  _Required: no · Parameter set: Url · Position: named_
- **`-Node`** `String`
  Node to store the file on. Can be omitted on a single-node server.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the task at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object`
  Connection to use. Defaults to the default connection.

  _Required: no · Position: named · Alias: -Connection_

**Output:** `PVEPS.StorageContent`, `PVEPS.Task`

**Examples**

```powershell
Import-PVEStorageContent -Url https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.1.0-amd64-netinst.iso -Storage local -Content iso
Import-PVEStorageContent -Path ./virtio-win.iso -Storage local -Content iso -Checksum $sha256 -ChecksumAlgorithm sha256
```

[Back to the cmdlet index](#cmdlet-index)

#### Set-PVEStorageContent

Changes the notes or protection of stored volumes.

Sends the change with PUT /nodes/{node}/storage/{storage}/content/{volume} and writes the volume as it
now is. The API documentation says protection is currently only supported for backups; a protected
backup cannot be deleted until it is unprotected.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
Set-PVEStorageContent [-Volume] <string[]> [-Node <string>] [-Notes <string>] [-Protected <bool>]
    [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Volume`** `String[]`
  Volume ID(s). Binds from piped PVEPS.StorageContent objects.

  _Required: yes · Position: first · Pipeline: by property name_
- **`-Node`** `String`
  Node the storage is on. Binds from piped objects; can be omitted on a single-node server.

  _Required: no · Position: named · Pipeline: by property name_
- **`-Notes`** `String`
  New notes.

  _Required: no · Position: named_
- **`-Protected`** `Boolean`
  Whether the backup is protected.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.StorageContent`

**Examples**

```powershell
Get-PVEStorageContent -Content backup -VMId 100 | Select-Object -First 1 | Set-PVEStorageContent -Protected $true -Notes 'Before the migration'
```

[Back to the cmdlet index](#cmdlet-index)

#### Remove-PVEStorageContent

Deletes volumes from storage: ISO images, templates, backups, or unused disk images.

Deletes each volume with DELETE /nodes/{node}/storage/{storage}/content/{volume} and waits for the task.
This cannot be undone. Prompts for confirmation by default (ConfirmImpact High). PVE refuses to delete a
protected backup, and a disk image that a guest still uses. Writes nothing.

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
Remove-PVEStorageContent [-Volume] <string[]> [-Node <string>] [-Server <Object[]>] [-WhatIf] [-Confirm]
    [<CommonParameters>]
```

**Parameters**

- **`-Volume`** `String[]`
  Volume ID(s), for example local:iso/old.iso. Binds from piped PVEPS.StorageContent objects.

  _Required: yes · Position: first · Pipeline: by property name_
- **`-Node`** `String`
  Node the storage is on. Binds from piped objects; can be omitted on a single-node server.

  _Required: no · Position: named · Pipeline: by property name_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `System.Void`

**Examples**

```powershell
Remove-PVEStorageContent -Volume local:iso/debian-12.5.0-amd64-netinst.iso
Get-PVEStorageContent -Content backup -VMId 100 | Select-Object -Skip 3 | Remove-PVEStorageContent -Confirm:$false
```

[Back to the cmdlet index](#cmdlet-index)

#### Get-PVEApplianceTemplate

Lists the container templates PVE can download (the appliance catalogue that pveam uses).

Reads GET /nodes/{node}/aplinfo and writes one PVEPS.ApplianceTemplate object per entry. The API schema
does not describe the entries' fields; Template, Section, OS, Version, Package, Headline and
Description are read from the fields PVE's own catalogue uses (template, section, os, version,
package, headline, description), and are empty if PVE leaves one out. Save-PVEApplianceTemplate
downloads one onto a storage.

**Syntax**

```text
Get-PVEApplianceTemplate [[-Template] <string[]>] [-Section <string>] [-Node <string>] [-Server <Object[]>]
    [<CommonParameters>]
```

**Parameters**

- **`-Template`** `String[]`
  Template file name(s) to return, for example 'debian-13-\*'. Wildcards allowed.

  _Required: no · Position: first · Wildcards: yes_
- **`-Section`** `String`
  Only templates in this section, for example system or turnkeylinux.

  _Required: no · Position: named_
- **`-Node`** `String`
  Node whose catalogue to read. Can be omitted on a single-node server.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection.

  _Required: no · Position: named · Alias: -Connection_

**Output:** `PVEPS.ApplianceTemplate`

**Examples**

```powershell
Get-PVEApplianceTemplate -Section system | Select-Object Template, Headline
Get-PVEApplianceTemplate 'debian-13-standard*' | Save-PVEApplianceTemplate -Storage local
```

[Back to the cmdlet index](#cmdlet-index)

#### Save-PVEApplianceTemplate

Downloads container templates from the PVE appliance catalogue onto a storage.

Starts each download with POST /nodes/{node}/aplinfo, waits for the tasks, and writes each stored
template as a PVEPS.StorageContent object, ready for New-PVEContainer -OSTemplate.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
Save-PVEApplianceTemplate [-Template] <string[]> -Storage <string> [-Node <string>] [-RunAsync]
    [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-Template`** `String[]`
  Template file name(s), as Get-PVEApplianceTemplate lists them. Binds from piped objects.

  _Required: yes · Position: first · Pipeline: by property name_
- **`-Storage`** `String`
  Storage to save the templates on. It must allow container templates (vztmpl).

  _Required: yes · Position: named_
- **`-Node`** `String`
  Node to download on. Binds from piped objects; can be omitted on a single-node server.

  _Required: no · Position: named · Pipeline: by property name_
- **`-RunAsync`** `SwitchParameter`
  Return the task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.StorageContent`, `PVEPS.Task`

**Examples**

```powershell
Save-PVEApplianceTemplate -Template debian-13-standard_13.1-2_amd64.tar.zst -Storage local
$t = Get-PVEApplianceTemplate 'debian-13-standard*' | Save-PVEApplianceTemplate -Storage local
New-PVEContainer -Name ct01 -OSTemplate $t.Volume -Storage local-lvm
```

[Back to the cmdlet index](#cmdlet-index)

### Backup and restore

#### Backup-PVEVM

Backs up VMs with vzdump.

Starts one backup task per node (POST /nodes/{node}/vzdump) for all the VMs given, waits for it,
and writes each new backup as a PVEPS.StorageContent object. Options not given come from PVE's own
backup defaults (its vzdump configuration). Restore-PVEBackup restores one; Remove-PVEStorageContent
deletes one.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Backup-PVEVM -VMId <int[]> [-Storage <string>] [-Mode <string>] [-Compress <string>] [-Notes <string>]
    [-Protected] [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
Backup-PVEVM [-VMName] <string[]> [-Storage <string>] [-Mode <string>] [-Compress <string>] [-Notes <string>]
    [-Protected] [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Storage`** `String`
  Storage to write the backups to. It must allow backups.

  _Required: no · Position: named_
- **`-Mode`** `String`
  snapshot (the default: the VM keeps running), suspend, or stop (the VM is shut down for the backup and started again).

  _Required: no · Position: named · Values: snapshot, suspend, stop_
- **`-Compress`** `String`
  zstd, gzip, lzo, or none.

  _Required: no · Position: named · Values: zstd, gzip, lzo, none_
- **`-Notes`** `String`
  Notes for the backup. PVE replaces {{guestname}}, {{vmid}}, {{node}} and {{cluster}}, and the API
  documentation requires a single line.

  _Required: no · Position: named_
- **`-Protected`** `SwitchParameter`
  Protect the backup, so it cannot be deleted (or pruned) until it is unprotected.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.StorageContent`, `PVEPS.Task`

**Examples**

```powershell
Backup-PVEVM -VMId 100 -Storage local
Get-PVEVM 'web*' | Backup-PVEVM -Storage backups -Mode snapshot
```

[Back to the cmdlet index](#cmdlet-index)

#### Backup-PVEContainer

Backs up containers with vzdump.

Starts one backup task per node (POST /nodes/{node}/vzdump) for all the containers given, waits for it,
and writes each new backup as a PVEPS.StorageContent object. Options not given come from PVE's own
backup defaults (its vzdump configuration). Restore-PVEBackup restores one; Remove-PVEStorageContent
deletes one.

**Confirmation:** not asked by default; `-Confirm` asks. Supports `-WhatIf`.

**Syntax**

```text
# Parameter set: Id (default)
Backup-PVEContainer -VMId <int[]> [-Storage <string>] [-Mode <string>] [-Compress <string>] [-Notes <string>]
    [-Protected] [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]

# Parameter set: Name
Backup-PVEContainer [-VMName] <string[]> [-Storage <string>] [-Mode <string>] [-Compress <string>]
    [-Notes <string>] [-Protected] [-RunAsync] [-Server <Object[]>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Storage`** `String`
  Storage to write the backups to. It must allow backups.

  _Required: no · Position: named_
- **`-Mode`** `String`
  snapshot (the default; needs storage that supports snapshots), suspend, or stop (the container is shut down for the backup and started again).

  _Required: no · Position: named · Values: snapshot, suspend, stop_
- **`-Compress`** `String`
  zstd, gzip, lzo, or none.

  _Required: no · Position: named · Values: zstd, gzip, lzo, none_
- **`-Notes`** `String`
  Notes for the backup. PVE replaces {{guestname}}, {{vmid}}, {{node}} and {{cluster}}, and the API
  documentation requires a single line.

  _Required: no · Position: named_
- **`-Protected`** `SwitchParameter`
  Protect the backup, so it cannot be deleted (or pruned) until it is unprotected.

  _Required: no · Position: named_
- **`-RunAsync`** `SwitchParameter`
  Return the task(s) at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.StorageContent`, `PVEPS.Task`

**Examples**

```powershell
Backup-PVEContainer -VMId 200 -Storage local
Get-PVEContainer | Backup-PVEContainer -Storage backups -Compress zstd
```

[Back to the cmdlet index](#cmdlet-index)

#### Get-PVEBackup

Lists backups, optionally of particular guests, newest first.

Lists the backup content of storages (Get-PVEStorageContent -Content backup). With -VMId, only those
guests' backups; the IDs are not checked against existing guests, so backups of deleted guests are
found too. -Latest keeps only the newest backup of each guest.

**Syntax**

```text
Get-PVEBackup [[-VMId] <int[]>] [-Storage <string[]>] [-Node <string[]>] [-Latest] [-Server <Object[]>]
    [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  Guest ID(s). Binds from piped PVEPS.VM or PVEPS.Container objects.

  _Required: no · Position: first · Pipeline: by property name · Range: 1 to 999999999_
- **`-Storage`** `String[]`
  Storage name(s). Wildcards allowed.

  _Required: no · Position: named · Wildcards: yes_
- **`-Node`** `String[]`
  Node name(s). Wildcards allowed.

  _Required: no · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-Latest`** `SwitchParameter`
  Only the newest backup of each guest.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.StorageContent`

**Examples**

```powershell
Get-PVEVM web01 | Get-PVEBackup
Get-PVEBackup -Latest | Where-Object Created -LT (Get-Date).AddDays(-7)
```

[Back to the cmdlet index](#cmdlet-index)

#### Restore-PVEBackup

Restores a VM or container from a backup.

Restores with POST /nodes/{node}/qemu (archive=&lt;backup&gt;) for a VM backup, or POST /nodes/{node}/lxc
(ostemplate=&lt;backup&gt;, restore=1) for a container backup, waits for the task, and writes the restored
guest with its live status. Whether the backup is of a VM or a container comes from -GuestType, which
binds from piped PVEPS.StorageContent objects; otherwise it is looked up in the storage's backup list.

The guest is restored as -VMId. Restoring over an existing guest needs -Force and replaces that guest,
disks included; that cannot be undone. Prompts for confirmation by default (ConfirmImpact High).

**Confirmation:** asks by default (ConfirmImpact High); `-Confirm:$false` skips it. Supports `-WhatIf`.

**Syntax**

```text
Restore-PVEBackup [-Volume] <string> -VMId <int> [-GuestType <string>] [-Storage <string>] [-Pool <string>]
    [-Force] [-Unique] [-PowerOn] [-Node <string>] [-RunAsync] [-Server <Object>] [-WhatIf] [-Confirm]
    [<CommonParameters>]
```

**Parameters**

- **`-Volume`** `String`
  Backup volume ID, for example local:backup/vzdump-qemu-100-2026_10_17-02_00_00.vma.zst. Binds from
  piped PVEPS.StorageContent objects.

  _Required: yes · Position: first · Pipeline: by property name_
- **`-VMId`** `Int32`
  ID to restore as. Binds from piped objects, so a piped backup restores to its original ID unless
  -VMId is given.

  _Required: yes · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-GuestType`** `String`
  qemu or lxc. Binds from piped objects; looked up if omitted.

  _Required: no · Position: named · Pipeline: by property name · Values: qemu, lxc_
- **`-Storage`** `String`
  Storage for the restored disks. PVE restores to the original storages if omitted.

  _Required: no · Position: named_
- **`-Pool`** `String`
  Resource pool to add the restored guest to. The API documentation lets VM.Allocate on the pool stand
  in for VM.Allocate on the guest, so a user whose rights are on a pool needs this to restore a new
  guest.

  _Required: no · Position: named_
- **`-Force`** `SwitchParameter`
  Replace an existing guest with this ID.

  _Required: no · Position: named_
- **`-Unique`** `SwitchParameter`
  Give the restored guest new random MAC addresses, for example when the original still runs.

  _Required: no · Position: named_
- **`-PowerOn`** `SwitchParameter`
  Start the guest once it has been restored.

  _Required: no · Position: named_
- **`-Node`** `String`
  Node to restore on. Binds from piped objects; can be omitted on a single-node server.

  _Required: no · Position: named · Pipeline: by property name_
- **`-RunAsync`** `SwitchParameter`
  Return the task at once instead of waiting.

  _Required: no · Position: named_
- **`-Server`** `Object`
  Connection to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.VM`, `PVEPS.Container`, `PVEPS.Task`

**Examples**

```powershell
Get-PVEBackup -VMId 100 -Latest | Restore-PVEBackup -VMId 150 -Unique
Get-PVEBackup -VMId 100 -Latest | Restore-PVEBackup -Force -Confirm:$false
```

[Back to the cmdlet index](#cmdlet-index)

### Statistics and events

#### Get-PVEVMStat

Gets performance statistics of VMs from PVE's round-robin database.

Writes one PVEPS.Stat object per sample from GET /nodes/{node}/qemu/{vmid}/rrddata. The API schema does not describe
the samples, so each field is passed through under its PVE name and in PVE's units (for example cpu as
a fraction of the VM's CPUs, mem and maxmem in bytes, netin and netout in bytes per second);
Timestamp is the sample time. Samples with no values (gaps) are left out.

**Syntax**

```text
# Parameter set: Id (default)
Get-PVEVMStat -VMId <int[]> [-Timeframe <string>] [-Consolidation <string>] [-Metric <string[]>]
    [-Start <datetime>] [-Finish <datetime>] [-Server <Object[]>] [<CommonParameters>]

# Parameter set: Name
Get-PVEVMStat [-VMName] <string[]> [-Timeframe <string>] [-Consolidation <string>] [-Metric <string[]>]
    [-Start <datetime>] [-Finish <datetime>] [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  VM ID(s). Binds from piped PVEPS.VM objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  VM name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Timeframe`** `String`
  hour (the default), day, week, month or year. PVE keeps fewer, coarser samples the longer the
  time frame.

  _Required: no · Position: named · Values: hour, day, week, month, year · Default: 'hour'_
- **`-Consolidation`** `String`
  Average or Max: how PVE combines the raw values into each sample. PVE's default applies if omitted.

  _Required: no · Position: named · Values: Average, Max_
- **`-Metric`** `String[]`
  Only these fields, for example cpu or 'net\*'. Wildcards allowed.

  _Required: no · Position: named · Wildcards: yes_
- **`-Start`** `DateTime`
  Only samples at or after this time.

  _Required: no · Position: named_
- **`-Finish`** `DateTime`
  Only samples at or before this time.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Stat`

**Examples**

```powershell
Get-PVEVMStat -VMId 100 -Timeframe day -Metric cpu, mem
Get-PVEVM | Get-PVEVMStat -Metric cpu | Group-Object VMName | ForEach-Object { [pscustomobject]@{ VMName = $_.Name; AverageCpu = ($_.Group.cpu | Measure-Object -Average).Average } }
```

[Back to the cmdlet index](#cmdlet-index)

#### Get-PVEContainerStat

Gets performance statistics of containers from PVE's round-robin database.

Writes one PVEPS.Stat object per sample from GET /nodes/{node}/lxc/{vmid}/rrddata. The API schema does not describe
the samples, so each field is passed through under its PVE name and in PVE's units (for example cpu as
a fraction of the container's CPUs, mem and maxmem in bytes, netin and netout in bytes per second);
Timestamp is the sample time. Samples with no values (gaps) are left out.

**Syntax**

```text
# Parameter set: Id (default)
Get-PVEContainerStat -VMId <int[]> [-Timeframe <string>] [-Consolidation <string>] [-Metric <string[]>]
    [-Start <datetime>] [-Finish <datetime>] [-Server <Object[]>] [<CommonParameters>]

# Parameter set: Name
Get-PVEContainerStat [-VMName] <string[]> [-Timeframe <string>] [-Consolidation <string>] [-Metric <string[]>]
    [-Start <datetime>] [-Finish <datetime>] [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-VMId`** `Int32[]`
  Container ID(s). Binds from piped PVEPS.Container objects.

  _Required: yes · Parameter set: Id · Position: named · Pipeline: by property name · Range: 100 to 999999999_
- **`-VMName`** `String[]`
  Container name(s). Wildcards allowed.

  _Required: yes · Parameter set: Name · Position: first · Wildcards: yes_
- **`-Timeframe`** `String`
  hour (the default), day, week, month or year. PVE keeps fewer, coarser samples the longer the
  time frame.

  _Required: no · Position: named · Values: hour, day, week, month, year · Default: 'hour'_
- **`-Consolidation`** `String`
  Average or Max: how PVE combines the raw values into each sample. PVE's default applies if omitted.

  _Required: no · Position: named · Values: Average, Max_
- **`-Metric`** `String[]`
  Only these fields, for example cpu or 'net\*'. Wildcards allowed.

  _Required: no · Position: named · Wildcards: yes_
- **`-Start`** `DateTime`
  Only samples at or after this time.

  _Required: no · Position: named_
- **`-Finish`** `DateTime`
  Only samples at or before this time.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Stat`

**Examples**

```powershell
Get-PVEContainerStat -VMId 200 -Timeframe day -Metric cpu, mem
Get-PVEContainer | Get-PVEContainerStat -Metric cpu | Group-Object VMName | ForEach-Object { [pscustomobject]@{ VMName = $_.Name; AverageCpu = ($_.Group.cpu | Measure-Object -Average).Average } }
```

[Back to the cmdlet index](#cmdlet-index)

#### Get-PVENodeStat

Gets performance statistics of nodes from PVE's round-robin database.

Writes one PVEPS.Stat object per sample from GET /nodes/{node}/rrddata. The API schema does not describe
the samples, so each field is passed through under its PVE name and in PVE's units (for example cpu as
a fraction of the node's CPUs, mem and maxmem in bytes, netin and netout in bytes per second);
Timestamp is the sample time. Samples with no values (gaps) are left out.

**Syntax**

```text
Get-PVENodeStat [[-Node] <string[]>] [-Timeframe <string>] [-Consolidation <string>] [-Metric <string[]>]
    [-Start <datetime>] [-Finish <datetime>] [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-Node`** `String[]`
  Node name(s). Wildcards allowed. All online nodes if omitted. Binds from piped PVEPS.Node objects.

  _Required: no · Position: first · Pipeline: by property name · Wildcards: yes · Alias: -Name_
- **`-Timeframe`** `String`
  hour (the default), day, week, month or year, decade. PVE keeps fewer, coarser samples the longer the
  time frame.

  _Required: no · Position: named · Values: hour, day, week, month, year, decade · Default: 'hour'_
- **`-Consolidation`** `String`
  Average or Max: how PVE combines the raw values into each sample. PVE's default applies if omitted.

  _Required: no · Position: named · Values: Average, Max_
- **`-Metric`** `String[]`
  Only these fields, for example cpu or 'net\*'. Wildcards allowed.

  _Required: no · Position: named · Wildcards: yes_
- **`-Start`** `DateTime`
  Only samples at or after this time.

  _Required: no · Position: named_
- **`-Finish`** `DateTime`
  Only samples at or before this time.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Stat`

**Examples**

```powershell
Get-PVENodeStat -Timeframe week -Metric loadavg, cpu
Get-PVENode pve01 | Get-PVENodeStat -Consolidation Max -Timeframe day
```

[Back to the cmdlet index](#cmdlet-index)

#### Get-PVEStorageStat

Gets usage statistics of storages from PVE's round-robin database.

Writes one PVEPS.Stat object per sample from GET /nodes/{node}/storage/{storage}/rrddata. The API schema does not describe
the samples, so each field is passed through under its PVE name and in PVE's units (for example cpu as
a fraction of the storage's CPUs, mem and maxmem in bytes, netin and netout in bytes per second);
Timestamp is the sample time. Samples with no values (gaps) are left out.
The storages are found with Get-PVEStorage; inactive ones are skipped with a warning.

**Syntax**

```text
Get-PVEStorageStat [[-Storage] <string[]>] [-Node <string[]>] [-Timeframe <string>] [-Consolidation <string>]
    [-Metric <string[]>] [-Start <datetime>] [-Finish <datetime>] [-Server <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-Storage`** `String[]`
  Storage name(s). Wildcards allowed. Binds from piped PVEPS.Storage objects.

  _Required: no · Position: first · Pipeline: by property name · Wildcards: yes · Alias: -Name_
- **`-Node`** `String[]`
  Node name(s). Wildcards allowed. Binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Wildcards: yes_
- **`-Timeframe`** `String`
  hour (the default), day, week, month or year. PVE keeps fewer, coarser samples the longer the
  time frame.

  _Required: no · Position: named · Values: hour, day, week, month, year · Default: 'hour'_
- **`-Consolidation`** `String`
  Average or Max: how PVE combines the raw values into each sample. PVE's default applies if omitted.

  _Required: no · Position: named · Values: Average, Max_
- **`-Metric`** `String[]`
  Only these fields, for example cpu or 'net\*'. Wildcards allowed.

  _Required: no · Position: named · Wildcards: yes_
- **`-Start`** `DateTime`
  Only samples at or after this time.

  _Required: no · Position: named_
- **`-Finish`** `DateTime`
  Only samples at or before this time.

  _Required: no · Position: named_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection; binds from piped objects.

  _Required: no · Position: named · Pipeline: by property name · Alias: -Connection_

**Output:** `PVEPS.Stat`

**Examples**

```powershell
Get-PVEStorageStat local-lvm -Timeframe month -Metric used, total
```

[Back to the cmdlet index](#cmdlet-index)

#### Get-PVEEvent

Gets recent entries of the PVE cluster log: logins, task starts and ends, and other events.

Reads GET /cluster/log (which standalone nodes have too) and writes one PVEPS.Event object per entry,
newest first. The API schema does not describe the entries; Time, Node, User, Tag, Severity and
Message are read from the fields the PVE web interface's cluster log uses (time, node, user, tag, pri,
msg), and are empty if PVE leaves one out. Severity is the syslog priority number (0 emergency to 7
debug). For task details, Get-PVETask reads the task list itself.

**Syntax**

```text
Get-PVEEvent [[-MaxEntries] <int>] [[-Start] <datetime>] [[-Finish] <datetime>] [[-Node] <string[]>]
    [[-User] <string[]>] [[-Message] <string[]>] [[-Server] <Object[]>] [<CommonParameters>]
```

**Parameters**

- **`-MaxEntries`** `Int32`
  Maximum number of entries PVE returns. PVE's default applies if omitted.

  _Required: no · Position: first · Range: 1 to 2147483647_
- **`-Start`** `DateTime`
  Only entries at or after this time.

  _Required: no · Position: second_
- **`-Finish`** `DateTime`
  Only entries at or before this time.

  _Required: no · Position: third_
- **`-Node`** `String[]`
  Only entries from these nodes. Wildcards allowed.

  _Required: no · Position: number 4 · Wildcards: yes_
- **`-User`** `String[]`
  Only entries for these users, for example 'root@pam'. Wildcards allowed.

  _Required: no · Position: number 5 · Wildcards: yes_
- **`-Message`** `String[]`
  Only entries whose message matches. Wildcards allowed.

  _Required: no · Position: number 6 · Wildcards: yes_
- **`-Server`** `Object[]`
  Connection(s) to use. Defaults to the default connection.

  _Required: no · Position: number 7 · Alias: -Connection_

**Output:** `PVEPS.Event`

**Examples**

```powershell
Get-PVEEvent -Start (Get-Date).AddHours(-1)
Get-PVEEvent -MaxEntries 500 -Message '*authentication failure*'
```

[Back to the cmdlet index](#cmdlet-index)
<!-- cmdlet-reference:end -->

## Tests

```powershell
# Unit tests: offline, the HTTP layer is mocked.
Invoke-Pester ./tests -ExcludeTagFilter Integration

# Integration tests: read-only, run against a real server (token setup below).
$env:PVEPS_TEST_SERVER = 'pve01.example.com'
$env:PVEPS_TEST_TOKEN_ID = 'pveps@pve!readonly'
$env:PVEPS_TEST_TOKEN_SECRET = '...'
$env:PVEPS_TEST_SKIPCERT = '1'
Invoke-Pester ./tests -TagFilter Integration -ExcludeTagFilter Power, Lifecycle, Hardware, Snapshot, Agent, Storage -Output Detailed
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

The storage tests write ISOs and backups to `PVEPS_TEST_FILE_STORAGE`. According to the API schema,
uploading and saving templates need Datastore.AllocateTemplate on that storage and deleting an ISO
needs Datastore.Allocate, so it needs a stronger role than the disk storage; on a throwaway node,
`pveum acl modify /storage/local --users pveps@pve --tokens 'pveps@pve!write' --roles PVEDatastoreAdmin`.
Downloading by URL (`PVEPS_TEST_ISO_URL`) also needs Sys.AccessNetwork on the node, which no built-in
role is known to grant here (unverified); a custom role covers it:
`pveum role add PVEPSNetwork --privs Sys.AccessNetwork`, then grant it on `/nodes/<node>`.

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
# Needs PVEPS_TEST_FILE_STORAGE: a storage for ISOs and backups (see below for its rights).
Invoke-Pester ./tests/Integration/Storage.Integration.Tests.ps1 -Output Detailed
```

The header of each test file lists every variable it reads.


## Building, packaging and publishing

`build/Build-PVEPS.ps1` checks the manifest, stages the module files into `out/PVEPS` (no tests or build
scripts), imports the staged copy in a clean `pwsh` to check it exports every function, and writes
`out/PVEPS.<version>.nupkg` and `out/PVEPS-<version>.zip`.

```powershell
pwsh ./build/Build-PVEPS.ps1                  # build and check only
pwsh ./build/Build-PVEPS.ps1 -Install         # also install for the current user
pwsh ./build/Build-PVEPS.ps1 -Publish -ApiKey (Read-Host 'Gallery API key' -MaskInput)
```

`-Publish` publishes to the PowerShell Gallery with `Publish-PSResource`. That makes the module public,
and a published version number can never be reused, so it asks for confirmation. The API key comes from
the account page on powershellgallery.com.

`build/Update-PVEReadme.ps1` regenerates the [cmdlet index](#cmdlet-index) and
[cmdlet reference](#cmdlet-reference) in this file from the help. A unit test runs it with `-Check` and
fails when the README is out of date, so run it after changing any cmdlet's help or parameters:

```powershell
pwsh ./build/Update-PVEReadme.ps1
```

A release is: update `ModuleVersion` and `ReleaseNotes` in `PVEPS.psd1`, add a changelog line to
`PVEPS.psm1`, regenerate the README, run the unit tests and the integration tests, build, tag
(`git tag v<version>`), and publish.

## Scope and limitations

- **Standalone nodes.** Development and testing target a standalone node. Clusters (HA, migration between
  nodes, cluster status) are not yet supported; the cmdlets that take `-Node` work on any one node.
- **Not yet wrapped:** the firewall, HA, users and ACLs, Ceph, SDN, replication and backup jobs. Use
  `Invoke-PVEApi` for these.
- **Guest-agent file uploads** are limited to 46,080 bytes per file (45 KiB): the agent's file-write call
  takes at most 61,440 characters of base64. Downloads have no such limit.
- **Two-factor authentication:** users with it enabled must connect with an API token.

## Version history

The full changelog is in the header of [`PVEPS.psm1`](PVEPS.psm1).

- **1.0.1** (2026-10-17): first release of the rewrite for PowerShell 7 and Proxmox VE 9.x.
- **1** (2015 to 2018): the original module by Einar Stenberg. Its code is in the git history.

## Credits and licence

Original module by Einar Stenberg. Rewrite by Robert McLay.

PVEPS is free software: you can redistribute it and/or modify it under the terms of the GNU General
Public License, version 3, as published by the Free Software Foundation. It is distributed in the hope
that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See [LICENSE](LICENSE) for the full text.

Proxmox and Proxmox VE are trademarks of Proxmox Server Solutions GmbH. PVEPS is not affiliated with or
endorsed by Proxmox Server Solutions GmbH.
