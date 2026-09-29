@echo off
setlocal
call "%~dp0Update-Lia.bat" quality-8b
exit /b %ERRORLEVEL%
