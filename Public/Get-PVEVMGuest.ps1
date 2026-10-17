function Get-PVEVMGuest {
  <#
  .SYNOPSIS
  Gets what the QEMU guest agent reports from inside VMs: OS, host name and IP addresses.
  .DESCRIPTION
  For each VM, writes one PVEPS.VMGuest object. State is:
  - Running: the agent answered (POST .../agent/ping), and the other properties come from it.
  - AgentNotRunning: the VM runs but the agent did not answer (not installed, not started, or the agent
    option is off in the VM's configuration).
  - VMNotRunning: the VM is not running.

  The details come from the agent's get-osinfo, get-host-name, network-get-interfaces and info calls. An
  older agent that lacks one of them leaves those properties empty. IPAddress lists every address except
  loopback ones; Interfaces has the per-interface detail.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Get-PVEVM web01 | Get-PVEVMGuest
  .EXAMPLE
  Get-PVEVMGuest -VMName '*' | Where-Object State -EQ 'Running' | Select-Object VMName, HostName, OSName, IPAddress
  #>
  [CmdletBinding(DefaultParameterSetName = 'Id')]
  [OutputType('PVEPS.VMGuest')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName
  }

  end {
    foreach ($guest in @(Resolve-PVEGuestTarget -Cmdlet $PSCmdlet -Type qemu -Target $targets)) {
      $info = [ordered]@{
        PSTypeName    = 'PVEPS.VMGuest'
        VMId          = $guest.VMId
        VMName        = $guest.Name
        Node          = $guest.Node
        State         = 'VMNotRunning'
        HostName      = $null
        OSName        = $null
        OSVersion     = $null
        KernelRelease = $null
        IPAddress     = [string[]]@()
        Interfaces    = @()
        AgentVersion  = $null
        Connection    = $guest.Connection
      }
      try {
        $null = Update-PVEGuestStatus -Guest $guest
      }
      catch {
        $PSCmdlet.WriteError($_)
        continue
      }
      if ($guest.Status -eq 'running') {
        try {
          $null = Invoke-PVEAgentRequest -Guest $guest -Command ping -Method POST
          $info.State = 'Running'
        }
        catch {
          Write-Verbose "$(Get-PVEGuestLabel -Guest $guest): the guest agent did not answer: $($_.Exception.Message)"
          $info.State = 'AgentNotRunning'
        }
      }
      if ($info.State -eq 'Running') {
        $calls = @{}
        foreach ($command in 'get-osinfo', 'get-host-name', 'network-get-interfaces', 'info') {
          try {
            $calls[$command] = Invoke-PVEAgentRequest -Guest $guest -Command $command
          }
          catch {
            Write-Verbose "$(Get-PVEGuestLabel -Guest $guest): agent call $command failed: $($_.Exception.Message)"
          }
        }
        $os = $calls['get-osinfo']
        $info.OSName = Get-PVEValue $os 'pretty-name'
        if (-not $info.OSName) {
          $info.OSName = Get-PVEValue $os 'name'
        }
        $info.OSVersion = Get-PVEValue $os 'version'
        $info.KernelRelease = Get-PVEValue $os 'kernel-release'
        $info.HostName = Get-PVEValue $calls['get-host-name'] 'host-name'
        $info.AgentVersion = Get-PVEValue $calls['info'] 'version'
        $interfaces = @(
          foreach ($interface in @($calls['network-get-interfaces'] | Where-Object { $_ })) {
            $addresses = Get-PVEValue $interface 'ip-addresses'
            [pscustomobject]@{
              Name       = Get-PVEValue $interface 'name'
              MacAddress = Get-PVEValue $interface 'hardware-address'
              IPAddress  = [string[]]@(
                @($addresses | Where-Object { $_ }) | ForEach-Object { '{0}/{1}' -f (Get-PVEValue $_ 'ip-address'), (Get-PVEValue $_ 'prefix') }
              )
            }
          }
        )
        $info.Interfaces = $interfaces
        $info.IPAddress = [string[]]@(
          $interfaces | ForEach-Object { $_.IPAddress } | ForEach-Object { ($_ -split '/')[0] } |
            Where-Object { $_ -and $_ -notmatch '^127\.' -and $_ -ne '::1' }
        )
      }
      [pscustomobject]$info
    }
  }
}
