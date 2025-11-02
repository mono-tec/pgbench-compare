#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
  実行環境の基本情報（CPU/メモリ/OS/ストレージ種別/pgbench・psqlのバージョン）を取得して出力します。

.DESCRIPTION
  Windows の CIM と一部コマンドのバージョン出力を用いて、以下の情報を収集します。
   - CPU モデル名 / 論理コア数
   - 物理メモリ容量（MB）
   - OS 名とバージョン
   - ストレージ種別（SSD/HDD/Unspecified）
   - pgbench / psql のバージョン（PATH にある場合）
   - ホスト名ラベル（非表示にすることも可能）

.PARAMETER HideHostName
  出力の label フィールド（ホスト名）を空文字にします。公開用JSON等でホスト名を隠したい場合に使用します。

.OUTPUTS
  PSCustomObject
  次のキーを持つオブジェクトを 1 件出力:
    label, cpu_model, cpu_logical_cores, ram_mb, storage_type, os,
    postgres_version, pgbench_version

.EXAMPLE
  pwsh .\Get-SysInfo.ps1
  # 収集結果オブジェクトを出力

.EXAMPLE
  pwsh .\Get-SysInfo.ps1 -HideHostName
  # label を空にして出力（公開用）

.NOTES
  - 管理者権限は不要です（ただし環境により一部のクエリが失敗する場合があります）。
  - 失敗時は該当フィールドを $null / "Unspecified" にフォールバックします。
#>
param([switch]$HideHostName)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- CPU / Memory / OS -------------------------------------------------------
# 可能な限り安全に情報取得。失敗してもスクリプト全体は止めずに $null を入れる。
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1 Name, NumberOfLogicalProcessors
$cs  = Get-CimInstance Win32_ComputerSystem
$ramMB = [math]::Round($cs.TotalPhysicalMemory / 1MB)
$os = Get-CimInstance Win32_OperatingSystem
$osInfo = "$($os.Caption) $($os.Version)"

# --- Storage: type only (SSD/HDD/Unspecified) --------------------------------
$storageType = "Unspecified"
try {
  $pd = Get-PhysicalDisk | Select-Object -First 1 MediaType, BusType
  if ($pd -and $pd.MediaType) { $storageType = [string]$pd.MediaType }
} catch {}

# --- Versions (pgbench / psql が PATH にある場合のみ) -------------------------
$pgbenchVersion = $null
$psqlVersion = $null
try { $pgbenchVersion = (& pgbench --version 2>$null).Trim() } catch {}
try { $psqlVersion   = (& psql --version 2>$null).Trim() } catch {}

# --- Host label (optional) ----------------------------------------------------
$label = $env:COMPUTERNAME
if (-not $label -or $label.Trim().Length -eq 0) {
  try { $label = (hostname) } catch { $label = "UNSET" }
}
if ($HideHostName) { $label = "" }

# --- 出力（公開用途を意識し、ネットワーク名/ドライブ/ユーザ/ドメイン等は含めない） --
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
