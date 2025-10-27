@echo off
REM ============================================================
REM  launch_all.bat
REM    - run_pgbench.ps1 を使って 3 種の負荷を連続実行
REM      1) SELECT のみ（readonly）
REM      2) INSERT のみ（writeheavy.sql）
REM      3) std（TPC-B 準拠の混在）
REM  注意: このファイルは Shift-JIS で保存してください
REM ============================================================

setlocal ENABLEDELAYEDEXPANSION

REM ---- パス設定（必要に応じて変更）----
set "BASE=%~dp0.."
set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
set "SCRIPT=%BASE%\run_pgbench.ps1"
set "WRITE_SQL=%BASE%\workloads\writeheavy.sql"
set "WRITE_DDL=%BASE%\workloads\create_writeheavy.sql"

REM ---- 共通パラメータ（必要ならここだけ直す）----
set "DURATION=60"
set "ROUNDS=5"
set "CLIENTS=8"
set "THREADS=8"
set "SCALE=800"
set "DBNAME=benchdb"

REM 名前/ホスト匿名化したい場合は有効化（既定で有効）
set "HIDE_SWITCH=-HideHostName"

REM ---- PowerShell 7 の存在確認（pwsh フォールバック）----
if not exist "%PWSH%" (
  for /f "delims=" %%P in ('where.exe pwsh 2^>nul') do set "PWSH=%%P"
)
if not exist "%PWSH%" (
  echo ERROR: PowerShell 7 が見つかりません。PWSH のパスを修正してください。
  pause & exit /b 1
)

REM ---- スクリプト存在確認 ----
if not exist "%SCRIPT%" (
  echo ERROR: run_pgbench.ps1 が見つかりません: "%SCRIPT%"
  pause & exit /b 1
)

REM ---- writeheavy 用 SQL/DDL の事前確認 ----
if not exist "%WRITE_SQL%" (
  echo ERROR: INSERT 用 SQL が見つかりません: "%WRITE_SQL%"
  echo        workloads\writeheavy.sql を配置してください。
  pause & exit /b 1
)
if not exist "%WRITE_DDL%" (
  echo ERROR: writeheavy 用 DDL が見つかりません: "%WRITE_DDL%"
  echo        workloads\create_writeheavy.sql を配置してください。
  pause & exit /b 1
)

REM ---- 共通引数をまとめる（重複排除）----
set "COMMON_ARGS=-Duration %DURATION% -Rounds %ROUNDS% -Clients %CLIENTS% -Threads %THREADS% -Scale %SCALE% -DbName %DBNAME% %HIDE_SWITCH%"

echo.
echo ============================================================
echo [1/3] SELECT のみ（readonly）を実行します
echo     %COMMON_ARGS%
echo ============================================================
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Workload readonly %COMMON_ARGS%
if errorlevel 1 (
  echo ERROR: readonly 実行でエラーが発生しました。
  pause & exit /b 1
)
echo.

echo ============================================================
echo [2/3] INSERT のみ（writeheavy）を実行します
echo     ※ workloads\create_writeheavy.sql / writeheavy.sql を使用
echo ============================================================
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Workload writeheavy -SqlFile "%WRITE_SQL%" -EnsureWriteTable %COMMON_ARGS%
if errorlevel 1 (
  echo ERROR: writeheavy 実行でエラーが発生しました。
  pause & exit /b 1
)
echo.

echo ============================================================
echo [3/3] 標準ワークロード（std: SELECT+UPDATE+INSERT）を実行します
echo ============================================================
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Workload std %COMMON_ARGS%
if errorlevel 1 (
  echo ERROR: std 実行でエラーが発生しました。
  pause & exit /b 1
)
echo.

echo すべてのジョブが終了しました。results\logs / results\raw をご確認ください。
pause
endlocal
