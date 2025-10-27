# pgbench-compare

PowerShell 7 で動作する **PostgreSQL ベンチマーク自動実行ツール** です。  
`pgbench` と `psql` を用い、同一条件下での CPU / メモリ / ストレージ性能比較を行います。  
ベンチ結果は JSON と CSV に保存でき、異なるマシン・構成間での比較が容易です。

> ⚠️ 本ツールは **開発・検証用途専用** です。本番運用では使用しないでください。  
> 必要要件: **PowerShell 7（pwsh）** / `psql` と `pgbench` が PATH にあること

---

## 📦 構成

```
pgbench-compare/
├─ results/               # 実行結果（自動生成／Git管理外）
│  ├─ logs/               # ログ出力
│  ├─ raw/                # JSON形式の生データ
│  └─ summary.csv         # 集計結果
├─ samples/               # 公開用サンプル（匿名化済み）
│  ├─ raw/
│  │  ├─ result_sample_std.json
│  │  ├─ result_sample_readonly.json
│  │  └─ result_sample_writeheavy.json
│  └─ summary_sample.csv
├─ secrets/               # 接続情報
│  ├─ pgpass.local.tmpl   # テンプレート
│  ├─ pgpass.local        # 実際の接続情報（生成・非管理）
├─ windows/               # Windows専用バッチ（Shift-JIS）
│  ├─ prep_db.bat         # 初期準備：DB作成・pgpass生成・ps1生成
│  ├─ cleanup_db.bat      # DB削除
│  ├─ launch_all.bat      # 3種ワークロードまとめ実行（※注記あり）
│  └─ summarize.bat       # summary.csv生成＋連番バックアップ
├─ workloads/             # ベンチマーク用SQL（UTF-8 / LF）
│  ├─ std.sql             # 標準TPC-B混合ワークロード
│  ├─ readonly.sql        # SELECT専用
│  ├─ writeheavy.sql      # INSERT専用（EnsureWriteTable推奨）
│  ├─ create_writeheavy.sql # writeheavy用テーブルDDL
│  └─ config_std.json
├─ Get-SysInfo.ps1        # 端末情報収集
├─ run_pgbench.tmpl.ps1   # テンプレート
├─ run_pgbench.ps1        # 実行スクリプト（prep_dbが生成／Git管理外）
├─ summarize.ps1          # JSON→CSV変換
├─ launch.bat             # 単体実行用
├─ launch_hidehost.bat    # 匿名化モード実行用
├─ .gitignore
└─ README.md
```

> ※ `docs/` は後日追加予定のため、現状は同梱しません。

---

## 🧩 使い方（Windows）

### ① 初期準備
```cmd
windows\prep_db.bat
```
- 接続先情報を入力（Host / Port / Database / User / Password）
- `secrets/pgpass.local` と `run_pgbench.ps1` を生成  
- DBが存在しない場合は自動作成（失敗しても警告で続行）

### ② ベンチマークの実行
```cmd
windows\launch_all.bat
```
以下の順に3種類のテストを実施します。
1. 標準ワークロード（std）
2. 読み取り専用（readonly）
3. 書き込み専用（writeheavy）※ `EnsureWriteTable` 前提

> それぞれ別ファイル名でログ・JSONが保存されます（`pgbench_<workload>_YYYYMMDD_HHMMSS.*`）。  
> 注: 連続実行ラッパー（`launch_all.bat`）は環境により挙動差が出る場合があります。README の注意に従ってください。

### ③ 集計
```cmd
windows\summarize.bat
```
- `results/raw/*.json` → `results/summary.csv` を生成  
- 既存 `summary.csv` がある場合は **連番バックアップ**（`summary_001.csv` 等）を作成してから上書き

---

## ⚙️ PowerShell直接実行

### 標準（std）
```powershell
pwsh -File .\run_pgbench.ps1 -Workload std -Duration 60 -Rounds 5 -Clients 8 -Threads 8 -Scale 800 -DbName benchdb
```

### 読み取り専用（readonly）
```powershell
pwsh -File .\run_pgbench.ps1 -Workload readonly -Duration 60 -Rounds 5 -Clients 8 -Threads 8 -Scale 800 -DbName benchdb
```

### 書き込み専用（writeheavy）
```powershell
pwsh -File .\run_pgbench.ps1 -Workload writeheavy -Duration 60 -Rounds 5 -Clients 8 -Threads 8 -Scale 800 -DbName benchdb -EnsureWriteTable
```

### 匿名化モード（共有用）
```powershell
pwsh -File .\run_pgbench.ps1 -Workload std -HideHostName
```

---

## 💾 出力例（JSON）

```json
{
  "timestamp": "2025-10-26T18:38:42+09:00",
  "workload": {
    "profile": "std",
    "duration_s": 60,
    "rounds": 5,
    "clients": 8,
    "threads": 8,
    "scale": 800,
    "database": "benchdb"
  },
  "results": {
    "tps_median": 12500.3,
    "latency_ms_median": 4.9
  },
  "device": {
    "label": "",
    "cpu_model": "Intel(R) Core(TM) i7-1260P",
    "cpu_logical_cores": 16,
    "ram_mb": 16247,
    "storage_type": "SSD",
    "os": "Windows 11 Pro 10.0.22631",
    "postgres_version": "16.4",
    "pgbench_version": "16.4"
  }
}
```

> `-HideHostName` 指定時、`label` は空文字。  
> ネットワーク名・IP・ユーザー名などの識別情報は出力しません。

---

## 🔠 文字コード・環境

| 種類 | 文字コード | 備考 |
|------|-------------|------|
| `.bat` | Shift-JIS | Windows の CMD 互換 |
| `.ps1`, `.sql` | UTF-8 (BOMなし, LF) | Linux共通利用可 |

> `psql` の日本語出力は環境によって文字化けする場合があります（既知）。ベンチ処理には影響しません。

---

## 🧹 クリーンアップ

テスト用DBを削除する場合：
```cmd
windows\cleanup_db.bat
```
`secrets/pgpass.local` の情報を利用して `DROP DATABASE IF EXISTS` を実行します。

---

## Notes

- `secrets/.keep` および `results/.keep` は、**空ディレクトリをリポジトリ上で保持するためのプレースホルダファイル**です。  
  （実際の機密情報や出力結果は `.gitignore` により除外されています）

---

⚠️ **ご注意**

このリポジトリは現在 **仮公開** の段階です。  
一部のスクリプトや構成が未確定のため、動作に不具合が発生する可能性があります。  
ご利用いただけますが、動作の安定性はまだ検証中です。  
2025年11月中に内容を再確認し、正式リリースを予定しています。

---

## 🧾 ライセンス

MIT License  
Copyright (c) 2025
