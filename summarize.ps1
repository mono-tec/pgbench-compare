<#
.SYNOPSIS
  PostgreSQL ベンチマーク結果(JSON)を集約し、CSVファイルにまとめます。

.DESCRIPTION
  run_pgbench.ps1 により生成された result_*.json を読み取り、
  各実行の概要情報（TPS、レイテンシ、CPU/メモリ平均、HwSensorによる温度/電力/クロック等）を
  1 行 = 1 実行として整形し、results/summary.csv に保存します。

.PARAMETER RawDir
  JSONファイルを格納したディレクトリのパス。既定: ".\results\raw"

.PARAMETER OutCsv
  出力するCSVファイルのパス。既定: ".\results\summary.csv"

.EXAMPLE
  # 標準設定で集計
  pwsh .\summarize.ps1

.EXAMPLE
  # カスタムパスで集計
  pwsh .\summarize.ps1 -RawDir .\benchmarks\raw -OutCsv .\benchmarks\summary.csv

.OUTPUTS
  CSVファイル（UTF-8, BOMなし）。各行は 1 回分のベンチマーク結果。

.NOTES
  - JSONフォーマットは run_pgbench.ps1 に依存します。
  - 公開用セキュリティ配慮のため、sql_file はファイル名のみ（パスは落とす）に統一します。
  - PowerShell 7+ を推奨。
