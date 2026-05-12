@echo off
REM Sprint 1 — Data Bridge Prototype launcher
REM Double-click to run, or invoke from cmd. Adjust GODOT_EXE if you move Godot.

set "GODOT_EXE=C:\Users\thoma\Godot\v4.3\Godot_v4.3-stable_win64.exe"

if not exist "%GODOT_EXE%" (
    echo ERROR: Godot not found at %GODOT_EXE%
    echo Edit run.bat and update GODOT_EXE to your local Godot install.
    pause
    exit /b 1
)

"%GODOT_EXE%" --path "%~dp0"
