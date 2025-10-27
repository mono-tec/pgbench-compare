<# ========================================================================
  pgbench-compare / run_pgbench.ps1 (TEMPLATE)
  - PowerShell 7 専用ベンチマーク実行スクリプト
  - 事前に prep_db.bat を実行して、secrets/pgpass.local と
    本スクリプト（テンプレ置換版）を生成してください。
  - PostgreSQL の pgbench / psql が PATH に必要です。

  実行例:
    pwsh -NoProfile -ExecutionPolicy Bypass `
      -File .\run_pgbench.ps1 `
      -Workload std -Duration 60 -Rounds 5 -Clients 8 -Threads 8 -Scale 800 -DbName benchdb

  注意:
    - PowerShell 7 以外（Windows PowerShell 5.x）では動きません。
      Windows Terminal で「PowerShell（青アイコン）/ pwsh」を選択。
    - パスワードは secrets/pgpass.local を使用し、本スクリプトやログに出しません。
========================================================================= #>
#requires -Version 7.0

# =========================
# Main: 事前セットアップ
# =========================
param(
  [ValidateSet('std','readonly','writeheavy')]
  [string]$Workload = "std",

  [ValidateRange(1, 86400)]
  [int]$Duration = 60,

  [ValidateRange(1, 1000)]
  [int]$Rounds = 5,

  [ValidateRange(1, 10000)]
  [int]$Clients = 8,

  [ValidateRange(1, 10000)]
  [int]$Threads = 8,

  [ValidateRange(1, 1000000)]
  [int]$Scale = 800,

  [string]$DbName = "benchdb",

  # Postgres connection (← prep_db.bat が置換)
  [string]$DbHost = "#DB_HOST#",
  [int]   $DbPort = #DB_PORT#,
  [string]$DbUser = "#DB_USER#",
  [string]$DbPassword = "",

  [string]$Pgbench = "pgbench",
  [string]$Psql    = "psql",
  [string]$SqlFile = "",
  [switch]$EnsureWriteTable,
  [switch]$HideHostName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"


# =========================
# Helpers: サブ関数群
# =========================

<#
.SYNOPSIS
  パフォーマンスカウンタ（CPU/メモリ）を指定秒数だけ採取するバックグラウンドジョブを開始します。
.DESCRIPTION
  Get-Counter を 1 秒間隔・指定サンプル数で実行し、そのジョブオブジェクトを返します。
  呼び出し側は Receive-Job -Wait -AutoRemoveJob で結果を回収します。
.PARAMETER Counters
  取得するカウンタ配列（省略時は CPU/メモリの2種）
.PARAMETER Seconds
  収集する秒数（=サンプル数）
.RETURN
  Job オブジェクト。完了後に [pscustomobject] @{ Cpu=[double[]]; Mem=[double[]] } を出力
#>
function Get-PerfAverages {
  param(
    [string[]]$Counters = @("\Processor(_Total)\% Processor Time", "\Memory\Available MBytes"),  # ← 既定値を追加（NEW）
    [int]     $Seconds
  )
  $job = Start-Job -ScriptBlock {
    param($Counters, $Seconds)
    # 収集
    $r = Get-Counter -Counter $Counters -SampleInterval 1 -MaxSamples $Seconds -ErrorAction Stop
    $samples = @($r.CounterSamples)

    # "Path" を持つ要素のみ対象にし、数値配列だけ返す（安全）
    $cpu = @(
      $samples |
        Where-Object { $_ -and $_.PSObject.Properties.Match('Path') } |
        Where-Object { $_.Path -like '*\Processor(_Total)\% Processor Time' } |
        Select-Object -ExpandProperty CookedValue -ErrorAction SilentlyContinue
    )
    $mem = @(
      $samples |
        Where-Object { $_ -and $_.PSObject.Properties.Match('Path') } |
        Where-Object { $_.Path -like '*\Memory\Available MBytes' } |
        Select-Object -ExpandProperty CookedValue -ErrorAction SilentlyContinue
    )

    [pscustomobject]@{ Cpu=$cpu; Mem=$mem }
  } -ArgumentList ($Counters, $Seconds)

  return $job
}

<#
.SYNOPSIS
  数値配列の中央値を返します。
.DESCRIPTION
  配列をソートして中央要素（偶数個の場合は中央2要素の平均）を返します。空配列の時は 0。
.PARAMETER arr
  [double[]] 数値配列
.RETURNS
  [double] 中央値
#>
function Get-Median([double[]]$arr) {
  if ($arr.Count -eq 0) { return 0 }
  $sorted = $arr | Sort-Object
  $mid = [int]([math]::Floor($sorted.Count/2))
  if ($sorted.Count % 2 -eq 1) { return $sorted[$mid] }
  else { return [Math]::Round( ($sorted[$mid-1] + $sorted[$mid]) / 2, 3 ) }
}

# --- パスワード解決: -DbPassword > $env:PGPASSWORD > secrets/pgpass.local ---
$resolvedPassword = $DbPassword
if (-not $resolvedPassword -and $env:PGPASSWORD) { $resolvedPassword = $env:PGPASSWORD }
if (-not $resolvedPassword) {
  $pgpassPath = Join-Path $PSScriptRoot "secrets/pgpass.local"
  if (Test-Path $pgpassPath) {
    $line = Get-Content $pgpassPath | Where-Object { $_ -and ($_ -notmatch '^\s*#') } | Select-Object -First 1
    if ($line) {
      $parts = $line.Split(':', 5)
      if ($parts.Count -ge 5) {
        if (-not $DbHost  -or $DbHost  -eq "") { $DbHost  = $parts[0] }
        if (-not $DbPort                 )     { $DbPort  = [int]$parts[1] }
        if (-not $DbName -or $DbName -eq "")   { $DbName  = $parts[2] }
        if (-not $DbUser -or $DbUser -eq "")   { $DbUser  = $parts[3] }
        $resolvedPassword = $parts[4]
      }
    }
  }
}

# --- PGPASSWORD をセッションスコープで設定（finally で必ず復元） ---
$__prevPwd = $env:PGPASSWORD
if ($resolvedPassword) { $env:PGPASSWORD = $resolvedPassword }

try {
  # 出力ディレクトリ（スクリプトのルート直下に results を作成）
  $OutDir = Join-Path -Path $PSScriptRoot -ChildPath "results"
  $LogDir = Join-Path $OutDir "logs"
  $RawDir = Join-Path $OutDir "raw"
  $null = New-Item -ItemType Directory -Force -Path $LogDir, $RawDir | Out-Null

  # タグを決定（SqlFile 指定時はファイル名ベース、未指定時は Workload）
  $tag = if ($SqlFile) { (Split-Path $SqlFile -LeafBase) } else { $Workload }   # ← NEW

  $ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
  $logPath  = Join-Path $LogDir ("pgbench_{0}_{1}.log"  -f $tag, $ts)           # ← tag を反映済
  $jsonPath = Join-Path $RawDir ("result_{0}_{1}.json"   -f $tag, $ts)           # ← tag を反映済

  Write-Host "[INFO] pgbench ベンチマーク開始: Workload=$Workload Duration=$Duration Rounds=$Rounds"
  "[INFO] Workload=$Workload Duration=$Duration Rounds=$Rounds HideHostName=$HideHostName DbHost=$DbHost DbPort=$DbPort DbUser=$DbUser" |
    Out-File -FilePath $logPath -Encoding UTF8

  # ツール存在チェック + 版数ログ
  foreach ($tool in @($Pgbench, $Psql)) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
      throw "実行ファイルが見つかりません: $tool  （PATHを通すかフルパスを指定してください）"
    }
  }
  ("[INFO] " + (& $Pgbench --version)) | Tee-Object -FilePath $logPath -Append
  ("[INFO] " + (& $Psql --version))    | Tee-Object -FilePath $logPath -Append

  # システム情報
  $sysInfo = & "$PSScriptRoot/Get-SysInfo.ps1" -HideHostName:$HideHostName

  # writeheavy 用の DDL（任意）
  if ($EnsureWriteTable) {
    $createSql = Join-Path $PSScriptRoot "workloads/create_writeheavy.sql"
    if (-not (Test-Path $createSql)) { throw "create_writeheavy.sql が見つかりません: $createSql" }
    "[STEP] prehook: $Psql -h $DbHost -p $DbPort -U $DbUser -d $DbName -f $createSql" | Tee-Object -FilePath $logPath -Append
    & $Psql -h $DbHost -p $DbPort -U $DbUser -d $DbName -f $createSql 2>&1 | Tee-Object -FilePath $logPath -Append
  }

  # pgbench 初期化
  "[STEP] init: $Pgbench -h $DbHost -p $DbPort -U $DbUser -i -s $Scale $DbName" | Tee-Object -FilePath $logPath -Append
  & $Pgbench -h $DbHost -p $DbPort -U $DbUser -i -s $Scale $DbName 2>&1 | Tee-Object -FilePath $logPath -Append
  "[*hint] init 失敗時は DB 作成・接続先・認証・pgpass を確認してください。" | Tee-Object -FilePath $logPath -Append  # ← ヒントを追記（NEW）

  # 収集カウンタ（呼び出し側で省略可だが明示しておく）
  $counters = @("\Processor(_Total)\% Processor Time", "\Memory\Available MBytes")

  # 結果バッファ
  $tpsList = New-Object System.Collections.Generic.List[double]
  $latList = New-Object System.Collections.Generic.List[double]
  $cpuAvgs = New-Object System.Collections.Generic.List[double]
  $memAvgs = New-Object System.Collections.Generic.List[double]

  # =========================
  # Main: ベンチマーク本体
  # =========================
  for ($r=1; $r -le $Rounds; $r++) {
    Write-Host "[RUN $r/$Rounds] 同時計測開始"
    $perfJob = Get-PerfAverages -Seconds $Duration   # ← 既定カウンタを使うので短縮（NEW）

    if ($SqlFile -and (Test-Path $SqlFile)) {
      $cmdDesc = "pgbench -h $DbHost -p $DbPort -U $DbUser -f $SqlFile -c $Clients -j $Threads -T $Duration $DbName"
      $args = @("-h",$DbHost,"-p",$DbPort,"-U",$DbUser,"-f",$SqlFile,"-c",$Clients,"-j",$Threads,"-T",$Duration,$DbName)
    }
    elseif ($Workload -eq "readonly") {
      $cmdDesc = "pgbench -h $DbHost -p $DbPort -U $DbUser -S -c $Clients -j $Threads -T $Duration $DbName"
      $args = @("-h",$DbHost,"-p",$DbPort,"-U",$DbUser,"-S","-c",$Clients,"-j",$Threads,"-T",$Duration,$DbName)
    }
    else {
      $cmdDesc = "pgbench -h $DbHost -p $DbPort -U $DbUser -c $Clients -j $Threads -T $Duration $DbName"
      $args = @("-h",$DbHost,"-p",$DbPort,"-U",$DbUser,"-c",$Clients,"-j",$Threads,"-T",$Duration,$DbName)
    }

    "[RUN] $cmdDesc" | Tee-Object -FilePath $logPath -Append
    & $Pgbench @args 2>&1 | Tee-Object -FilePath $logPath -Append

    # --- ここからパフォーマンスの受け取り（安全版） ---
    $perf = Receive-Job -Job $perfJob -Wait -AutoRemoveJob
    Stop-Job   -Job $perfJob -ErrorAction SilentlyContinue
    Remove-Job -Job $perfJob -ErrorAction SilentlyContinue

    $cpuVals = if ($perf -and $perf.PSObject.Properties.Match('Cpu')) { @($perf.Cpu) } else { @() }
    $memVals = if ($perf -and $perf.PSObject.Properties.Match('Mem')) { @($perf.Mem) } else { @() }

    if (-not $cpuVals -or $cpuVals.Count -eq 0) { $cpuVals = @(0) }
    if (-not $memVals -or $memVals.Count -eq 0) { $memVals = @(0) }

    $cpuAvg = [Math]::Round((($cpuVals | Measure-Object -Average).Average) ?? 0, 2)
    $memAvg = [Math]::Round((($memVals | Measure-Object -Average).Average) ?? 0, 2)
    $cpuAvgs.Add($cpuAvg) | Out-Null
    $memAvgs.Add($memAvg) | Out-Null
    # --- ここまで ---

    $lastTps = Select-String -Path $logPath -Pattern '\btps\s*=\s*([0-9]+(?:\.[0-9]+)?)' | Select-Object -Last 1
    $tpsVal  = if ($lastTps) { [double]$lastTps.Matches[0].Groups[1].Value } else { 0 }

    $lastLat = Select-String -Path $logPath -Pattern 'latency\s+average\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*ms' | Select-Object -Last 1
    $latVal  = if ($lastLat) { [double]$lastLat.Matches[0].Groups[1].Value } else { 0 }

    $tpsList.Add($tpsVal) | Out-Null
    $latList.Add($latVal) | Out-Null

    # 完了サマリ行（grepしやすい1行要約） ← NEW
    "[DONE $r/$Rounds] CPU.avg=${cpuAvg}%  Mem.avg=${memAvg}MB  TPS=${tpsVal}  Lat(ms)=${latVal}" |
      Tee-Object -FilePath $logPath -Append

    "" | Add-Content -Path $logPath
  }

  # 集約
  $tpsAvg    = [Math]::Round( ($tpsList | Measure-Object -Average).Average, 3 )
  $latAvg    = [Math]::Round( ($latList | Measure-Object -Average).Average, 3 )
  $tpsMed    = Get-Median $tpsList.ToArray()
  $latMed    = Get-Median $latList.ToArray()
  $cpuAvgAll = [Math]::Round( ($cpuAvgs | Measure-Object -Average).Average, 2 )
  $memAvgAll = [Math]::Round( ($memAvgs | Measure-Object -Average).Average, 2 )

  # SqlFile は絶対パスに解決（失敗時は元の文字列を残す） ← NEW
  $sqlPathForJson = if ($SqlFile) {
    try { (Resolve-Path -LiteralPath $SqlFile).Path } catch { $SqlFile }
  } else { $null }

  $result = [ordered]@{
    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    workload  = @{
      tag         = $tag                    # ← JSON にタグを追加（NEW）
      profile     = $Workload
      duration_s  = $Duration
      rounds      = $Rounds
      clients     = $Clients
      threads     = $Threads
      scale       = $Scale
      database    = $DbName
      sql_file    = $sqlPathForJson        # ← 安全に格納
      hide_hostname = [bool]$HideHostName
      host        = $DbHost
      port        = $DbPort
      user        = $DbUser
    }
    results = @{
      tps_list           = $tpsList
      tps_avg            = $tpsAvg
      tps_median         = $tpsMed
      latency_ms_list    = $latList
      latency_ms_avg     = $latAvg
      latency_ms_median  = $latMed
    }
    perf = @{
      cpu_avg_percent_overall        = $cpuAvgAll
      mem_available_mb_avg_overall   = $memAvgAll
      cpu_avg_percent_per_round      = $cpuAvgs
      mem_available_mb_avg_per_round = $memAvgs
    }
    device = $sysInfo
  }

  $result | ConvertTo-Json -Depth 6 | Out-File -FilePath $jsonPath -Encoding UTF8
  Write-Host "[INFO] 完了: $jsonPath"
}
finally {
  # Restore PGPASSWORD（必ず実行）
  if ($resolvedPassword) {
    if ($null -ne $__prevPwd) { $env:PGPASSWORD = $__prevPwd }
    else { Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue }
  }
}
