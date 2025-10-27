#!/usr/bin/env pwsh
#requires -Version 7.0
param([switch]$HideHostName)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# CPU / Memory / OS
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1 Name, NumberOfLogicalProcessors
$cs  = Get-CimInstance Win32_ComputerSystem
$ramMB = [math]::Round($cs.TotalPhysicalMemory / 1MB)
$os = Get-CimInstance Win32_OperatingSystem
$osInfo = "$($os.Caption) $($os.Version)"

# Storage: type only (SSD/HDD/Unspecified)
$storageType = "Unspecified"
try {
  $pd = Get-PhysicalDisk | Select-Object -First 1 MediaType, BusType
  if ($pd -and $pd.MediaType) { $storageType = [string]$pd.MediaType }
} catch {}

# Versions
$pgbenchVersion = $null
$psqlVersion = $null
try { $pgbenchVersion = (& pgbench --version 2>$null).Trim() } catch {}
try { $psqlVersion   = (& psql --version 2>$null).Trim() } catch {}

# Host label (optional)
$label = $env:COMPUTERNAME
if (-not $label -or $label.Trim().Length -eq 0) {
  try { $label = (hostname) } catch { $label = "UNSET" }
}
if ($HideHostName) { $label = "" }

# NOTE: No network names, no drive letters, no user/domain, no model names exported
[ordered]@{
  label              = $label
  cpu_model          = $cpu.Name
  cpu_logical_cores  = $cpu.NumberOfLogicalProcessors
  ram_mb             = $ramMB
  storage_type       = $storageType
  os                 = $osInfo
  postgres_version   = $psqlVersion
  pgbench_version    = $pgbenchVersion
}
