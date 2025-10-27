@echo off
REM ============================================================
REM  prep_db.bat - ベンチ用DB作成 & pgpass.local 生成 & run_pgbench.ps1 生成
REM  前提:
REM    - PowerShell 7 (pwsh.exe)
REM    - psql が PATH にある（無ければ PSQL 変数をフルパスに）
REM ============================================================

setlocal ENABLEDELAYEDEXPANSION

echo =============================================================
echo  pgbench ベンチマーク環境 準備ツール
echo -------------------------------------------------------------
echo  このバッチは以下の処理を行います:
echo   1. PostgreSQL の接続情報を入力し、secrets\pgpass.local を生成します。
echo   2. run_pgbench.tmpl.ps1 をもとに run_pgbench.ps1 を生成します。
echo   3. 指定されたデータベースが存在しない場合は CREATE DATABASE を試行します。
echo.
echo  ※既に存在するファイルやデータベースは上書き確認のうえ続行します。
echo  ※CREATE DATABASE が失敗しても続行可能です（既存DB想定）。
echo =============================================================
echo.
pause

REM --- パス設定（必要に応じて変更）---
set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
REM 例: フルパス指定したい場合は下行のコメントを外す
REM set "PSQL=C:\Program Files\PostgreSQL\17\bin\psql.exe"

REM --- pwsh フォールバック ---
if not exist "%PWSH%" (
  for /f "delims=" %%P in ('where.exe pwsh 2^>nul') do set "PWSH=%%P"
)
if not exist "%PWSH%" (
  echo ERROR: PowerShell 7 が見つかりません。PWSH のパスを修正してください。
  pause & exit /b 1
)

REM --- テンプレート/出力ファイル ---
set "BASE=%~dp0..\"
set "TMPL=%BASE%run_pgbench.tmpl.ps1"
set "OUTP=%BASE%run_pgbench.ps1"

REM --- secrets ---
set "SECRETS_DIR=%BASE%secrets"
set "TMPL_SECRETS=%SECRETS_DIR%\pgpass.local.tmpl"
set "PGPASS_LOCAL=%SECRETS_DIR%\pgpass.local"

REM --- 既定値（Enterで採用）---
set "DB_HOST=localhost"
set "DB_PORT=5432"
set "DB_NAME=benchdb"
set "DB_USER=postgres"

REM --- psql パス検出（未指定時のみ）---
if "%PSQL%"=="" (
  for /f "delims=" %%P in ('where.exe psql 2^>nul') do set "PSQL=%%P"
)
echo Using psql: "%PSQL%"

"%PSQL%" --version >nul 2>&1 || (
  echo ERROR: psql を実行できません。PATH を通すか、PSQL をフルパスに設定してください。
  pause & exit /b 1
)

REM --- 入力 ---
set /p DB_HOST=Host [default: %DB_HOST%] ?:
if "%DB_HOST%"=="" set "DB_HOST=localhost"

set /p DB_PORT=Port [default: %DB_PORT%] ?:
if "%DB_PORT%"=="" set "DB_PORT=5432"

set /p DB_NAME=Database [default: %DB_NAME%] ?:
if "%DB_NAME%"=="" set "DB_NAME=benchdb"

set /p DB_USER=User [default: %DB_USER%] ?:
if "%DB_USER%"=="" set "DB_USER=postgres"

set /p DB_PASS=Password ?:
if "%DB_PASS%"=="" (
  echo ERROR: パスワードが空です。処理を中止します。
  pause & exit /b 1
)

REM --- かんたん妥当性チェック（任意）---
echo %DB_PORT%| findstr /r "^[0-9][0-9]*$" >nul || (
  echo ERROR: Port は数値で指定してください。
  pause & exit /b 1
)

REM ---- secrets\pgpass.local 作成（PowerShellでテンプレ置換）----
if not exist "%SECRETS_DIR%" mkdir "%SECRETS_DIR%"
if not exist "%TMPL_SECRETS%" (
  echo ERROR: テンプレートが見つかりません: %TMPL_SECRETS%
  pause & exit /b 1
)

if exist "%PGPASS_LOCAL%" (
  choice /c YN /m "既存の pgpass.local を上書きしますか？"
  if errorlevel 2 (
    echo キャンセルされました。
    pause & exit /b 0
  )
)

"%PWSH%" -NoLogo -NoProfile -Command ^
  "$ErrorActionPreference='Stop'; " ^
  "$t = Get-Content -Raw -Path '%TMPL_SECRETS%'; " ^
  "$t = $t -replace '#DB_HOST#', $env:DB_HOST; " ^
  "$t = $t -replace '#DB_PORT#', $env:DB_PORT; " ^
  "$t = $t -replace '#DB_NAME#', $env:DB_NAME; " ^
  "$t = $t -replace '#DB_USER#', $env:DB_USER; " ^
  "$t = $t -replace '#DB_PASS#', $env:DB_PASS; " ^
  "Set-Content -Path '%PGPASS_LOCAL%' -Value $t -Encoding UTF8; "  ^
  "Add-Content -Path '%PGPASS_LOCAL%' -Value '' -Encoding UTF8"  ^
  ""
if errorlevel 1 (
  echo ERROR: pgpass.local の生成に失敗しました。
  pause & exit /b 1
)
echo 作成: %PGPASS_LOCAL%

REM --- run_pgbench.ps1 生成（UTF-8）---
if not exist "%TMPL%" (
  echo ERROR: %TMPL% が見つかりません。run_pgbench.tmpl.ps1 を配置してください。
  pause & exit /b 2
)

if exist "%OUTP%" (
  choice /c YN /m "既存の run_pgbench.ps1 を上書きしますか？"
  if errorlevel 2 (
    echo キャンセルされました。
    pause & exit /b 0
  )
)

"%PWSH%" -NoLogo -NoProfile -Command ^
  "$t = Get-Content -Raw -Path '%TMPL%'; " ^
  "$t = $t.Replace('#DB_HOST#','%DB_HOST%'); " ^
  "$t = $t.Replace('#DB_PORT#','%DB_PORT%'); " ^
  "$t = $t.Replace('#DB_USER#','%DB_USER%'); " ^
  "Set-Content -Encoding UTF8 '%OUTP%' -Value $t"
if errorlevel 1 (
  echo ERROR: run_pgbench.ps1 の生成に失敗しました。
  pause & exit /b 1
)
echo 生成: %OUTP%

REM --- DB 作成：失敗しても続行（既存や権限不足を想定） ---
set "PGPASSWORD=%DB_PASS%"
echo CREATE DATABASE %DB_NAME% ...
"%PSQL%" -h "%DB_HOST%" -p %DB_PORT% -U "%DB_USER%" -d postgres -c "CREATE DATABASE %DB_NAME%;" 1>nul 2>&1 && (
  echo 作成しました: %DB_NAME%
) || (
  echo WARN: CREATE DATABASE に失敗しました。（既に存在する・権限不足などの可能性）
  echo      このまま続行します。必要なら手動で作成してください。
)
set "PGPASSWORD="

echo.
echo 準備完了。windows\launch_all.bat または run_pgbench.ps1 を実行してください。
pause
endlocal
