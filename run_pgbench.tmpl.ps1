<# ========================================================================
  pgbench-compare / run_pgbench.ps1 (TEMPLATE, single-file with HwSensorCli)
  - PowerShell 7 専用ベンチマーク実行スクリプト
  - 事前に prep_db.bat を実行して、本スクリプト（テンプレ置換版）を生成してください。
  - PostgreSQL の pgbench / psql が PATH に必要です。
  - HwSensorCli.exe（管理者権限で温度・電力・クロック取得）を同フォルダへ

  実行例（お試し短縮版：5秒×1回・規模10）:
    pwsh -NoProfile -ExecutionPolicy Bypass `
      -File .\run_pgbench.ps1 `
      -Workload readonly -Duration 5 -Rounds 1 -Clients 1 -Threads 1 -Scale 10 -DbName benchdb `
      -EnableHwSensors -HideHostName
   
  注意:
    - PowerShell 7 以外（Windows PowerShell 5.x）では動きません。
      Windows Terminal で「PowerShell（青アイコン）/ pwsh」を選択。
    - prep_db.bat で埋め込まれた接続情報を使用します。
    - 本スクリプトは .gitignore 対象です（パスワードはGit管理外）。
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

  # Postgres connection (← prep_db.bat が置換)
  [string]$DbHost = "#DB_HOST#",
  [int]   $DbPort = #DB_PORT#,
  [string]$DbName = "#DB_NAME#",
  [string]$DbUser = "#DB_USER#",
  [string]$DbPassword = "#DB_PASS#",

  [string]$Pgbench = "pgbench",
  [string]$Psql    = "psql",
  [string]$SqlFile = "",
  [switch]$EnsureWriteTable,
  [switch]$HideHostName,

  # --- HwSensor 連携（単一ファイル内に統合） ---
  [switch]$EnableHwSensors,
  [string]$HwSensorCli = ".\tool\HwSensorCli.exe",
  [switch]$IncludeStorageTemp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
# =========================
# Helpers: サブ関数群
# =========================
<#
.SYNOPSIS
  CPU/メモリのパフォーマンスカウンタをバックグラウンドジョブで収集します。

.DESCRIPTION
  Get-Counter を 1 秒おきに指定サンプル数だけ取得し、完了時に
  [pscustomobject]@{ Cpu=[double[]]; Mem=[double[]] } を「ジョブ出力」として返します。
  呼び出し側では Receive-Job -Wait -AutoRemoveJob で結果を受け取ります。

.PARAMETER Counters
  取得するカウンタ名の配列。既定は CPU とメモリの 2 種類。

.PARAMETER Seconds
  収集する秒数（=サンプル数）。

.RETURNS
  [System.Management.Automation.Job] 収集ジョブ。
  受け取り時の出力は @{Cpu=[double[]]; Mem=[double[]]}。
#>
function Get-PerfAverages {
  param(
    [string[]]$Counters = @("\Processor(_Total)\% Processor Time", "\Memory\Available MBytes"),
    [int]$Seconds
  )
  Start-Job -ScriptBlock {
    param($Counters, $Seconds)
    $r = Get-Counter -Counter $Counters -SampleInterval 1 -MaxSamples $Seconds -ErrorAction Stop
    $samples = @($r.CounterSamples)

     # CookedValue を2系統に分離（Path がヒットするものだけ安全に抽出）
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
}
<#
.SYNOPSIS
  数値配列の中央値（median）を返します。

.DESCRIPTION
  配列を昇順ソートして中央値を返します。要素数が偶数の場合は
  中央2要素の平均を小数第3位で丸めて返します。空や $null は 0 を返します。

.PARAMETER arr
  中央値を求める [double[]] 配列。

.RETURNS
  [double] 中央値。
#>
function Get-Median {
  param([double[]]$arr)

  if (-not $arr -or $arr.Count -eq 0) { return 0 }

  # 「必ず配列化」しておくと Count/インデクサが安定する
  $sorted = @($arr | Sort-Object)

  $n   = $sorted.Length
  $mid = [int]([math]::Floor($n / 2))
  if ($n % 2 -eq 1) {
    return [double]$sorted[$mid]
  } else {
    $a = [double]$sorted[$mid-1]
    $b = [double]$sorted[$mid]
    return [math]::Round( ($a + $b) / 2, 3 )
  }
}


<#
.SYNOPSIS  配列の平均（null は 0 扱い、空は 0 を返す）を返します。#>
function Mean0([double[]]$a) {
  if (-not $a) { return 0 }
  $v = @($a | ForEach-Object { if ($_ -eq $null) { 0 } else { $_ } })
  if ($v.Count -eq 0) { 0 } else { [Math]::Round( ($v | Measure-Object -Average).Average, 3 ) }
}
<#
.SYNOPSIS  配列の最大（null は 0 扱い、空は 0 を返す）を返します。#>
function Max0([double[]]$a) {
  if (-not $a) { return 0 }
  $v = @($a | ForEach-Object { if ($_ -eq $null) { 0 } else { $_ } })
  if ($v.Count -eq 0) { 0 } else { [Math]::Round( ($v | Measure-Object -Maximum).Maximum, 3 ) }
}
<#
.SYNOPSIS  配列の最小（null は 0 扱い、空は 0 を返す）を返します。#>
function Min0([double[]]$a) {
  if (-not $a) { return 0 }
  $v = @($a | ForEach-Object { if ($_ -eq $null) { 0 } else { $_ } })
  if ($v.Count -eq 0) { 0 } else { [Math]::Round( ($v | Measure-Object -Minimum).Minimum, 3 ) }
}

<#
.SYNOPSIS
  HwSensorCli を 1 秒間隔で指定秒数だけ実行し、温度/電力/クロック/（任意で）ストレージ温度を収集します。

.DESCRIPTION
  指定の EXE を Mode 引数（1=温度, 2=CPUパッケージ電力, 3=クロックMHz, 4=ストレージ温度）で呼び出します。
  収集はバックグラウンドジョブで行い、完了後に以下の形で出力を返します：
    [pscustomobject]@{ Temp=[double[]]; Power=[double[]]; Clock=[double[]]; StorageTemp=[double[]] }

  ※ LibreHardwareMonitor の仕様上、CPU温度/電力などは管理者権限が必要な環境があります。
  ※ 依存 DLL は .\tool 配下に設置してください（EXE と同ディレクトリ）。

.PARAMETER Seconds
  収集秒数。

.PARAMETER Exe
  HwSensorCli.exe へのパス。相対パスなら .\tool\HwSensorCli.exe を自動探索します。

.PARAMETER IncludeStorage
  ストレージ温度の収集を有効化します（Mode=4）。収集不可の場合は null を格納します。

.RETURNS
  [System.Management.Automation.Job] 収集ジョブ。
  受け取り時の出力は @{Temp=[double[]]; Power=[double[]]; Clock=[double[]]; StorageTemp=[double[]]}。
#>
function Start-HwSensorJob {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][int]$Seconds,
    [string]$Exe = "HwSensorCli.exe",
    [switch]$IncludeStorage
  )

  ## 相対パスが渡された場合は .\tool\HwSensorCli.exe を自動採用
  if (-not (Test-Path $Exe)) {
    $toolPath = Join-Path $PSScriptRoot "tool\HwSensorCli.exe"
    if (Test-Path $toolPath) { $Exe = $toolPath }
  }

  Start-Job -ScriptBlock {
    param($Seconds, $Exe, $IncludeStorage)

    # 単一サンプル取得（JSON から .value を取り出す）※失敗時は $null
    function Invoke-Hw {
      param(
        [Parameter(Mandatory)][string]$Exe,
        [Parameter(Mandatory)][int]$Mode
      )
      try {
        $raw = & $Exe $Mode 2>$null
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        ($raw | ConvertFrom-Json -ErrorAction Stop).value
      } catch { $null }
    }

    # 収集用コンテナ（ArrayList）
    $temp = New-Object System.Collections.ArrayList
    $pwr  = New-Object System.Collections.ArrayList
    $clk  = New-Object System.Collections.ArrayList
    $st   = New-Object System.Collections.ArrayList

    for ($i=0; $i -lt $Seconds; $i++) {
      # ここをすべて “( … )” で包む ＆ 名前付き引数にする
      [void]$temp.Add( (Invoke-Hw -Exe $Exe -Mode 1) )  # cpu_temp_c (C)
      [void]$pwr.Add(  (Invoke-Hw -Exe $Exe -Mode 2) )  # cpu_package_power_w (W)
      [void]$clk.Add(  (Invoke-Hw -Exe $Exe -Mode 3) )  # cpu_clock_mhz (MHz)
      if ($IncludeStorage) {
        [void]$st.Add( (Invoke-Hw -Exe $Exe -Mode 4) )  # storage_temp_c
      } else {
        [void]$st.Add($null)
      }
      Start-Sleep -Seconds 1
    }

    [pscustomobject]@{
      Temp        = @($temp)
      Power       = @($pwr)
      Clock       = @($clk)
      StorageTemp = @($st)
    }
  } -ArgumentList $Seconds, $Exe, $IncludeStorage
}

function Summarize-HwRound {
  param([double[]]$Temp,[double[]]$Power,[double[]]$Clock,[double[]]$Storage)
  [pscustomobject]@{
    cpu_temp     = [pscustomobject]@{ avg = (Mean0 $Temp);    max = (Max0  $Temp) }
    cpu_power    = [pscustomobject]@{ avg = (Mean0 $Power);   max = (Max0  $Power) }
    cpu_clock    = [pscustomobject]@{ avg = (Mean0 $Clock);   min = (Min0  $Clock) }
    storage_temp = [pscustomobject]@{ avg = (Mean0 $Storage); max = (Max0  $Storage) }
  }
}

 # =========================
 # パスワード設定（明示または環境変数）
 # =========================
$resolvedPassword = if ($DbPassword) { $DbPassword } else { $env:PGPASSWORD }
$__prevPwd = $env:PGPASSWORD
if ($resolvedPassword) { $env:PGPASSWORD = $resolvedPassword }

try {
  # 出力ディレクトリ
  $OutDir = Join-Path -Path $PSScriptRoot -ChildPath "results"
  $LogDir = Join-Path $OutDir "logs"
  $RawDir = Join-Path $OutDir "raw"
  $null = New-Item -ItemType Directory -Force -Path $LogDir, $RawDir | Out-Null

  # タグ
  $tag = if ($SqlFile) { (Split-Path $SqlFile -LeafBase) } else { $Workload }

  $ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
  $logPath  = Join-Path $LogDir ("pgbench_{0}_{1}.log"  -f $tag, $ts)
  $jsonPath = Join-Path $RawDir ("result_{0}_{1}.json"   -f $tag, $ts)

  Write-Host "[INFO] pgbench ベンチマーク開始: Workload=$Workload Duration=$Duration Rounds=$Rounds"
  "[INFO] Workload=$Workload Duration=$Duration Rounds=$Rounds HideHostName=$HideHostName DbHost=$DbHost DbPort=$DbPort DbUser=$DbUser" |
    Out-File -FilePath $logPath -Encoding UTF8

  foreach ($tool in @($Pgbench, $Psql)) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
      throw "実行ファイルが見つかりません: $tool  （PATHを通すかフルパスを指定してください）"
    }
  }
  ("[INFO] " + (& $Pgbench --version)) | Tee-Object -FilePath $logPath -Append
  ("[INFO] " + (& $Psql --version))    | Tee-Object -FilePath $logPath -Append

  # システム情報
  $sysInfo = & "$PSScriptRoot/Get-SysInfo.ps1" -HideHostName:$HideHostName

    # ================================================
    # 依存 DLL および管理者権限チェック
    # ================================================
    # 1) HwSensorCli 依存ファイルチェック
    $toolDir = Join-Path $PSScriptRoot 'tool'
    [string[]]$deps = @(
      'HwSensorCli.exe',
      'LibreHardwareMonitorLib.dll',
      'Newtonsoft.Json.dll',
      'HidSharp.dll',
      'System.CodeDom.dll'
    )

    # ← 強制配列化して Count を安全に参照
    $missing = @(
      $deps | Where-Object { -not (Test-Path (Join-Path $toolDir $_)) }
    )

    if ($missing -and $missing.Count -gt 0) {
      Write-Warning "依存ファイルが不足しています: $($missing -join ', ') in '$toolDir'"
      Write-Warning "センサー連携をスキップします（-EnableHwSensors は無視されます）。"
      $EnableHwSensors = $false
    }

    # 2) 管理者権限チェック
    try {
      $principal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
      )
      $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
      $isAdmin = $false
    }

    if ($EnableHwSensors -and -not $isAdmin) {
      Write-Warning "管理者権限で実行していません。CPU温度や電力センサーは取得できない可能性があります。"
      Start-Sleep -Seconds 1
    }

    # 3) CLI パス（常に絶対パス化）
    $HwSensorCli = Join-Path $toolDir 'HwSensorCli.exe'


  # HwSensor 事前ガード（依存不足やパス不正時は静かに無効化）
  if ($EnableHwSensors) {
      if (-not (Test-Path $HwSensorCli)) {
          Write-Warning "HwSensorCli が見つかりません: $HwSensorCli  センサー連携をスキップします。"
          $EnableHwSensors = $false
      }
  }

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
  "[*hint] init 失敗時は DB 作成・接続先・認証（ユーザー/パスワード）を確認してください。" | Tee-Object -FilePath $logPath -Append


  # 収集カウンタ（呼び出し側で省略可だが明示しておく）
  $counters = @("\Processor(_Total)\% Processor Time", "\Memory\Available MBytes")

  # 結果バッファ
  $tpsList = New-Object System.Collections.Generic.List[double]
  $latList = New-Object System.Collections.Generic.List[double]
  $cpuAvgs = New-Object System.Collections.Generic.List[double]
  $memAvgs = New-Object System.Collections.Generic.List[double]

  # HwSensor 用（ラウンド集計配列）
  $hw_temp_avg_per_round   = @()
  $hw_temp_max_per_round   = @()
  $hw_power_avg_per_round  = @()
  $hw_power_max_per_round  = @()
  $hw_clock_avg_per_round  = @()
  $hw_clock_min_per_round  = @()
  $hw_st_avg_per_round     = @()
  $hw_st_max_per_round     = @()

  # ループの直前あたり（for ($r=1; ...) の直前）に追加
  # $HwSensorCli を絶対パス化し、無ければ $EnableHwSensors を落とす
  $HwExe = $null
  if ($EnableHwSensors) {
    $HwExe = if ([System.IO.Path]::IsPathRooted($HwSensorCli)) {
      $HwSensorCli
    } else {
      Join-Path $PSScriptRoot $HwSensorCli
    }

    if (-not (Test-Path $HwExe)) {
      Write-Warning "HwSensorCli が見つかりません: $HwExe  センサー連携をスキップします。"
      $EnableHwSensors = $false
    } else {
      # 後段で迷わないよう、変数も絶対パスで上書きしておく
      $HwSensorCli = $HwExe
    }
  }

  # =========================
  # Main: ベンチマーク本体
  # =========================
  for ($r=1; $r -le $Rounds; $r++) {
    Write-Host "[RUN $r/$Rounds] 同時計測開始"
    $perfJob = Get-PerfAverages -Seconds $Duration

    # HwSensor（任意・絶対パスで起動）
    $hwJob = $null
    if ($EnableHwSensors) {
      # Start-HwSensorJob がある前提（ない場合は、前に渡した Start-Job 版に差し替え）
      $hwJob = Start-HwSensorJob -Seconds $Duration -Exe $HwSensorCli -IncludeStorage:$IncludeStorageTemp
  }

    # pgbench コマンド
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
    $pgOut  = & $Pgbench @args 2>&1 | Tee-Object -FilePath $logPath -Append
    $pgText = ($pgOut | Out-String)

    # パフォーマンスの受け取り
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

    # --- tps / latency を抽出（正規表現 + フォールバック）---
    [double]$tpsVal = 0
    [double]$latVal = 0

    # 1) 通常抽出
    $m1 = [regex]::Match($pgText, 'tps\s*=\s*([0-9]+(?:\.[0-9]+)?)')
    if ($m1.Success) { $tpsVal = [double]$m1.Groups[1].Value }

    $m2 = [regex]::Match($pgText, 'latency\s+average\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*ms')
    if ($m2.Success) { $latVal = [double]$m2.Groups[1].Value }

    # 2) フォールバック: 件数 / Duration で tps 計算
    if ($tpsVal -le 0) {
      $mTr = [regex]::Match($pgText, 'number of transactions actually processed:\s*([0-9]+)')
      if ($mTr.Success -and $Duration -gt 0) {
        $tpsVal = [math]::Round(([double]$mTr.Groups[1].Value) / $Duration, 6)
      } else {
        Write-Warning "tps を抽出できませんでした（RUN $r/$Rounds）。ログ末尾を確認してください。"
      }
    }

    # latency は明示が無いケースもあるので、見つからなければ 0 のまま（警告だけ）
    if ($latVal -le 0) {
      Write-Warning "latency average を抽出できませんでした（RUN $r/$Rounds）。"
    }

    $tpsList.Add($tpsVal) | Out-Null
    $latList.Add($latVal) | Out-Null

    # HwSensor 回収
    if ($EnableHwSensors -and $hwJob) {
      $hwRound = Receive-Job $hwJob -Wait -AutoRemoveJob
      if ($hwRound) {
        $sum = Summarize-HwRound -Temp $hwRound.Temp -Power $hwRound.Power -Clock $hwRound.Clock -Storage $hwRound.StorageTemp
        $hw_temp_avg_per_round  += $sum.cpu_temp.avg
        $hw_temp_max_per_round  += $sum.cpu_temp.max
        $hw_power_avg_per_round += $sum.cpu_power.avg
        $hw_power_max_per_round += $sum.cpu_power.max
        $hw_clock_avg_per_round += $sum.cpu_clock.avg
        $hw_clock_min_per_round += $sum.cpu_clock.min
        $hw_st_avg_per_round    += $sum.storage_temp.avg
        $hw_st_max_per_round    += $sum.storage_temp.max
      }
    }

    # 完了サマリ行
    "[DONE $r/$Rounds] CPU.avg=${cpuAvg}%  Mem.avg=${memAvg}MB  TPS=${tpsVal}  Lat(ms)=${latVal}" |
      Tee-Object -FilePath $logPath -Append
    "" | Add-Content -Path $logPath
  }

  # =========================
  # 集約
  # =========================
  $tpsAvg    = [Math]::Round( ($tpsList | Measure-Object -Average).Average, 3 )
  $latAvg    = [Math]::Round( ($latList | Measure-Object -Average).Average, 3 )
  $tpsMed    = Get-Median $tpsList.ToArray()
  $latMed    = Get-Median $latList.ToArray()
  $cpuAvgAll = [Math]::Round( ($cpuAvgs | Measure-Object -Average).Average, 2 )
  $memAvgAll = [Math]::Round( ($memAvgs | Measure-Object -Average).Average, 2 )

  # --- sql_file を JSON 用にマスク ---
  $sqlPathForJson = $null
  if ($SqlFile) {
    try {
      # どのみち公開JSONではファイル名だけを残す
      $sqlPathForJson = Split-Path (Resolve-Path -LiteralPath $SqlFile).Path -Leaf
    } catch {
      $sqlPathForJson = Split-Path $SqlFile -Leaf
    }
  }


  $result = [ordered]@{
    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    workload  = @{
      tag         = $tag
      profile     = $Workload
      duration_s  = $Duration
      rounds      = $Rounds
      clients     = $Clients
      threads     = $Threads
      scale       = $Scale
      database    = $DbName
      sql_file    = $sqlPathForJson
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

  # HwSensor まとめ（既存 perf に追加）
  if ($EnableHwSensors) {
    $result.perf.cpu_temp_c = @{
      avg_overall   = (Mean0 $hw_temp_avg_per_round)
      max_overall   = (Max0  $hw_temp_max_per_round)
      avg_per_round = $hw_temp_avg_per_round
      max_per_round = $hw_temp_max_per_round
    }
    $result.perf.cpu_package_power_w = @{
      avg_overall   = (Mean0 $hw_power_avg_per_round)
      max_overall   = (Max0  $hw_power_max_per_round)
      avg_per_round = $hw_power_avg_per_round
      max_per_round = $hw_power_max_per_round
    }
    $result.perf.cpu_clock_mhz = @{
      avg_overall   = (Mean0 $hw_clock_avg_per_round)
      min_overall   = (Min0  $hw_clock_min_per_round)
      avg_per_round = $hw_clock_avg_per_round
      min_per_round = $hw_clock_min_per_round
    }
    if ($IncludeStorageTemp) {
      $result.perf.storage_temp_c = @{
        avg_overall   = (Mean0 $hw_st_avg_per_round)
        max_overall   = (Max0  $hw_st_max_per_round)
        avg_per_round = $hw_st_avg_per_round
        max_per_round = $hw_st_max_per_round
      }
    }
  }

  $result | ConvertTo-Json -Depth 8 | Out-File -FilePath $jsonPath -Encoding UTF8
  Write-Host "[INFO] 完了: $jsonPath"
}
finally {
  # Restore PGPASSWORD
  if ($resolvedPassword) {
    if ($null -ne $__prevPwd) { $env:PGPASSWORD = $__prevPwd }
    else { Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue }
  }
}
