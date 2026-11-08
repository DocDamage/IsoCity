@echo off
setlocal
pushd "%~dp0"
call godot --path "%~dp0." --resolution 1480x900 res://scenes/builder.tscn
if errorlevel 1 pause
popd
