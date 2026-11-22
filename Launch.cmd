@echo off
setlocal
where godot >nul 2>nul
if errorlevel 1 (
    echo Godot 4 was not found on PATH.
    echo Open project.godot in Godot 4 and press F5.
    pause
    exit /b 1
)
if not exist "%~dp0.godot\global_script_class_cache.cfg" (
    call godot --headless --path "%~dp0." --editor --import
    if errorlevel 1 goto failed
)
call godot --path "%~dp0." -- %*
if errorlevel 1 goto failed
exit /b 0

:failed
echo Godot could not start the project. Check the log above.
pause
exit /b 1
