# Shared by the integration tests that change state (Power, Lifecycle). Dot-source in BeforeAll.
#
# Those tests connect with the write token (PVEPS_TEST_WRITE_TOKEN_ID / _SECRET), whose rights are
# limited to the test pool (see README, "Write tests"), and act only on guests that pass
# Assert-PVETestGuest.

Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'PVEPS.psd1') -Force

function Assert-PVETestGuest {
  # Throws unless the guest is in the test pool and named pveps-test*. Called before any action.
  param([psobject]$Guest, [string]$Kind)
  if (-not $Guest) {
    throw "Test $Kind not found (or not visible to the test token)."
  }
  if ($Guest.Pool -ne $env:PVEPS_TEST_POOL) {
    throw "REFUSING: $Kind $($Guest.VMId) is in pool '$($Guest.Pool)', not '$env:PVEPS_TEST_POOL'."
  }
  if ($Guest.Name -notlike 'pveps-test*') {
    throw "REFUSING: $Kind $($Guest.VMId) is named '$($Guest.Name)'; test guests must be named pveps-test*."
  }
}

function Connect-PVETestWrite {
  # Connects with the write token if the variables are set; does nothing otherwise (the tests skip).
  if (-not ($env:PVEPS_TEST_SERVER -and $env:PVEPS_TEST_WRITE_TOKEN_ID -and $env:PVEPS_TEST_WRITE_TOKEN_SECRET)) {
    return
  }
  $secret = ConvertTo-SecureString -String $env:PVEPS_TEST_WRITE_TOKEN_SECRET -AsPlainText -Force
  $connect = @{
    Server               = $env:PVEPS_TEST_SERVER
    Port                 = if ($env:PVEPS_TEST_PORT) { [int]$env:PVEPS_TEST_PORT } else { 8006 }
    SkipCertificateCheck = $env:PVEPS_TEST_SKIPCERT -eq '1'
    Credential           = [pscredential]::new($env:PVEPS_TEST_WRITE_TOKEN_ID, $secret)
    Token                = $true
  }
  $null = Connect-PVE @connect
}

function Get-PVETestLiveStatus {
  # The live status from status/current, bypassing everything the module computes.
  param([psobject]$Guest)
  (Invoke-PVEApi -Path "/nodes/$($Guest.Node)/$($Guest.Type)/$($Guest.VMId)/status/current" -ErrorAction Stop).status
}
