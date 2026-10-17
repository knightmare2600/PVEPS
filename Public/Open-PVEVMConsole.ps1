function Open-PVEVMConsole {
  <#
  .SYNOPSIS
  Opens the noVNC console of VMs in the default web browser.
  .DESCRIPTION
  Builds the console URL the PVE web interface itself opens (pve-manager's openVNCViewer:
  https://<server>:<port>/?console=kvm&novnc=1&vmid=<id>&vmname=<name>&node=<node>&resize=off&cmd=)
  and opens it with Start-Process, which hands it to the system's default browser. The browser needs its
  own PVE web interface session; the module's connection is not passed to it.

  -UrlOnly writes the URL instead of opening it, for example to open it elsewhere.
  .PARAMETER VMId
  VM ID(s). Binds from piped PVEPS.VM objects.
  .PARAMETER VMName
  VM name(s). Wildcards allowed.
  .PARAMETER UrlOnly
  Write the URL instead of opening a browser.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Open-PVEVMConsole web01
  .EXAMPLE
  Get-PVEVM -VMId 100 | Open-PVEVMConsole -UrlOnly
  #>
  [CmdletBinding(DefaultParameterSetName = 'Id')]
  [OutputType([string])]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [switch]$UrlOnly,

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
      $url = Get-PVEConsoleUrl -Guest $guest -Console kvm
      if ($UrlOnly) {
        $url
        continue
      }
      Write-Verbose "Opening $url"
      try {
        Start-Process -FilePath $url -ErrorAction Stop
      }
      catch {
        $PSCmdlet.WriteError($_)
      }
    }
  }
}
