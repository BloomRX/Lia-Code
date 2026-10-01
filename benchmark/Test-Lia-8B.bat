@echo off
setlocal
call "%~dp0..\Update-Lia.bat" quality-8b
exit /b %ERRORLEVEL%
