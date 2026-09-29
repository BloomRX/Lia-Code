@echo off
setlocal
call "%~dp0Update-Lia.bat" quality-both
exit /b %ERRORLEVEL%
