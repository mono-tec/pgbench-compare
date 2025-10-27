-- ============================================================================
-- writeheavy.sql
--   pgbench INSERT 専用ワークロード（\echo 非対応版）
--   pgbench 内部コマンドのみ使用 (\set, \if, \endif など)
--   任意文字列は SQL 内で md5() により生成
-- ============================================================================

-- 乱数を生成
\set payload random(1, 1000000)

BEGIN;
  INSERT INTO bench_insert (ts, note, payload)
  VALUES (
    clock_timestamp(),
    substr(md5(:payload::text || clock_timestamp()::text), 1, 20),
    :payload::text
  );
END;
