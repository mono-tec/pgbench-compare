param(
  [Parameter(Mandatory=$true)]
  [string]$Root,                     # 例: .\samples\v1.1.0
  [string]$SummaryCsvName = "summary.csv",
  [string]$Title = "pgbench-compare samples viewer"
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path $Root).Path
$RawDir = Join-Path $Root "raw"
if (-not (Test-Path $RawDir)) { throw "raw フォルダが見つかりません: $RawDir" }

# 端末ID = ルート直下の *.html (CPU-Z) のベース名、と仮定
$cpuZ = Get-ChildItem $Root -Filter *.html -File | Sort-Object Name
$deviceIds = @()

foreach ($h in $cpuZ) {
  $id = [IO.Path]::GetFileNameWithoutExtension($h.Name)
  $deviceIds += $id
  $devDir = Join-Path $RawDir $id
  if (-not (Test-Path $devDir)) {
    Write-Host "WARN: $id 用の raw サブフォルダがありません。作成します。"
    New-Item -ItemType Directory -Force -Path $devDir | Out-Null
  }
  # CPU-Z HTML を 各デバイス配下の device.html としてコピー
  Copy-Item -Force $h.FullName (Join-Path $devDir "device.html")
}

# raw の構造を判定：サブフォルダが1つ以上あるか？
$devDirs = Get-ChildItem $RawDir -Directory | Sort-Object Name

function New-DeviceIndex($DevDir, $Title) {
  $rawLinks = Get-ChildItem $DevDir -Filter *.json -File | Sort-Object Name | ForEach-Object {
    "          <li><a href=""$($_.Name)"" target=""json"">$($_.Name)</a></li>"
  } | Out-String

  $hasCpuZ = Test-Path (Join-Path $DevDir "device.html")
  $cpuZNote = if ($hasCpuZ) { "device.html（CPU-Z HTML）" } else { "（CPU-Z HTML 未配置）" }
  $iframe = if ($hasCpuZ) { '<iframe src="device.html" name="device" title="CPU-Z"></iframe>' } else { '<div class="tip">CPU-Z HTML がありません。</div>' }

  @"
<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>$Title</title>
<style>
:root{--bg:#0f1116;--fg:#e6e6e6;--muted:#9aa4af;--accent:#8ab4f8}
html,body{margin:0;height:100%;background:var(--bg);color:var(--fg);font-family:ui-sans-serif,system-ui,Segoe UI,Roboto,Helvetica,Arial}
a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}
header{padding:12px 16px;border-bottom:1px solid #222;display:flex;gap:12px;align-items:center}
.wrap{display:grid;grid-template-columns:320px 1fr;min-height:calc(100vh - 54px)}
aside{border-right:1px solid #222;padding:12px 14px}
h1{font-size:16px;margin:0}h2{font-size:14px;margin:12px 0 6px;color:var(--muted)}
ul{list-style:none;padding:0;margin:0;display:flex;flex-direction:column;gap:6px}
.tip{font-size:12px;color:var(--muted);margin-top:10px}
iframe{width:100%;height:100%;border:0;background:#111}
.pill{font-size:12px;border:1px solid #333;border-radius:999px;padding:4px 8px;color:var(--muted)}
</style></head>
<body>
<header><h1>$Title</h1><div class="pill">$([IO.Path]::GetFileName($DevDir))</div></header>
<div class="wrap">
  <aside>
    <h2>raw JSON</h2>
    <ul>
$rawLinks
    </ul>
    <div class="tip">$cpuZNote</div>
    <h2 style="margin-top:16px;">メモ</h2>
    <ul>
      <li><a href="../index.html">← 端末一覧へ戻る</a></li>
      <li><a href="device-note.md">device-note.md（任意で作成）</a></li>
    </ul>
  </aside>
  $iframe
</div>
</body></html>
"@
}

function New-PortalIndex($Root, $DevDirs, $SummaryCsvName, $Title) {
  $rows = @(
    foreach ($d in $DevDirs) {
      $name = $d.Name
      $cnt  = (Get-ChildItem -LiteralPath $d.FullName -Filter *.json -File -ErrorAction SilentlyContinue | Measure-Object).Count
      if ($cnt -eq 0) { continue } 
      $cpuZ = if (Test-Path (Join-Path $d.FullName "device.html")) { "✔" } else { "—" }
      "        <tr><td><a href=""raw/$name/index.html"">$name</a></td><td style=""text-align:right"">$cnt</td><td style=""text-align:center"">$cpuZ</td></tr>"
    }
  ) -join "`r`n"   # ← 配列を改行で連結

  $summaryLink = ""
  $summaryPath = Join-Path $Root $SummaryCsvName
  if (Test-Path -LiteralPath $summaryPath) {
    $summaryLink = "<a href=""$SummaryCsvName"" download>summary.csv をダウンロード</a>"
  }

  @"
<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>$Title</title>
<style>
:root{--bg:#0f1116;--fg:#e6e6e6;--muted:#9aa4af;--accent:#8ab4f8}
html,body{margin:0;height:100%;background:var(--bg);color:var(--fg);font-family:ui-sans-serif,system-ui,Segoe UI,Roboto,Helvetica,Arial}
a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}
header{padding:12px 16px;border-bottom:1px solid #222;display:flex;gap:12px;align-items:center}
h1{font-size:16px;margin:0}.pill{font-size:12px;border:1px solid #333;border-radius:999px;padding:4px 8px;color:var(--muted);margin-left:12px}
main{padding:16px}
table{width:100%;border-collapse:collapse}
th,td{border-bottom:1px solid #222;padding:8px 10px}
th{color:var(--muted);font-weight:600;text-align:left}
td:nth-child(2){width:120px}
td:nth-child(3){width:120px}
</style></head>
<body>
<header>
  <h1>$Title</h1>
  <div class="pill">フォルダ: $([IO.Path]::GetFileName($Root))</div>
  <div style="margin-left:auto">$summaryLink</div>
</header>
<main>
  <table>
    <thead><tr><th>端末ID</th><th style="text-align:right">JSON数</th><th style="text-align:center">CPU-Z</th></tr></thead>
    <tbody>
$rows
    </tbody>
  </table>
  <p style="color:#9aa4af;margin-top:12px;font-size:12px">※ 各端末フォルダに CPU-Z HTML（device.html）と JSON が揃っていると見やすいです。</p>
</main>
</body></html>
"@
}

if ($devDirs.Count -gt 0) {
  # 複数端末モード：端末ページ＋ポータル
  foreach ($d in $devDirs) {
    $html = New-DeviceIndex -DevDir $d.FullName -Title $Title
    $html | Set-Content -Encoding UTF8 (Join-Path $d.FullName "index.html")
  }
  $portal = New-PortalIndex -Root $Root -DevDirs $devDirs -SummaryCsvName $SummaryCsvName -Title $Title
  $portal | Set-Content -Encoding UTF8 (Join-Path $Root "index.html")
  Write-Host "✔ 端末ページとポータル index.html を生成しました。"
} else {
  # 単一端末モード：raw 直下に JSON、Root に CPU-Z HTML がある想定
  $devDir = $RawDir
  if (-not (Test-Path (Join-Path $devDir "device.html"))) {
    # ルート直下に一つだけある CPU-Z を device.html としてコピー
    $one = $cpuZ | Select-Object -First 1
    if ($one) { Copy-Item -Force $one.FullName (Join-Path $devDir "device.html") }
  }
  $html = New-DeviceIndex -DevDir $devDir -Title $Title
  $html | Set-Content -Encoding UTF8 (Join-Path $Root "index.html")
  Write-Host "✔ 単一端末ページ index.html を生成しました。"
}
