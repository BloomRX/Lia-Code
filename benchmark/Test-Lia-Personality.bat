@echo off
setlocal
call "%~dp0..\Update-Lia.bat" personality
exit /b %ERRORLEVEL%
