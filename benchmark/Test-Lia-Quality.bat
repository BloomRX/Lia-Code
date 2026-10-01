@echo off
setlocal
call "%~dp0..\Update-Lia.bat" quality-both
exit /b %ERRORLEVEL%
