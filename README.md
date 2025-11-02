# pgbench-compare

PowerShell 7 で動作する **PostgreSQL ベンチマーク自動実行ツール** です。  
`pgbench` と `psql` を用い、同一条件下での **CPU / メモリ / 温度 / 電力 / クロック / ストレージ温度** を同時計測します。  
出力は JSON と CSV 形式で保存でき、異なる端末・構成間の比較が容易です。

> ⚠️ 本ツールは **開発・検証用途専用** です。本番環境では使用しないでください。  
> 必要要件: **PowerShell 7（pwsh）**, `psql`, `pgbench` が PATH に存在すること。

---

## 🆕 主な更新（2025-11）

- **CPU温度 / 電力 / クロックMHz / ストレージ温度** の取得を追加（`HwSensorCli` 経由）  
- **writeheavy ワークロードで TPS/Latency が出力されない不具合を修正**  
- `summarize.ps1` が新しい JSON 構造に対応（CPU温度などを CSV に出力）  
- `Get-SysInfo.ps1` にコメントベースドヘルプを追加  
- GitHub リリース管理用に **Tag 運用を開始**（例: `v1.1.0`）
- CPU-Z HTML の **サニタイズ（個人情報マスク）処理を自動化**
- **Make-SamplePages.ps1** により、`raw` 配下の CPU-Z HTML と JSON を統合した HTML ビューアを自動生成  
- サンプル構成を **`samples/v2.X.X/windows`** に統一し、メジャーバージョンごとに区分
- `Sanitize-CPUZ.ps1` により UUID / MAC / Serial などをマスク処理

---

## 📦 フォルダ構成

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
├─ tool/
│  ├─ HwSensorCli.exe     # CPU温度・電力などの取得ツール
│  ├─ HwSensorCli.sys     # CPU温度・電力などの取得ツールが一時的に生成
│  ├─ InnoReplacer.exe    # Shift-JIS維持でバッチを生成するユーティリティ
│  ├─ LibreHardwareMonitorLib.dll # ハードウェアセンサー取得用ライブラリ
│  ├─ Newtonsoft.Json.dll # JSON構造処理
│  ├─ Make-SamplePages.ps1# (管理人用) `raw` 配下の JSON と CPU-Z HTML から端末別・ポータル HTML ページを生成
│  ├─ HidSharp.dll
│  ├─ Sanitize-CPUZ.ps1   # (管理人用) CPU-Z HTML 内の UUID / MAC / Serial を自動マスク（サニタイズ）ユーティリティ
│  └─ System.CodeDom.dll  # PowerShell実行依存モジュール
├─ windows/                # Windows専用バッチ（Shift-JIS）
│  ├─ prep_db.bat         # 初期準備：DB作成・pgpass生成・ps1生成
│  ├─ cleanup_db.bat      # DB削除
│  ├─ launch_all.bat      # 3種ワークロードまとめ実行（※注記あり）
│  ├─ make_sample_pages.bat # (管理人用) `raw` 配下の JSON と CPU-Z HTML から端末別・ポータル HTML ページを生成
│  └─ summarize.bat       # summary.csv生成＋連番バックアップ
├─ workloads/              # ベンチマーク用SQL（UTF-8 / LF）
│  ├─ std.sql             # 標準TPC-B混合ワークロード
│  ├─ readonly.sql        # SELECT専用
│  ├─ writeheavy.sql      # INSERT専用（EnsureWriteTable推奨）
│  ├─ create_writeheavy.sql # writeheavy用テーブルDDL
├─ Get-SysInfo.ps1        # 端末情報収集
├─ run_pgbench.tmpl.ps1   # テンプレート
├─ run_pgbench.ps1        # 実行スクリプト（prep_dbが生成／Git管理外）
├─ summarize.ps1          # JSON→CSV変換
├─ launch.bat             # 単体実行用
├─ launch_hidehost.bat    # 匿名化モード実行用
├─ .gitignore
└─ README.md
```

> `secrets/.keep` および `results/.keep` は、**空ディレクトリをGitHub上で保持するためのプレースホルダファイル**です。  
> 実際の接続情報や出力データは `.gitignore` によりリポジトリから除外されています。

---


## 📂 サンプルデータ構成

### v1.0.0（旧構造）

```
samples/
└─ v1.0.0/                # 旧構造（CPU温度・電力なし）
     ├─ raw/
     └─ summary.csv

