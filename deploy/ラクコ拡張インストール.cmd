@echo off
rem Rakuco extension installer: double-click this file.
rem It asks for administrator permission (UAC) once, then runs install.ps1.
rem The signed-in user's name and LOCALAPPDATA are passed so the right Chrome is restarted.
set "HERE=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command','$env:RAKUCO_USER_LOCALAPPDATA=''%LOCALAPPDATA%''; $env:RAKUCO_USER_NAME=''%USERNAME%''; & ''%HERE%install.ps1''')"
