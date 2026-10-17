function New-PVEContainer {
  <#
  .SYNOPSIS
  Creates an LXC container from an OS template.
  .DESCRIPTION
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
  .PARAMETER Name
  Host name of the container. PVE requires a valid DNS name.
  .PARAMETER OSTemplate
  OS template volume, for example local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst. Get-PVEStorage
  -Content vztmpl lists the storages that hold templates.
  .PARAMETER VMId
  ID for the container. Defaults to the next free ID. PVE checks a given ID is free before the container
  is created.
  .PARAMETER Node
  Node to create the container on. Can be omitted when the server has a single node.
  .PARAMETER Storage
  Storage for the root file system.
  .PARAMETER DiskGB
  Size of the root file system in GiB. Defaults to 8.
  .PARAMETER Cores
  CPU cores the container may use. PVE's default is all of the host's cores.
  .PARAMETER MemoryGB
  Memory in GiB, sent to PVE in whole MiB.
  .PARAMETER SwapGB
  Swap in GiB, sent to PVE in whole MiB. 0 disables swap.
  .PARAMETER Password
  Root password inside the container. Accepts a string or a SecureString.
  .PARAMETER SshPublicKey
  Public SSH keys (OpenSSH format) for root inside the container. One key per value.
  .PARAMETER Privileged
  Create a privileged container instead of an unprivileged one.
  .PARAMETER NetworkBridge
  Bridge for the container's eth0 network device, for example vmbr0.
  .PARAMETER IPAddress
  IPv4 address for eth0 in CIDR notation (192.0.2.10/24), dhcp, or manual. Defaults to dhcp. Needs
  -NetworkBridge.
  .PARAMETER Gateway
  IPv4 gateway for eth0. Needs -NetworkBridge.
  .PARAMETER IPv6Address
  IPv6 address for eth0 in CIDR notation, auto, dhcp, or manual. Needs -NetworkBridge.
  .PARAMETER Nesting
  Enable the nesting feature (see the description).
  .PARAMETER Pool
  Resource pool to add the container to.
  .PARAMETER Tags
  Tags for the container.
  .PARAMETER Description
  Description (notes) shown in the container's summary.
  .PARAMETER StartOnBoot
  Start the container when the node boots.
  .PARAMETER PowerOn
  Start the container once it has been created.
  .PARAMETER Parameter
  Further create options by their API names, for example @{ timezone = 'host'; nameserver = '192.0.2.53' }.
  .PARAMETER RunAsync
  Return the create task at once instead of waiting.
  .PARAMETER Server
  Connection to use. Defaults to the default connection.
  .EXAMPLE
  New-PVEContainer -Name dns01 -OSTemplate local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst -Storage local-lvm -NetworkBridge vmbr0 -SshPublicKey (Get-Content ~/.ssh/id_ed25519.pub)
  .EXAMPLE
  New-PVEContainer proxy01 -OSTemplate $template -Storage local-lvm -DiskGB 16 -MemoryGB 1 -NetworkBridge vmbr0 -IPAddress 192.0.2.20/24 -Gateway 192.0.2.1 -Nesting -PowerOn
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Password', Justification = 'Deliberately accepts a string or a SecureString, as Connect-PVE does.')]
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.Container', 'PVEPS.Task')]
  param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OSTemplate,

    [ValidateRange(100, 999999999)]
    [int]$VMId,

    [ValidateNotNullOrEmpty()]
    [string]$Node,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Storage,

    [ValidateRange(1, [int]::MaxValue)]
    [int]$DiskGB = 8,

    [ValidateRange(1, 8192)]
    [int]$Cores,

    [ValidateRange(0.015625, [double]::MaxValue)]
    [double]$MemoryGB,

    [ValidateRange(0, [double]::MaxValue)]
    [double]$SwapGB,

    [ValidateScript({ $_ -is [string] -or $_ -is [securestring] }, ErrorMessage = 'Password must be a string or a SecureString.')]
    [object]$Password,

    [ValidateNotNullOrEmpty()]
    [string[]]$SshPublicKey,

    [switch]$Privileged,

    [ValidateNotNullOrEmpty()]
    [string]$NetworkBridge,

    [ValidateNotNullOrEmpty()]
    [string]$IPAddress = 'dhcp',

    [ValidateNotNullOrEmpty()]
    [string]$Gateway,

    [ValidateNotNullOrEmpty()]
    [string]$IPv6Address,

    [switch]$Nesting,

    [ValidateNotNullOrEmpty()]
    [string]$Pool,

    [ValidateNotNullOrEmpty()]
    [string[]]$Tags,

    [string]$Description,

    [switch]$StartOnBoot,

    [switch]$PowerOn,

    [hashtable]$Parameter,

    [switch]$RunAsync,

    [Alias('Connection')]
    [object]$Server
  )

  foreach ($option in 'IPAddress', 'Gateway', 'IPv6Address') {
    if ($PSBoundParameters.ContainsKey($option) -and -not $NetworkBridge) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message "-$option needs -NetworkBridge." -Target $PSBoundParameters[$option]))
    }
  }
  foreach ($key in 'vmid', 'node') {
    if ($Parameter -and $Parameter.ContainsKey($key)) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message "-Parameter cannot set '$key'; use -VMId or -Node." -Target $Parameter))
    }
  }

  try {
    $connection = Resolve-PVESingleConnection -Server $Server -Reason 'a container is created on exactly one'
    $nodeName = Resolve-PVENodeName -Connection $connection -Node $Node
    $id = Get-PVENewVMId -Connection $connection -VMId $VMId
  }
  catch {
    $PSCmdlet.WriteError($_)
    return
  }

  $body = @{
    vmid       = $id
    hostname   = $Name
    ostemplate = $OSTemplate
    rootfs     = '{0}:{1}' -f $Storage, $DiskGB
  }
  if ($PSBoundParameters.ContainsKey('Cores')) { $body.cores = $Cores }
  if ($PSBoundParameters.ContainsKey('MemoryGB')) { $body.memory = ConvertTo-PVEMiB $MemoryGB }
  if ($PSBoundParameters.ContainsKey('SwapGB')) { $body.swap = ConvertTo-PVEMiB $SwapGB }
  if ($null -ne $Password) {
    $body.password = if ($Password -is [securestring]) { ConvertFrom-PVESecureString -SecureString $Password } else { $Password }
  }
  if ($SshPublicKey) { $body['ssh-public-keys'] = $SshPublicKey -join "`n" }
  $body.unprivileged = if ($Privileged) { 0 } else { 1 }
  if ($NetworkBridge) {
    $net = 'name=eth0,bridge={0},ip={1}' -f $NetworkBridge, $IPAddress
    if ($Gateway) { $net += ',gw={0}' -f $Gateway }
    if ($IPv6Address) { $net += ',ip6={0}' -f $IPv6Address }
    $body.net0 = $net
  }
  if ($Nesting) { $body.features = 'nesting=1' }
  if ($Pool) { $body.pool = $Pool }
  if ($Tags) { $body.tags = $Tags -join ';' }
  if ($PSBoundParameters.ContainsKey('Description')) { $body.description = $Description }
  if ($StartOnBoot) { $body.onboot = 1 }
  if ($PowerOn) { $body.start = 1 }
  if ($Parameter) {
    foreach ($key in $Parameter.Keys) {
      $body[$key] = $Parameter[$key]
    }
  }

  $label = 'Container {0} ({1}) on {2}' -f $id, $Name, $nodeName
  if (-not $PSCmdlet.ShouldProcess($label, 'Create')) {
    return
  }

  $operations = [System.Collections.Generic.List[psobject]]::new()
  try {
    $path = Format-PVEPath '/nodes/{node}/lxc' @{ node = $nodeName }
    $upid = Invoke-PVERequest -Connection $connection -Method POST -Path $path -Parameters $body
  }
  catch {
    $PSCmdlet.WriteError($_)
    return
  }
  Write-Verbose "Create $label`: task $upid"
  $operations.Add([pscustomobject]@{ Upid = [string]$upid; Connection = $connection; Guest = $null; Type = 'lxc'; Node = $nodeName; VMId = $id; Pool = $Pool })
  Complete-PVEOperation -Cmdlet $PSCmdlet -Operation $operations -RunAsync:$RunAsync
}
