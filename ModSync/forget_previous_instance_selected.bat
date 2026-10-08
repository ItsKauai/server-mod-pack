@echo off
set "SEL=%LOCALAPPDATA%\ModSync\install-selection.json"
if exist "%SEL%" (
    del "%SEL%"
    echo Forgot your saved MultiMC / instance choice.
    echo Run Install.bat again to pick an instance.
    echo.
    echo Note: instances that are already set up keep auto-updating.
) else (
    echo Nothing saved - Install.bat will already ask you to pick.
)
echo.
pause