```


### v2.X.X（新構造／CPU-Z HTML統合ビュー対応）

```
samples/
└─ v2.X.X/                              # 新構造（CPU-Z HTML統合ビュー対応）
      └ windows/
         ├─ raw/
         │   ├─ <端末ID>/device.html   # CPU-Z 情報
         │   └─ <端末ID>/*.json        # ベンチ結果
         ├─ index.html                  # 一覧ビュー
         └─ NUC8i5BEH.html              # 端末個別ビュー

```

---

## 📘 CPU-Z サニタイズとサンプル生成

samples では、CPU-Z の HTML レポートを匿名化し、比較用サンプルとして公開しています。  
CPU-Z は、CPU やメモリ構成などハードウェア情報を取得できるユーティリティです。  
本体は以下で配布されています：

🔗 [https://cpuid.com/softwares/cpu-z.html](https://cpuid.com/softwares/cpu-z.html)
（CPU-Z 本体の「Report → HTML」機能を使用）

> 💡 `windows/make_sample_pages.bat` を実行すると、CPU-Z HTML のサニタイズと index.html の自動生成を行います。  
> 完成したページはローカルブラウザで開くだけで確認可能です。  

> 🔒 公開される CPU-Z HTML は、UUID / MAC / Serial / DMI / LPCIO / Display / Software 等を  
> 自動サニタイズ済みであり、端末特定や個人識別に繋がる情報は含まれていません。

---

## ⚙️ 実行手順（Windows）

### ① 初期準備
```cmd
windows\prep_db.bat
```
- 接続先情報を入力（Host / Port / Database / User / Password）
- `secrets/pgpass.local` と `run_pgbench.ps1` を生成  
- DBが存在しない場合は自動作成（失敗しても警告で続行）

### ② ベンチマーク実行
```cmd
windows\launch_all.bat
```
> ⚠️ 管理者権限で実行してください。  
> CPU温度・電力・クロックの取得（-EnableHwSensors）には管理者権限が必要です。  
> 通常モードで実行するとセンサー値が 0 になりますが、テスト自体は継続します。  

以下の順に3種類のテストを実施します。
1. 標準ワークロード（std）
2. 読み取り専用（readonly）
3. 書き込み専用（writeheavy）※ `EnsureWriteTable` 前提

> 注: ベースライン比較では通常、readonly と writeheavy のみを使用します。
> std はオプション的な混合ワークロードです。

> それぞれ別ファイル名でログ・JSONが保存されます（`pgbench_<workload>_YYYYMMDD_HHMMSS.*`）。  
> 注: 連続実行ラッパー（`launch_all.bat`）は環境により挙動差が出る場合があります。README の注意に従ってください。

## 推奨パラメータ（端末間の公平比較・ベースライン）

ベンチマークの目的が「端末ごとの DB 性能比較」のため、コア数差による影響を避けるために **負荷は固定**します。各ラウンドは 60 秒、3 回の実行から**中央値**を採用することで瞬間的なノイズを吸収します。

| 項目        | 推奨値（ベースライン） | 意図/メモ |
|-------------|-------------------------|-----------|
| Workload    | `readonly`, `writeheavy` | 2 本構成で CPU/IO 両面を評価 |
| Duration    | `60` 秒                  | サーマル/周波数の変動を平均化 |
| Rounds      | `3`                      | 中央値で安定化（1 本目をウォームアップ扱いにしても可） |
| Threads     | `4`                      | 固定（論理コア < 4 の端末はそのコア数） |
| Clients     | `16`                     | 固定（目安: 4 × Threads） |
| Scale       | `800`                    | メモリ/IO バランスが良く比較しやすい共通値 |
| センサー    | `-EnableHwSensors`       | 管理者権限がある場合に有効。温度/電力/クロックを記録（後からスロットリング判断に有効） |
| ホスト名    | `-HideHostName`          | 公開用 JSON からホスト名をマスク |

### ③ 集計（JSON → CSV）
```cmd
windows\summarize.bat
```
- `results/raw/*.json` → `results/summary.csv` を生成  
- 既存 `summary.csv` がある場合は **連番バックアップ**（`summary_001.csv` 等）を作成してから上書き

- ---

## ⚙️ PowerShell直接実行（短時間テスト用）

環境動作確認や設定チェックに使える **軽量テストモード（約5秒で完了）** の例です。  
本番比較やベースライン測定を行う場合は、`windows\launch_all.bat` を使用してください。

### 標準（std）
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\run_pgbench.ps1 `
  -Workload std -Duration 5 -Rounds 1 -Threads 1 -Clients 1 -Scale 10 -DbName benchdb `
  -HideHostName -EnableHwSensors
```

### 読み取り専用（readonly）
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\run_pgbench.ps1 `
  -Workload readonly -Duration 5 -Rounds 1 -Threads 1 -Clients 1 -Scale 10 -DbName benchdb `
  -HideHostName -EnableHwSensors
```

### 書き込み専用（writeheavy）
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\run_pgbench.ps1 `
  -Workload writeheavy -Duration 5 -Rounds 1 -Threads 1 -Clients 1 -Scale 10 -DbName benchdb `
  -EnsureWriteTable -HideHostName -EnableHwSensors
```

### 💡 ヒント:

> 各テストは数秒で完了します。ログとJSON出力が results\logs および results\raw に生成されます。
> -HideHostName は公開用JSONからホスト名を除去します。
> -EnableHwSensors を付けると、管理者権限時にCPU温度・電力・クロックを取得します（任意）。

---

## 💾 出力例（JSON）

```json
{
  "timestamp": "2025-11-01T21:43:23+09:00",                         // 計測時刻
  "workload": { "profile": "readonly", "duration_s": 5 },           // 実施したワークロード情報
  "results": { "tps_avg": 6374.865, "latency_ms_avg": 0.157 },      // pgbench結果
  "perf": { "cpu_temp_c": { "avg_overall": 56.6 } }                 // センサー情報（平均温度）
}
```

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

# 🔐 配布物整合性チェック（InnoReplacer.exe）

このテンプレートで利用している **`InnoReplacer.exe`** は、  
文字コードを保持したままテンプレートファイル（例：`.bat`, `.tmpl`）を置換するユーティリティです。  
本来は Inno Setup のインストーラ構築用に作成された内部ツールを、  
バッチファイル生成（Shift-JIS維持）のために転用しています。

---

## 整合性チェック手順

配布物の正当性を確認するには、以下のコマンドを実行します：

```powershell
CertUtil -hashfile tool\InnoReplacer.exe SHA256
```

実行結果の例：
```
SHA256 ハッシュ (対象 InnoReplacer.exe):
c12b4ee67b0ee0aa4d9922ddb36293504b9887992f6c9a1d7b877d1263bc4458
CertUtil: -hashfile コマンドは正常に完了しました。
```

✅ **この SHA256 値**
```
c12b4ee67b0ee0aa4d9922ddb36293504b9887992f6c9a1d7b877d1263bc4458
```
上記と一致していれば、正規の配布物であることを確認できます。

---

## 備考
- `InnoReplacer.exe` は [mono-tec/InnoReplacer](https://github.com/mono-tec/InnoReplacer) にてソースコードを公開しています。  
- SQLテンプレートは **UTF-8（BOMなし）**、BATテンプレートは **Shift-JIS** を維持したまま生成されます。  
- 本ツールは **`prep_db.bat`** により、`launch_all.bat.tmpl` をもとにShift-JISのまま自動生成する処理で使用しています。

---

# 🔐 配布物整合性チェック（HwSensorCli.exeなど）

HwSensorCliは **mono-tec が LibreHardwareMonitor をベースに再構成した軽量CLIユーティリティ**です。  
本体は MIT License のもとで配布されており、ソースコードは以下のリポジトリで公開しています：

🔗 [https://github.com/mono-tec/HwSensorCli](https://github.com/mono-tec/HwSensorCli)

- **動作内容**: Windows API および LibreHardwareMonitor API を通じて CPU / GPU / Storage のセンサー値を取得  
- **権限要件**: 一部センサー（CPUパッケージ電力など）の取得には管理者権限が必要  

- **代表センサー選択の方針**:  
  - CPU温度は、LibreHardwareMonitor が提供する複数のセンサー群のうち  
    `CPU Core #1` または `CPU Package` のいずれかを優先的に選択して取得します。  
  - これは LibreHardwareMonitor の API において、`SensorType.Temperature` の中から  
    最初に検出された代表的なコア温度を返す実装に基づきます。  
  - Intel／AMD いずれの環境でも、**相対的な温度傾向の比較用途には十分な代表値**となります。  

- **計測値の性質**:  
  - 取得される値は「CPU全体の代表温度」であり、**全コアの平均温度ではありません**。  
  - ノートPCなど省電力CPUでは `Core #1` の値、デスクトップCPUでは `Package` 温度が返るケースが多いです。  
  - 実際の全コア温度やホットスポットとは数度の差が生じる場合があります。  
  - 本ツールでの温度・電力値は **比較評価・傾向把握を目的とした参考値** としてご利用ください。

- **責任範囲**:  
  - ハードウェア構成や BIOS 設定によっては取得値が不正確になる場合があります。  
  - 本ツールは「開発・評価用」であり、**本番監視や安全制御を目的とする利用は非推奨**です。  
  - 備考: LibreHardwareMonitor の内部APIを使用しており、一部センサーの動作はハードウェアやBIOS実装に依存します。

---

## 整合性チェック手順

配布物の正当性を確認するには、以下のコマンドを実行します：

```powershell
CertUtil -hashfile tool\HwSensorCli.exe SHA256
```

実行結果の例：
```
SHA256 ハッシュ (対象 HwSensorCli.exe):
ffafab1ce1218a8a1ba65e7b5d639d2748f23e3a235bddfae16e452f1d0aa622
CertUtil: -hashfile コマンドは正常に完了しました。
```

✅ **この SHA256 値**
```
ffafab1ce1218a8a1ba65e7b5d639d2748f23e3a235bddfae16e452f1d0aa622
```
上記と一致していれば、正規の配布物であることを確認できます。

---

## 🏷️ リリース管理（Git Tag 運用）

```bash
git tag -a v1.1.0 -m "Add CPU temperature & fix writeheavy TPS bug"
git push origin v1.1.0
```

| バージョン | 主な変更点 |
|-------------|------------|
| v1.0.0 | 初回公開 |
| v2.0.0 | CPU温度/電力/クロック出力の追加・writeheavy修正 |

---

## 🧩 バージョン管理ポリシー

- **v1.0.0**：JSONスキーマ旧構造（CPU温度なし）  
- **v2.X.X**：JSONスキーマ新構造（CPU温度・電力・クロック対応）＋ CPU-Z ビュー機能  
- **v3.X.X**（将来）：出力CSVフォーマット変更・非互換時に移行

> 破壊的変更（既存summary.csvやビューアの互換性が失われる場合）は Major（v3.0.0）としてフォルダを新設します。

---

## ⚖️ 利用ライブラリとライセンス

本ツールの一部は、以下のオープンソースコンポーネントを使用しています。

| コンポーネント | ライセンス | 利用目的 / 備考 |
|----------------|-------------|----------------|
| **LibreHardwareMonitor** ([GitHub](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor)) | MIT License | CPU温度・電力・クロックなどのハードウェア情報を取得するために使用。`HwSensorCli.exe` 内で参照。 |
| **HidSharp** ([GitHub](https://github.com/mikeobrien/HidSharp)) | MIT License | センサー機器との通信に利用。 |
| **Newtonsoft.Json** ([GitHub](https://github.com/JamesNK/Newtonsoft.Json)) | MIT License | JSON構造データの読み書き処理に利用。 |
| **System.CodeDom.dll**（.NET標準ライブラリ） | MIT License | PowerShell スクリプトの一部依存モジュールとして同梱。 |

> 各ライブラリの著作権は、それぞれの開発者およびプロジェクトに帰属します。

---

📦 **最新版リリースページ**
👉 [https://github.com/mono-tec/pgbench-compare/releases](https://github.com/mono-tec/pgbench-compare/releases)

---

## 🧾 ライセンス

MIT License  
Copyright (c) 2025
