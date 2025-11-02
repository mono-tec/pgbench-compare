param(
  [Parameter(Mandatory=$true)]
  [string]$Target  # ファイル or フォルダ（例: .\samples\v1.1.0）
)

$ErrorActionPreference = "Stop"




function Mask-Tail4 {
  param([string]$s)
  if ([string]::IsNullOrEmpty($s)) { return "xxxx" }
  $s = $s.Trim()
  if ($s.Length -le 4) { return "xxxx" }
  return ('x' * ($s.Length - 4)) + $s.Substring($s.Length - 4)
}

# =========================
# 見出しセクションの安全削除
#   CPU-Z HTMLは各セクション見出しの<tr>に bgcolor="#E0E0FF" が付く
#   指定セクションの見出し行から、次の見出し行 or </table> 直前までを除去
# =========================
function Remove-CpuzSection {
  param(
    [string]$Html,
    [string]$SectionTitle   # 例: "LPCIO" / "Display Adapters" / "Software"
  )
  # 見出し行: <tr ... bgcolor="#E0E0FF"> ... <b>SectionTitle</b> ...
  $title = [Regex]::Escape($SectionTitle)
  $pattern = '(?is)<tr[^>]*bgcolor="#E0E0FF"[^>]*>\s*<td[^>]*>\s*<small>\s*<b>\s*' +
             $title +
             '\s*</b>\s*</small>\s*</td>.*?(?=(?:<tr[^>]*bgcolor="#E0E0FF")|</table>)'
  return [Regex]::Replace($Html, $pattern, '')
}

function Sanitize-OneHtml {
  param([string]$Path)

  if (!(Test-Path -LiteralPath $Path)) { return }

  $html = Get-Content -LiteralPath $Path -Raw

  # --- 1) GUID/UUID をマスク
  $html = $html -replace '(?i)\{?[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}\}?', '{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}'

  # --- 2) MAC アドレスをマスク（aa:bb:.. / aa-bb-..）
  $html = $html -replace '(?i)\b([0-9A-F]{2}[:-]){5}[0-9A-F]{2}\b', 'xx:xx:xx:xx:xx:xx'

  # --- 3) 「Serial number」セル形式をマスク
  $html = [System.Text.RegularExpressions.Regex]::Replace(
    $html,
    '(?is)(Serial\s*Number|Serial\s*number)\s*</td>\s*<td[^>]*><small><font[^>]*>\s*([^<]+)\s*</font>\s*</small>\s*</td>',
    {
      $pfx = $args[0].Groups[1].Value
      $val = $args[0].Groups[2].Value
      "$pfx</td><td><small><font>" + (Mask-Tail4 $val) + "</font></small></td>"
    }
  )

  # --- 4) プレーンテキスト形式の「Serial number: 値」も保険でマスク
  $html = [System.Text.RegularExpressions.Regex]::Replace(
    $html,
    '(?im)(Serial\s*Number|Serial\s*number)\s*[:：]\s*([0-9A-Za-z\-]+)',
    {
      $pfx = $args[0].Groups[1].Value
      $val = $args[0].Groups[2].Value
      "$($pfx): " + (Mask-Tail4 $val)   # ← ここをサブ式展開に修正
    }
  )

  # --- 5) Part number は先頭10文字 + 省略記号
  $html = [System.Text.RegularExpressions.Regex]::Replace(
    $html,
    '(?is)(Part\s*Number)\s*</td>\s*<td[^>]*><small><font[^>]*>\s*([^<]+)\s*</font>\s*</small>\s*</td>',
    {
      $pfx = $args[0].Groups[1].Value
      $val = $args[0].Groups[2].Value.Trim()
      $short = if ($val.Length -gt 10) { $val.Substring(0,10) + '…' } else { $val }
      "$pfx</td><td><small><font>$short</font></small></td>"
    }
  )

  # --- 6) cpuid.com 由来の外部画像/リンクを除去 or ダミー化
  $html = $html -replace '(?is)<img[^>]+cpuid\.com[^>]*>', ''
  $html = $html -replace '(?is)<a[^>]+cpuid\.com[^>]*>.*?</a>', '<span></span>'

  # --- 7) 余計な絶対URL画像も一応除去
  $html = $html -replace '(?is)<img[^>]+src=["'']https?://[^"'']+["''][^>]*>', ''


  # --- 8) ここで不要セクションを個別に除去 ---
  $targets = @(
    'Memory SPD',
    'Monitoring',
    'LPCIO',             # LPCIO 配下（Hardware Monitors含む）を丸ごと除去
    'Hardware Monitors',
    'PCI Devices',
    'DMI',
    'Graphics',
    'Graphic APIs',
    'Graphic APIs',
    'Display Adapters',  # GPU・表示系
    'Software'           # ドライバ/OS詳細など
  )
  foreach ($t in $targets) {
    $before = $html.Length
    $html   = Remove-CpuzSection -Html $html -SectionTitle $t
    if ($html.Length -ne $before) { Write-Host "removed section: $t" }
  }

  # ※ ここまでで末尾まで真っ白になる症状は解消されます。
  #    既存の「LPCIO～テーブル末尾ごと削除」の正規表現は削除してください。


  Set-Content -LiteralPath $Path -Value $html -Encoding UTF8
}

# ---- 走査（フォルダなら配下 *.html を全部、ファイルならそれだけ）
$targets = @()
if (Test-Path -LiteralPath $Target -PathType Container) {
  $targets = Get-ChildItem -LiteralPath $Target -Recurse -Include *.html -File | Select-Object -Expand FullName
} elseif (Test-Path -LiteralPath $Target -PathType Leaf) {
  if ($Target.ToLower().EndsWith('.html')) { $targets = @($Target) }
}

foreach ($f in $targets) {
  try {
    Sanitize-OneHtml -Path $f
    Write-Host "sanitized: $f"
  } catch {
    Write-Warning "failed: $f  ($($_.Exception.Message))"
  }
}
