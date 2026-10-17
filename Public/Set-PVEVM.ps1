function Set-PVEVM {
  <#
  .SYNOPSIS
  Changes the configuration of QEMU virtual machines.
  .DESCRIPTION
  Sends the changes with POST /nodes/{node}/qemu/{vmid}/config, waits for the task, and writes each VM
  with its live status.

  On a running VM, PVE either applies a change at once or stores it as pending until the VM is next
  started, depending on the option and the VM's hotplug settings. After the change, a warning lists the
  options still pending on a running VM (read from GET .../pending).

  Only the options given are changed. -Parameter reaches any other option by its API name.
  .PARAMETER Name
  VM name(s). Wildcards allowed.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER IncludeTemplate
  Let -Name match templates as well as VMs.
  .PARAMETER NewName
  New name for the VM. Only allowed when exactly one VM is targeted.
  .PARAMETER Cores
  Cores per socket.
  .PARAMETER Sockets
  CPU sockets.
  .PARAMETER MemoryGB
  Memory in GiB, sent to PVE in whole MiB.
  .PARAMETER CpuType
  Emulated CPU type, for example host or x86-64-v2-AES.
  .PARAMETER OSType
  Guest OS type (see New-PVEVM).
  .PARAMETER Description
  Description (notes). An empty string removes it.
  .PARAMETER Tags
  Tags, replacing the current ones. An empty array removes all tags.
  .PARAMETER StartOnBoot
  Whether the VM starts when the node boots.
  .PARAMETER Protection
  Whether the protection flag is set. While set, PVE refuses to delete the VM or its disks.
  .PARAMETER GuestAgent
  Whether the QEMU guest agent device is enabled.
  .PARAMETER Parameter
  Further options by their API names, for example @{ balloon = 2048 }. Applied last.
  .PARAMETER Delete
  Option names to remove from the configuration, so their PVE defaults apply, for example 'balloon'.
  .PARAMETER RunAsync
  Return the task(s) at once instead of waiting.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Set-PVEVM -VMId 100 -Cores 4 -MemoryGB 8
  .EXAMPLE
  Get-PVEVM -Name 'web*' | Set-PVEVM -Tags web, production -StartOnBoot $true
  .EXAMPLE
  Set-PVEVM web01 -NewName web01-old -Protection $false
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestOperation.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'Medium')]
  [OutputType('PVEPS.VM', 'PVEPS.Task')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Name,

    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(ParameterSetName = 'Name')]
    [switch]$IncludeTemplate,

    [ValidateNotNullOrEmpty()]
    [string]$NewName,

    [ValidateRange(1, [int]::MaxValue)]
    [int]$Cores,

    [ValidateRange(1, [int]::MaxValue)]
    [int]$Sockets,

    [ValidateRange(0.015625, [double]::MaxValue)]
    [double]$MemoryGB,

    [ValidateNotNullOrEmpty()]
    [string]$CpuType,

    [ValidateSet('other', 'wxp', 'w2k', 'w2k3', 'w2k8', 'wvista', 'win7', 'win8', 'win10', 'win11', 'l24', 'l26', 'solaris')]
    [string]$OSType,

    [AllowEmptyString()]
    [string]$Description,

    [AllowEmptyCollection()]
    [string[]]$Tags,

    [bool]$StartOnBoot,

    [bool]$Protection,

    [bool]$GuestAgent,

    [hashtable]$Parameter,

    [ValidateNotNullOrEmpty()]
    [string[]]$Delete,

    [switch]$RunAsync,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $body = @{}
    $remove = [System.Collections.Generic.List[string]]::new()
    if ($NewName) { $body.name = $NewName }
    if ($PSBoundParameters.ContainsKey('Cores')) { $body.cores = $Cores }
    if ($PSBoundParameters.ContainsKey('Sockets')) { $body.sockets = $Sockets }
    if ($PSBoundParameters.ContainsKey('MemoryGB')) { $body.memory = ConvertTo-PVEMiB $MemoryGB }
    if ($CpuType) { $body.cpu = $CpuType }
    if ($OSType) { $body.ostype = $OSType }
    if ($PSBoundParameters.ContainsKey('Description')) {
      if ($Description) { $body.description = $Description } else { $remove.Add('description') }
    }
    if ($PSBoundParameters.ContainsKey('Tags')) {
      if ($Tags) { $body.tags = $Tags -join ';' } else { $remove.Add('tags') }
    }
    if ($PSBoundParameters.ContainsKey('StartOnBoot')) { $body.onboot = $StartOnBoot }
    if ($PSBoundParameters.ContainsKey('Protection')) { $body.protection = $Protection }
    if ($PSBoundParameters.ContainsKey('GuestAgent')) { $body.agent = [int]$GuestAgent }
    if ($Parameter) {
      foreach ($key in $Parameter.Keys) {
        $body[$key] = $Parameter[$key]
      }
    }
    foreach ($key in $Delete) {
      $remove.Add($key)
    }
    if ($remove.Count -gt 0) {
      $body.delete = $remove -join ','
    }
    if ($body.Count -eq 0) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message 'No change given; specify at least one setting.' -Target $null))
    }
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $Name
  }

  end {
    $guests = @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets -IncludeTemplate:$IncludeTemplate)
    if ($NewName -and $guests.Count -gt 1) {
      $PSCmdlet.ThrowTerminatingError((New-PVEArgumentError -Message "-NewName gives one name, but $($guests.Count) VMs are targeted; nothing was changed." -Target $guests))
    }
    $action = 'Set {0}' -f (@($body.Keys | Sort-Object) -join ', ')
    foreach ($guest in @(Invoke-PVEGuestOperation -Cmdlet $PSCmdlet -Guest $guests -Description $action -Method POST -Suffix '/config' -Parameters $body -RunAsync:$RunAsync)) {
      if (-not $RunAsync) {
        try {
          Write-PVEPendingWarning -Guest $guest
        }
        catch {
          $PSCmdlet.WriteError($_)
        }
      }
      $guest
    }
  }
}
