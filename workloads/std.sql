-- ============================================================================
-- std.sql
--   標準ワークロード（TPC-B 準拠）
--   pgbench デフォルトの標準トランザクションを明示的に記述したものです。
--   UPDATE / SELECT / INSERT を混在させた総合的な負荷を測定します。
--
--   主な処理:
--     1. ランダムな口座（aid）を選択
--     2. その口座の残高 (abalance) を増減（UPDATE）
--     3. 変更後の残高を取得（SELECT）
--     4. 対応する teller / branch の残高を更新（UPDATE）
--     5. トランザクション履歴を追記（INSERT）
--
--   備考:
--     - 各テーブルは pgbench の標準スキーマ (pgbench_accounts 等) を使用
--     - :scale は pgbench 初期化時に設定されたスケールファクタ
--     - 実際の金額・残高などはランダム化して模擬的に変動
-- ============================================================================

-- ランダムな取引対象を選択
\set aid random(1, :scale * 100000)
\set bid random(1, 1)
\set tid random(1, 10)
\set delta random(-5000, 5000)

BEGIN;

-- 対象口座の残高を更新
UPDATE pgbench_accounts
   SET abalance = abalance + :delta
 WHERE aid = :aid;

-- 更新後の残高を取得（確認用途）
SELECT abalance
  FROM pgbench_accounts
 WHERE aid = :aid;

-- 対応する teller / branch の残高を更新
UPDATE pgbench_tellers
   SET tbalance = tbalance + :delta
 WHERE tid = :tid;

UPDATE pgbench_branches
   SET bbalance = bbalance + :delta
 WHERE bid = :bid;

-- 履歴テーブルに取引ログを追加
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime)
VALUES (:tid, :bid, :aid, :delta, CURRENT_TIMESTAMP);

END;
