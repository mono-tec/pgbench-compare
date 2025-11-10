@echo off
REM ============================================================
REM  prep_db.bat - ベンチ用DB作成 & run_pgbench.ps1 / launch_all.bat 生成
REM  前提:
REM    - PowerShell 7 (pwsh.exe)
REM    - psql が PATH にある（無ければ PSQL 変数をフルパスに）
REM ============================================================

setlocal ENABLEDELAYEDEXPANSION

echo =============================================================
echo  pgbench ベンチマーク環境 準備ツール
echo -------------------------------------------------------------
echo  このバッチは以下の処理を行います:
echo   1. PostgreSQL の接続情報を入力し、run_pgbench.ps1 / launch_all.bat を生成します。
echo   2. run_pgbench.tmpl.ps1 をもとに run_pgbench.ps1 を生成します。
echo   3. launch_all.bat.tmpl をもとに launch_all.bat を生成します。
echo   4. 指定されたデータベースが存在しない場合は CREATE DATABASE を試行します。
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

REM InnoReplacer.exe の配置場所（例：リポジトリの tool/ 配下）
set "INNO_REPLACER=%~dp0..\tool\InnoReplacer.exe"

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

REM --- windows ---
set "WINDOWS_DIR=%BASE%windows"
set "TMPL_LAUNCH=%WINDOWS_DIR%\launch_all.bat.tmpl"
set "OUT_LAUNCH=%WINDOWS_DIR%\launch_all.bat"

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

REM PowerShell で環境変数を使って安全に置換
set "ENV_DB_NAME=%DB_NAME%"
set "ENV_DB_HOST=%DB_HOST%"
set "ENV_DB_PORT=%DB_PORT%"
set "ENV_DB_USER=%DB_USER%"
set "ENV_DB_PASS=%DB_PASS%"

"%PWSH%" -NoLogo -NoProfile -Command ^
  "$t = Get-Content -Raw -Path '%TMPL%';" ^
  "$t = $t.Replace('#DB_NAME#',  $env:ENV_DB_NAME);"  ^
  "$t = $t.Replace('#DB_HOST#',  $env:ENV_DB_HOST);"  ^
  "$t = $t.Replace('#DB_PORT#',  $env:ENV_DB_PORT);"  ^
  "$t = $t.Replace('#DB_USER#',  $env:ENV_DB_USER);"  ^
  "$t = $t.Replace('#DB_PASS#',  $env:ENV_DB_PASS);"  ^
  "Set-Content -Encoding UTF8 '%OUTP%' -Value $t"
if errorlevel 1 (
  echo ERROR: run_pgbench.ps1 の生成に失敗しました。
  pause & exit /b 1
)
echo 生成: %OUTP%

REM --- launch_all.bat 生成（テンプレ → 実体, SJISのまま）---
if not exist "%TMPL_LAUNCH%" (
  echo ERROR: %TMPL_LAUNCH% が見つかりません。launch_all.bat.tmpl を配置してください。
  pause & exit /b 2
)

if exist "%OUT_LAUNCH%" (
  choice /c YN /m "既存の launch_all.bat を上書きしますか？"
  if errorlevel 2 (
    echo キャンセルされました。
    pause & exit /b 0
  )
)

COPY /Y "%TMPL_LAUNCH%" "%OUT_LAUNCH%" >nul
if errorlevel 1 (
  echo ERROR: launch_all.bat のコピーに失敗しました。
  pause & exit /b 1
)

REM --- ここから置換実行（Shift-JIS のまま）---
REM 表記ゆれ対策：#DB_NAME# を置換
call :REPLACE_SJIS "%OUT_LAUNCH%" "#DB_NAME#"  "%DB_NAME%"
if errorlevel 1 (
  echo ERROR: launch_all.bat の置換（#DB_NAME#）に失敗しました。
  pause & exit /b 1
)

REM 残存チェック（置換漏れがないか警告）
findstr /C:"#DB_NAME#"  "%OUT_LAUNCH%" >nul && (
  echo WARN: launch_all.bat に "#DB_NAME#" が残っています。テンプレ表記をご確認ください。
)

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
exit /b 0

REM ================================================
REM  InnoReplacer で Shift-JIS のまま置換する関数
REM    %1 = 入力ファイル（.bat, SJIS）
REM    %2 = 置換前文字列（プレースホルダ）
REM    %3 = 置換後文字列（DB 名）
REM ================================================
:REPLACE_SJIS
if not exist "%INNO_REPLACER%" (
  echo ERROR: InnoReplacer.exe が見つかりません: "%INNO_REPLACER%"
  echo        tool\ に配置するか、INNO_REPLACER のパスを修正してください。
  exit /b 1
)

set "_IN=%~1"
set "_FROM=%~2"
set "_TO=%~3"

if not exist "%_IN%" (
  echo WARN : 対象が見つかりません: "%_IN%"
  exit /b 0
)

set "_OUT=%_IN%.tmp"
"%INNO_REPLACER%" "%_IN%" "%_FROM%" "%_TO%" sjis

if errorlevel 1 (
  echo ERROR: InnoReplacer 置換に失敗しました: "%_IN%"
  del /q "%_OUT%" 2>nul
  exit /b 1
)
exit /b 0
