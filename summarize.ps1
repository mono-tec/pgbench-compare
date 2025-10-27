<#
.SYNOPSIS
  PostgreSQL ベンチマーク結果(JSON)を集約し、CSVファイルにまとめます。

.DESCRIPTION
  run_pgbench.ps1 により生成された result_*.json を読み取り、
  各実行の概要情報（TPS、レイテンシ、CPU/メモリ平均など）を1行ずつに整形し、
  results/summary.csv として出力します。

.PARAMETER RawDir
  JSONファイルを格納したディレクトリのパス。
  既定値は ".\results\raw"。

.PARAMETER OutCsv
  出力するCSVファイルのパス。
  既定値は ".\results\summary.csv"。

.EXAMPLE
  # 標準設定で集計
  pwsh .\summarize.ps1

.EXAMPLE
  # カスタムパスで集計
  pwsh .\summarize.ps1 -RawDir .\benchmarks\raw -OutCsv .\benchmarks\summary.csv

.OUTPUTS
  CSVファイル（UTF-8, BOMなし）
  各行は1回分のベンチマーク結果を表します。

.NOTES
  - JSONフォーマットは run_pgbench.ps1 に依存します。
  - summary.csv はZenn掲載やGitHub集約用の整理データとして利用可能です。
#>

param(
  [string]$RawDir = ".\results\raw",
  [string]$OutCsv = ".\results\summary.csv"
)

# --- JSONファイルの一覧を取得し、時系列順に処理 ---
$rows = Get-ChildItem -Path $RawDir -Filter *.json |
  Sort-Object LastWriteTime |
  ForEach-Object {
    $j = Get-Content $_.FullName -Raw | ConvertFrom-Json
    [pscustomobject]@{
      file                         = $_.Name
      timestamp                    = $j.timestamp
      profile                      = $j.workload.profile
      duration_s                   = $j.workload.duration_s
      rounds                       = $j.workload.rounds
      clients                      = $j.workload.clients
      threads                      = $j.workload.threads
      scale                        = $j.workload.scale
      tps_avg                      = $j.results.tps_avg
      tps_median                   = $j.results.tps_median
      latency_ms_avg               = $j.results.latency_ms_avg
      latency_ms_median            = $j.results.latency_ms_median
      cpu_avg_percent_overall      = $j.perf.cpu_avg_percent_overall
      mem_available_mb_avg_overall = $j.perf.mem_available_mb_avg_overall
      cpu_name                     = $j.device.cpu.name
      logical_processors           = $j.device.cpu.logical_processors
      total_memory_mb              = $j.device.memory.total_mb
    }
  }

# --- CSVファイルに書き出し ---
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 $OutCsv
Write-Host "書き出し完了: $OutCsv"
