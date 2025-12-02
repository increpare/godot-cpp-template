@echo off
REM Build script for Windows GDExtension
REM Usage: build-windows.bat [windows32|windows64|windows]

if "%1"=="" goto :windows64
if "%1"=="windows32" goto :windows32
if "%1"=="windows64" goto :windows64
if "%1"=="windows" goto :windows

echo Unknown target: %1
echo Usage: build-windows.bat [windows32^|windows64^|windows]
exit /b 1

:windows32
echo Building Windows 32-bit (debug)...
python -m SCons platform=windows arch=x86_32 target=template_debug
if errorlevel 1 (
    echo Build failed!
    exit /b 1
)

echo Building Windows 32-bit (release)...
python -m SCons platform=windows arch=x86_32 target=template_release
if errorlevel 1 (
    echo Build failed!
    exit /b 1
)
echo Windows 32-bit build complete!
goto :end

:windows64
echo Building Windows 64-bit (debug)...
python -m SCons platform=windows arch=x86_64 target=template_debug
if errorlevel 1 (
    echo Build failed!
    exit /b 1
)

echo Building Windows 64-bit (release)...
python -m SCons platform=windows arch=x86_64 target=template_release
if errorlevel 1 (
    echo Build failed!
    exit /b 1
)
echo Windows 64-bit build complete!
goto :end

:windows
echo Building Windows 32-bit...
call :windows32
if errorlevel 1 exit /b 1
echo.
echo Building Windows 64-bit...
call :windows64
if errorlevel 1 exit /b 1
echo.
echo All Windows builds complete!
goto :end

:end
@echo "Deploying to egg folder..."
@copy demo\bin\windows\*.* C:\Users\Anwender\Documents\GitHub\godot-cpp-template\bin\windows\
@echo "Deployment complete!"

