-- ============================================================================
-- create_writeheavy.sql
--   書き込み負荷（INSERT専用ワークロード）用テーブル定義
--
--   主な用途:
--     - writeheavy.sql（INSERT専用ベンチ）で利用されるテーブルを作成
--     - ベンチマーク実行前に -EnsureWriteTable オプションで自動作成されます
--
--   テーブル設計:
--     bench_insert:
--       id       : 一意の連番（自動採番、BIGSERIAL）
--       ts       : 挿入時刻（デフォルトで現在時刻）
--       note     : 任意のコメント（NULL可）
--       payload  : 任意のテキストデータ（JSONや自由形式）
--
--   特徴:
--     - シンプルな INSERT 負荷を再現するため、外部キーや更新を排除
--     - タイムスタンプ列にインデックスを付与し、I/Oコストの傾向を測定可能
--     - 既に存在する場合は CREATE TABLE IF NOT EXISTS によりスキップされます
--
--   注意:
--     - ベンチマークは毎回 TRUNCATE して再実行されるため、永続データは残りません。
-- ============================================================================

-- 書き込み専用ベンチ用テーブル
CREATE TABLE IF NOT EXISTS bench_insert (
  id       BIGSERIAL PRIMARY KEY,      -- 自動採番ID
  ts       TIMESTAMPTZ NOT NULL DEFAULT now(),  -- 挿入時刻
  note     TEXT,                       -- 任意メモ
  payload  TEXT                        -- 任意のデータ（JSON等）
);

-- タイムスタンプ検索性能を検証しやすくするためのインデックス
CREATE INDEX IF NOT EXISTS idx_bench_insert_ts ON bench_insert(ts);
