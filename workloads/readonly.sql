-- ============================================================================
-- readonly.sql
--   読み取り専用ワークロード（SELECT のみ）
--   pgbench_accounts テーブルからランダムな口座残高を取得します。
--
--   主な用途:
--     - ディスクI/Oキャッシュ性能の比較
--     - 読み取りクエリ性能（SELECT latency, TPS）の測定
--     - PostgreSQLの読み取り最適化（shared_buffers / seq_page_cost 等）の検証
--
--   備考:
--     - データ更新は一切行わないため、整合性影響なし
--     - INSERT/UPDATE と違い、他セッションとの競合がほぼ起こりません
--     - CPUキャッシュやストレージキャッシュの影響を観察しやすい負荷モデルです
-- ============================================================================

-- パラメータ設定（スケール依存値）
\set nbranches 1
\set ntellers 1
\set naccounts 100000

-- ランダムな口座ID（aid）を選んで残高を参照
\set aid random(1, :naccounts)

-- 残高取得（読み取り専用クエリ）
SELECT abalance
  FROM pgbench_accounts
 WHERE aid = :aid;
