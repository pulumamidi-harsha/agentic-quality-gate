@echo off
REM Windows entrypoint for run-qg — needs Git for Windows (bash).
setlocal EnableExtensions

set "HUB=%AGENTIC_QUALITY_GATE_HOME%"
if "%HUB%"=="" set "HUB=%USERPROFILE%\.cursor\agentic-quality-gate"
set "GATE=%HUB%\scripts\run-qg.sh"

if not exist "%GATE%" (
  echo error: quality gate not installed.
  echo   From your app repo in PowerShell:
  echo   irm https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-app.ps1 ^| iex
  exit /b 2
)

set "BASH="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if "%BASH%"=="" if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if "%BASH%"=="" where bash >nul 2>&1 && for /f "delims=" %%i in ('where bash') do set "BASH=%%i" & goto :have_bash
if "%BASH%"=="" (
  echo error: Git for Windows bash not found. Install Git for Windows, then reopen the terminal.
  exit /b 2
)
:have_bash

"%BASH%" "%GATE%" %*
exit /b %ERRORLEVEL%
