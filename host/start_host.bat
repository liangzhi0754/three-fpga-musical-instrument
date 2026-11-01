@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if errorlevel 1 goto use_python
py -3 instrument_host.py
goto finished
:use_python
python instrument_host.py
:finished
if errorlevel 1 echo Launch failed. Run install_dependencies.bat first.
pause
