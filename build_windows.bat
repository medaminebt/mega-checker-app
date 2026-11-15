@echo off
rem Build the Windows app:  build\windows\x64\runner\Release\mega-checker-app.exe
rem and zip the whole Release folder to build\mega-checker-app-windows.zip
rem
rem   build_windows.bat
rem
rem Run it on Windows, from this folder (Command Prompt or PowerShell).
rem Flutter cannot build Windows apps on a Mac: see BUILD.md.
setlocal
cd /d "%~dp0"

call flutter pub get
if errorlevel 1 exit /b 1
call flutter build windows --release
if errorlevel 1 exit /b 1

rem x64 PCs build into x64\, Windows-on-ARM PCs into arm64\.
set "OUT=build\windows\x64\runner\Release"
if not exist "%OUT%\mega-checker-app.exe" set "OUT=build\windows\arm64\runner\Release"

powershell -NoProfile -Command "Compress-Archive -Force -Path %OUT%\* -DestinationPath build\mega-checker-app-windows.zip"

echo.
echo Built:  %CD%\%OUT%\mega-checker-app.exe
echo Zip:    %CD%\build\mega-checker-app-windows.zip
echo Keep the .exe next to its DLLs and "data" folder - copy the whole folder.
endlocal
