@echo off
REM ============================================================
REM  cleanup_db.bat - ƒxƒ“ƒ`—pƒf[ƒ^ƒx[ƒX‚Ìíœ
REM  ‘O’ñ:
REM    - secrets\pgpass.local ‚ª‚ ‚é‚ÆŠyi–³‚¢ê‡‚Í“s“x“ü—Íj
REM ============================================================

setlocal ENABLEDELAYEDEXPANSION

REM ---- ÀsŠT—v‚Ì•\¦ ------------------------------------------------
echo =============================================================
echo  pgbench ƒxƒ“ƒ`—pƒf[ƒ^ƒx[ƒXíœƒc[ƒ‹
echo -------------------------------------------------------------
echo  ‚±‚Ìƒoƒbƒ`‚ÍˆÈ‰º‚ğs‚¢‚Ü‚·:
echo    1) secrets\pgpass.local ‚ª‚ ‚ê‚ÎÚ‘±î•ñ‚ğ“Ç‚İ‚İ
echo       –³‚¯‚ê‚Î Host/Port/DB/User/Password ‚ğ‘Î˜b“ü—Í‚µ‚Ü‚·B
echo    2) ‘ÎÛƒf[ƒ^ƒx[ƒX‚É‘Î‚µ‚Ä
echo       DROP DATABASE IF EXISTS ‚ğÀs‚µ‚Ü‚·B
echo.
echo  ¦”j‰ó“I‚È‘€ì‚Å‚·BŒë‚Á‚½ DB –¼‚É’ˆÓ‚µ‚Ä‚­‚¾‚³‚¢B
echo =============================================================
echo.
choice /c YN /m "‘±s‚µ‚Ü‚·‚©H"
if errorlevel 2 (
  echo ƒLƒƒƒ“ƒZƒ‹‚µ‚Ü‚µ‚½B
  pause & exit /b 0
)
echo.

set "BASE=%~dp0.."
set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
set "SECRETS_DIR=%BASE%\secrets"
set "PGPASS_LOCAL=%SECRETS_DIR%\pgpass.local"

REM ---- psql ‚Ì‘¶İŠm”F ----
for /f "delims=" %%P in ('where.exe psql 2^>nul') do set "PSQL=%%P"
if not defined PSQL (
  echo ERROR: psql ‚ªŒ©‚Â‚©‚è‚Ü‚¹‚ñBPATH ‚ğ’Ê‚·‚©Aƒtƒ‹ƒpƒX‚ğİ’è‚µ‚Ä‚­‚¾‚³‚¢B
  pause & exit /b 1
)
echo Using psql: "%PSQL%"
echo.

set "DB_HOST="
set "DB_PORT="
set "DB_NAME="
set "DB_USER="
set "DB_PASS="

if exist "%PGPASS_LOCAL%" (
  for /f "usebackq delims=" %%L in ("%PGPASS_LOCAL%") do (
    for /f "tokens=1-5 delims=:" %%a in ("%%~L") do (
      set "DB_HOST=%%a"
      set "DB_PORT=%%b"
      set "DB_NAME=%%c"
      set "DB_USER=%%d"
      set "DB_PASS=%%e"
    )
    goto :HAVE_CONF
  )
)

:HAVE_CONF
if "%DB_HOST%"=="" set /p DB_HOST=Host ?:
if "%DB_PORT%"=="" set /p DB_PORT=Port ?:
if "%DB_NAME%"=="" set /p DB_NAME=Database ?:
if "%DB_USER%"=="" set /p DB_USER=User ?:
if "%DB_PASS%"=="" (
  for /f "usebackq delims=" %%P in (`
    "%PWSH%" -NoProfile -Command ^
      "$p=Read-Host 'Postgres password' -AsSecureString; " ^
      "$b=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($p); " ^
      "[Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)"
  `) do set "DB_PASS=%%P"
)

echo íœ‘ÎÛ: %DB_USER%@%DB_HOST%:%DB_PORT%/%DB_NAME%
choice /c YN /m "–{“–‚Éíœ‚µ‚Ü‚·‚©H"
if errorlevel 2 (
  echo ƒLƒƒƒ“ƒZƒ‹‚µ‚Ü‚µ‚½B
  pause & exit /b 0
)

set "PGPASSWORD=%DB_PASS%"
"%PSQL%" -h "%DB_HOST%" -p %DB_PORT% -U "%DB_USER%" -d postgres -c "DROP DATABASE IF EXISTS %DB_NAME%;" || (
  echo ERROR: DROP DATABASE ‚É¸”s‚µ‚Ü‚µ‚½B
)
set PGPASSWORD=

echo.
echo [92m[OK] ƒf[ƒ^ƒx[ƒXíœŠ®—¹: %DB_NAME%[0m
pause
endlocal
