function Remove-PVEContainerVolume {
  <#
  .SYNOPSIS
  Detaches mount points from LXC containers, or deletes their volumes.
  .DESCRIPTION
  By default the mount point is removed with PUT /nodes/{node}/lxc/{vmid}/config (delete=mpN). For a
  volume mount point PVE keeps the volume as an unusedN entry, so its data survives. -DeletePermanently
  then deletes that unusedN entry as well, to delete the volume; that cannot be undone. (For VMs the API
  documents that removing an unusedN entry always removes the volume physically; for containers this is
  unverified until the lifecycle integration test checks the storage content.) A bind mount has no
  volume; removing it only removes the entry.

  The root file system cannot be removed. Prompts for confirmation by default (ConfirmImpact High). On a
  running container the removal can be pending until the next start; a warning says so, and
  -DeletePermanently then cannot find the unused entry until the container has restarted. Writes nothing.
  .PARAMETER VMId
  Container ID. Binds from piped PVEPS.ContainerVolume objects.
  .PARAMETER VMName
  Container name(s). Wildcards allowed.
  .PARAMETER Device
  Mount point(s) to remove, for example mp1. Binds from piped PVEPS.ContainerVolume objects.
  .PARAMETER DeletePermanently
  Delete the volume instead of keeping it as an unused entry.
  .PARAMETER Server
  Connection(s) to use. Defaults to the default connection; binds from piped objects.
  .EXAMPLE
  Remove-PVEContainerVolume -VMId 200 -Device mp1
  .EXAMPLE
  Get-PVEContainerVolume -VMId 200 -Device mp2 | Remove-PVEContainerVolume -DeletePermanently -Confirm:$false
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on this cmdlet through $PSCmdlet by Invoke-PVEGuestChange.')]
  [CmdletBinding(DefaultParameterSetName = 'Id', SupportsShouldProcess, ConfirmImpact = 'High')]
  [OutputType([void])]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Id', ValueFromPipelineByPropertyName)]
    [ValidateRange(100, 999999999)]
    [int[]]$VMId,

    [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0)]
    [SupportsWildcards()]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Device,

    [switch]$DeletePermanently,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Connection')]
    [object[]]$Server
  )

  begin {
    $targets = [System.Collections.Generic.List[psobject]]::new()
  }

  process {
    Add-PVEGuestTarget -Cmdlet $PSCmdlet -Target $targets -Server $Server -VMId $VMId -Name $VMName -Device $Device
  }

  end {
    foreach ($selection in @(Resolve-PVEDeviceTarget -Cmdlet $PSCmdlet -Type lxc -Target $targets -Kind ContainerVolume -Noun 'volume')) {
      $guest = $selection.Guest
      foreach ($volume in $selection.Devices) {
        $label = '{0} {1}' -f (Get-PVEGuestLabel -Guest $guest), $volume.Device
        if ($volume.Device -eq 'rootfs') {
          $PSCmdlet.WriteError((New-PVEArgumentError -Message "$label is the root file system and cannot be removed." -Target $volume))
          continue
        }
        $description = if ($volume.IsBindMount) { "Remove bind mount $($volume.Device) ($($volume.Volume) at $($volume.Path))" } else { "Detach mount point $($volume.Device) ($($volume.Volume) at $($volume.Path))" }
        Remove-PVEGuestDevice -Cmdlet $PSCmdlet -Guest $guest -Device $volume.Device -Kind ContainerVolume -Description $description
        if (-not $DeletePermanently -or $volume.IsBindMount) {
          continue
        }

        try {
          $config = Get-PVEGuestConfig -Guest $guest
        }
        catch {
          $PSCmdlet.WriteError($_)
          continue
        }
        if (@(Get-PVEConfigKey -Config $config) -contains $volume.Device) {
          # Still configured: the detach failed, was declined, or is pending on the running container.
          continue
        }
        $unused = Get-PVEConfigKey -Config $config | Where-Object {
          $_ -match '^unused\d+$' -and (ConvertFrom-PVEPropertyString -Value ([string](Get-PVEValue $config $_)) -DefaultKey volume)['volume'] -eq $volume.Volume
        } | Select-Object -First 1
        if (-not $unused) {
          Write-Warning "$label`: no unused entry for $($volume.Volume) was found, so the volume was not deleted."
          continue
        }
        $body = @{ delete = $unused; digest = Get-PVEValue $config 'digest' }
        $null = Invoke-PVEGuestChange -Cmdlet $PSCmdlet -Guest $guest -Description "Delete volume $($volume.Volume) ($unused)" -Body $body
      }
    }
  }
}
