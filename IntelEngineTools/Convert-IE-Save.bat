@echo off
setlocal DisableDelayedExpansion
if "%~1"=="" goto usage
if not "%~2"=="" goto usage
if not "%2"=="" goto usage
if /I not "%~x1"==".ess" goto usage
"%~dp0LegacyCacheMigration.exe" fix --save "%~1"
set "result=%errorlevel%"
goto finish
:usage
echo Drag exactly one .ess file onto this launcher. Keep its matching .skse beside it.
set "result=2"
:finish
pause
exit /b %result%
