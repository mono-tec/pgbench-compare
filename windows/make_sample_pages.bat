@echo off
REM ============================================================
REM  make_sample_pages.bat
REM    - tool\Make-SamplePages.ps1 を実行して
REM      samples の HTML ビューを生成するラッパー
REM  使い方:
REM    ダブルクリック  または
REM    make_sample_pages.bat [RootPath]
REM      RootPath 省略時は ..\samples\＜最新v*＞\windows を使用
REM  ※このファイルは Shift-JIS で保存してください
REM ============================================================

setlocal ENABLEDELAYEDEXPANSION

echo =============================================================
echo  make_sample_pages
echo  - samples の HTML ビューを生成します。
echo =============================================================
choice /c YN /m "続行しますか？"
if errorlevel 2 ( echo キャンセルしました。 & pause & exit /b 0 )
echo.

REM ----- 既定パス（先にセット）-----
set "BASE=%~dp0.."
set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
set "SCRIPT=%BASE%\tool\Make-SamplePages.ps1"
REM デフォルト Root（最新 v* を自動検出／引数があれば後で上書き）
set "ROOT="

REM ----- 最新 v* ディレクトリ自動検出（引数が無い場合のみ）-----
if "%~1"=="" (
  for /f "delims=" %%G in ('dir /b /ad /o-n "%BASE%\samples\v*" 2^>nul') do (
    if not defined ROOT set "ROOT=%BASE%\samples\%%G\windows"
  )
) else (
  set "ROOT=%~1"
)

REM フォールバック：pwsh の場所を where で上書き（見つかったら優先）
for /f "delims=" %%P in ('where.exe pwsh 2^>nul') do set "PWSH=%%P"

REM ---- pwsh / スクリプト / ルートの存在確認 ----
if not exist "%PWSH%" (
  echo ERROR: PowerShell 7 が見つかりません。PWSH のパスを修正してください。
  pause & exit /b 1
)
if not exist "%SCRIPT%" (
  echo ERROR: %SCRIPT% が見つかりません。
  pause & exit /b 1
)
if "%ROOT%"=="" (
  echo ERROR: Root が決められませんでした。引数で RootPath を指定してください。
  pause & exit /b 1
)
if not exist "%ROOT%" (
  echo ERROR: Root パスが存在しません: "%ROOT%"
  pause & exit /b 1
)

echo Root: "%ROOT%"


choice /c YN /m "CPU-Z情報のサニタイズをしますか？"
if errorlevel 2 ( GOTO SANITAIZE_END )
echo.
REM サニタイズ（再実行OK・冪等）
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%BASE%\tool\Sanitize-CPUZ.ps1" -Target "%ROOT%"

:SANITAIZE_END

REM HTML生成
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Root "%ROOT%"
if errorlevel 1 (
  echo 生成に失敗しました。
  pause & exit /b 1
)

echo 完了: "%ROOT%\index.html" を確認してください。
pause
endlocal