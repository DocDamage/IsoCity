@echo off
setlocal
pushd "%~dp0"
call godot --path "%~dp0." res://scenes/main.tscn
if errorlevel 1 pause
popd