#>
param(
  [string]$RawDir = ".\results\raw",
  [string]$OutCsv   = ".\results\summary.csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

<#
.SYNOPSIS
  ドット区切りのパス文字列で、ネストしたオブジェクトの値を安全に取得します。

.DESCRIPTION
  例: Get-PathValue $json 'workload.duration_s'
  セグメント途中でプロパティが無ければ $null を返します（例外を出しません）。

.PARAMETER Root
  探索を開始するルートオブジェクト（PSCustomObject 等）。

.PARAMETER Path
  'a.b.c' のようなドット区切りのプロパティパス。

.RETURNS
  任意型（見つかれば値、見つからなければ $null）。
#>
function Get-PathValue {
  param([object]$Root, [string]$Path)
  if (-not $Root) { return $null }
  if (-not $Path) { return $null }
  $cur = $Root
  foreach ($seg in $Path.Split('.')) {
    if (-not $cur) { return $null }
    $prop = $cur.PSObject.Properties[$seg]
    if (-not $prop) { return $null }
    $cur = $prop.Value
  }
  return $cur
}

<#
.SYNOPSIS
  IEnumerable を ';' 連結した文字列に畳み込みます（文字列はそのまま返す）。

.DESCRIPTION
  tps_list などの配列を CSV の 1 セルに収める用途。$null は $null のまま返します。

.PARAMETER Value
  文字列または IEnumerable。

.RETURNS
  文字列または $null。
#>
function Join-IfList {
  param([object]$Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [string]) { return $Value }
  if ($Value -is [System.Collections.IEnumerable]) {
    return ($Value | ForEach-Object { $_ }) -join ';'
  }
  return $Value
}

# 対象 JSON を列挙
$files = Get-ChildItem -Path $RawDir -Filter 'result_*.json' -File | Sort-Object Name
if ($files.Count -eq 0) {
  Write-Warning "JSON が見つかりません: $RawDir\result_*.json"
  return
}

# 1ファイル = 1行のオブジェクトに整形
$rows = foreach ($f in $files) {
  try {
    $j = Get-Content -Raw -LiteralPath $f.FullName | ConvertFrom-Json

    # workload
    $tag        = Get-PathValue $j 'workload.tag'
    $profile    = Get-PathValue $j 'workload.profile'
    $duration   = Get-PathValue $j 'workload.duration_s'
    $rounds     = Get-PathValue $j 'workload.rounds'
    $clients    = Get-PathValue $j 'workload.clients'
    $threads    = Get-PathValue $j 'workload.threads'
    $scale      = Get-PathValue $j 'workload.scale'
    $dbname     = Get-PathValue $j 'workload.database'
    $hostName   = Get-PathValue $j 'workload.host'
    $sqlFileRaw = Get-PathValue $j 'workload.sql_file'
    # セキュリティ観点: raw のまま（絶対パスになっていても）CSVには basename のみ
    $sqlFile    = if ($sqlFileRaw) { Split-Path -Leaf $sqlFileRaw } else { $null }

    # results
    $tps_avg    = Get-PathValue $j 'results.tps_avg'
    $tps_median = Get-PathValue $j 'results.tps_median'
    $lat_avg    = Get-PathValue $j 'results.latency_ms_avg'
    $lat_med    = Get-PathValue $j 'results.latency_ms_median'
    $tps_list   = Join-IfList (Get-PathValue $j 'results.tps_list')
    $lat_list   = Join-IfList (Get-PathValue $j 'results.latency_ms_list')

     # ==== perf（基本メトリクス）====
    $cpu_overall = Get-PathValue $j 'perf.cpu_avg_percent_overall'
    $mem_overall = Get-PathValue $j 'perf.mem_available_mb_avg_overall'
    $cpu_pround  = Join-IfList (Get-PathValue $j 'perf.cpu_avg_percent_per_round')
    $mem_pround  = Join-IfList (Get-PathValue $j 'perf.mem_available_mb_avg_per_round')

    # ==== 追加メトリクス（HwSensor）====
    # CPU 温度
    $temp_avg_all = Get-PathValue $j 'perf.cpu_temp_c.avg_overall'
    $temp_max_all = Get-PathValue $j 'perf.cpu_temp_c.max_overall'
    $temp_proundA = Join-IfList (Get-PathValue $j 'perf.cpu_temp_c.avg_per_round')
    $temp_proundM = Join-IfList (Get-PathValue $j 'perf.cpu_temp_c.max_per_round')
    # CPU パッケージ電力
    $pwr_avg_all = Get-PathValue $j 'perf.cpu_package_power_w.avg_overall'
    $pwr_max_all = Get-PathValue $j 'perf.cpu_package_power_w.max_overall'
    $pwr_proundA = Join-IfList (Get-PathValue $j 'perf.cpu_package_power_w.avg_per_round')
    $pwr_proundM = Join-IfList (Get-PathValue $j 'perf.cpu_package_power_w.max_per_round')
    # CPU クロック
    $clk_avg_all = Get-PathValue $j 'perf.cpu_clock_mhz.avg_overall'
    $clk_min_all = Get-PathValue $j 'perf.cpu_clock_mhz.min_overall'
    $clk_proundA = Join-IfList (Get-PathValue $j 'perf.cpu_clock_mhz.avg_per_round')
    $clk_proundN = Join-IfList (Get-PathValue $j 'perf.cpu_clock_mhz.min_per_round')
    # ストレージ温度（任意で存在）
    $st_avg_all  = Get-PathValue $j 'perf.storage_temp_c.avg_overall'
    $st_max_all  = Get-PathValue $j 'perf.storage_temp_c.max_overall'
    $st_proundA  = Join-IfList (Get-PathValue $j 'perf.storage_temp_c.avg_per_round')
    $st_proundM  = Join-IfList (Get-PathValue $j 'perf.storage_temp_c.max_per_round')

    # デバイス（任意で参照）
    $cpu_model = Get-PathValue $j 'device.cpu_model'
    $os_ver    = Get-PathValue $j 'device.os'

    # === 1 行分として出力 ===
    [pscustomobject]@{
      file_name                         = $f.Name
      timestamp                         = Get-PathValue $j 'timestamp'

      tag                               = $tag
      profile                           = $profile
      duration_s                        = $duration
      rounds                            = $rounds
      clients                           = $clients
      threads                           = $threads
      scale                             = $scale
      database                          = $dbname
      host                              = $hostName
      sql_file                          = $sqlFile

      tps_avg                           = $tps_avg
      tps_median                        = $tps_median
      latency_ms_avg                    = $lat_avg
      latency_ms_median                 = $lat_med
      tps_list                          = $tps_list
      latency_ms_list                   = $lat_list

      cpu_avg_percent_overall           = $cpu_overall
      mem_available_mb_avg_overall      = $mem_overall
      cpu_avg_percent_per_round         = $cpu_pround
      mem_available_mb_avg_per_round    = $mem_pround

      cpu_temp_c_avg_overall            = $temp_avg_all
      cpu_temp_c_max_overall            = $temp_max_all
      cpu_temp_c_avg_per_round          = $temp_proundA
      cpu_temp_c_max_per_round          = $temp_proundM

      cpu_package_power_w_avg_overall   = $pwr_avg_all
      cpu_package_power_w_max_overall   = $pwr_max_all
      cpu_package_power_w_avg_per_round = $pwr_proundA
      cpu_package_power_w_max_per_round = $pwr_proundM

      cpu_clock_mhz_avg_overall         = $clk_avg_all
      cpu_clock_mhz_min_overall         = $clk_min_all
      cpu_clock_mhz_avg_per_round       = $clk_proundA
      cpu_clock_mhz_min_per_round       = $clk_proundN

      storage_temp_c_avg_overall        = $st_avg_all
      storage_temp_c_max_overall        = $st_max_all
      storage_temp_c_avg_per_round      = $st_proundA
      storage_temp_c_max_per_round      = $st_proundM

      device_cpu_model                  = $cpu_model
      device_os                         = $os_ver
    }
  }
  catch {
    Write-Warning "読み込み失敗: $($f.FullName) — $($_.Exception.Message)"
  }
}
# --- CSVファイルに書き出し ---
$rows | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
Write-Host "書き出し完了: $OutCsv"
