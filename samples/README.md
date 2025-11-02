# 🧩 samples ディレクトリについて（Windows版）

このフォルダは、**管理人（mono-tec）の検証結果をサンプルとして公開**するための領域です。  
ツールの使い方や結果レイアウトの参考にご活用ください。

> 💡 本ディレクトリは Windows 版のサンプルです。  
> 今後、Linux 版（`linux/` ディレクトリ）も分割して公開する予定です。  
> 利用者さまからのご要望があれば、利用者さまの公開も検討します。

---

## 構成方針

- バージョンごとにサブフォルダを分けます（例：`v2.X.X/windows/`）。
- **端末ごと**に CPU-Z の HTML と `raw` の JSON をひも付けます。  
  端末IDは **「CPU-Z HTML のファイル名（拡張子を除く）」** を利用します。

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

- 各端末フォルダには、任意で `device-note.md`（TDP/筐体/冷却/電源プランなど一言メモ）を置けます。

---

## HTML ビューの自動生成

**CPU-Z の HTML** と **raw の JSON** から、閲覧用ページを自動生成します。

- スクリプト：`tool/Make-SamplePages.ps1`
- バッチ：`windows/make_sample_pages.bat`（Shift-JIS）

### 実行方法（例）

```cmd
windows\make_sample_pages.bat ..\samples\v2.X.X\windows
```

- 端末ごとの `index.html` と、ポータル `samples\v2.X.X\windows\index.html` が生成されます。
- 直接ブラウザで開いて閲覧できます（サーバ不要）。

### 💡 ヒント:

> `tool/Make-SamplePages.ps1` の初期設定では、`samples/v2.X.X/windows` が操作対象になっています。  
> 新しいフォルダを作成すると、自動で最新フォルダを操作対象にする予定です。


---

## 注意点（センサー値・匿名化の扱い）

- CPU 温度・電力・クロックは **HwSensorCli**（LibreHardwareMonitor ベース）により取得します。
- 取得される温度は、環境に応じて **代表センサー（例：CPU Package または Core #1）** の値です。  
  **全コア平均やホットスポットの厳密値ではありません**。傾向比較の参考値としてご利用ください。
- JSON は公開共有を前提に **ホスト名を匿名化**する運用を推奨します（`-HideHostName`）。

---

## ライセンス

- サンプルデータは公開用の参考資料です。再配布や引用の際は、元リポジトリ（本プロジェクト）へのクレジットをお願いします。
- 付属ツールのライセンスは各フォルダの `README` を参照してください。
