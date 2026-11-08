@echo off
setlocal
pushd "%~dp0"
call godot --editor --path "%~dp0."
if errorlevel 1 pause
popd
