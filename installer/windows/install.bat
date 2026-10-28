@echo off
rem reaper-web-faders installer for Windows (runs install.ps1 next to this file)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
pause
