@echo off
REM ============================================================
REM  summarize.bat - ベンチマーク結果の集計（JSON → CSV）
REM ------------------------------------------------------------
REM  results/raw/ の result_*.json を集約し、results/summary.csv を出力
REM  前提:
REM    - PowerShell 7 (pwsh.exe)
REM    - ルート直下に summarize.ps1 があること
REM  仕様:
REM    - 既存 summary.csv がある場合は上書き確認し、バックアップを自動作成
REM ============================================================

setlocal enabledelayedexpansion

REM ルートパス（windows\ の親）
set BASE=%~dp0..\
set PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe
set RAWDIR=%BASE%results\raw
set OUTDIR=%BASE%results
set OUTCSV=%OUTDIR%\summary.csv
set SUMPS1=%BASE%summarize.ps1

echo.
echo ============================================================
echo  PostgreSQL ベンチ結果集計ツール
echo  summarize.ps1 を呼び出して summary.csv を生成します。
echo ============================================================
echo.

REM ---- PowerShell 7 の存在確認（pwsh フォールバック）----
if not exist "%PWSH%" (
  for /f "delims=" %%P in ('where.exe pwsh 2^>nul') do set "PWSH=%%P"
)
if not exist "%PWSH%" (
  echo ERROR: PowerShell 7 が見つかりません。PWSH のパスを修正してください。
  pause & exit /b 1
)

REM --- スクリプト／出力先ディレクトリの確認 ---
if not exist "%SUMPS1%" (
  echo ERROR: summarize.ps1 が見つかりません: "%SUMPS1%"
  pause & exit /b 1
)

if not exist "%OUTDIR%" mkdir "%OUTDIR%"
if not exist "%RAWDIR%" (
  echo WARN: 入力ディレクトリがありません: "%RAWDIR%"
  echo       先に run_pgbench.ps1 を実行して JSON を生成してください。
  pause & exit /b 2
)

REM --- 上書き確認＋自動バックアップ ---
if exist "%OUTCSV%" (
  echo 既存の %OUTCSV% が見つかりました。
  choice /c YN /m "上書きして再生成しますか？"
  if errorlevel 2 (
    echo.
    echo キャンセルしました。
    pause & exit /b 0
  )
 
 :: 拡張子を除いたベース名取得
  for %%F in ("%OUTCSV%") do set "basename=%%~nF"
  for %%F in ("%OUTCSV%") do set "ext=%%~xF"

  rem ECHO !basename!
  rem ECHO !ext!

  rem 001～999までループ
  for /L %%i in (1,1,999) do (
    set "num=00%%i"
    set "num=!num:~-3!"
    set "dest=%OUTDIR%\!basename!_!num!!ext!"
    if not exist "!dest!" (
        echo コピー中: "%OUTCSV%" → "!dest!"
        copy /y "%OUTCSV%" "!dest!" >nul
        if errorlevel 1 (
          echo バックアップに失敗しました。書き込み権限やパスを確認してください。
          pause & exit /b 1
        )
        echo バックアップを作成しました: "!dest!"
        goto :EXIT_BACKUP
    )
  )
  echo %OUTCSV%の連番001-999が埋まっています。古いバックアップを整理してください。
  echo 不要なファイルを削除してください。
  pause & exit /b 1

)

:EXIT_BACKUP

REM --- 集計実行（絶対パスで引数を明示） ---
"%PWSH%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SUMPS1%" -RawDir "%RAWDIR%" -OutCsv "%OUTCSV%"
if errorlevel 1 (
  echo.
  echo ERROR: 集計処理に失敗しました。
  pause & exit /b 1
)

echo.
echo 正常に完了しました。結果ファイル: %OUTCSV%
echo.
pause
endlocal