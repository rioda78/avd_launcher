@echo off
setlocal EnableExtensions
rem Build a runnable Release bundle when "flutter build windows" cannot see
rem Visual Studio (for example if an update was cancelled and the install is
rem marked incomplete). Requires MSVC, CMake, Ninja, and Windows SDK.

set "ROOT=%~dp0"
cd /d "%ROOT%"
set "VS=C:\Program Files\Microsoft Visual Studio\18\Community"
set "VCVARS=%VS%\VC\Auxiliary\Build\vcvarsall.bat"
set "CMAKE=%VS%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
set "NINJA_DIR=%VS%\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"
set "BUILD_DIR=%ROOT%build\windows\x64"
set "RELEASE_DIR=%BUILD_DIR%\runner\Release"

if not exist "%VCVARS%" (
  echo Tidak menemukan vcvarsall.bat di:
  echo   %VCVARS%
  echo Perbaiki instalasi Visual Studio, atau sesuaikan path di skrip ini.
  exit /b 1
)
if not exist "%CMAKE%" (
  echo Tidak menemukan cmake.exe
  exit /b 1
)

call "%VCVARS%" x64
if errorlevel 1 exit /b 1
set "PATH=%NINJA_DIR%;%PATH%"

flutter pub get
if errorlevel 1 exit /b 1

if not exist "%ROOT%windows\flutter\ephemeral" mkdir "%ROOT%windows\flutter\ephemeral"

rem If generated_config.cmake is missing, flutter build windows will write it
rem even when the Visual Studio check later fails.
if not exist "%ROOT%windows\flutter\ephemeral\generated_config.cmake" (
  flutter build windows --release
)

set "FLUTTER_ROOT=C:\flutter"
set "PROJECT_DIR=%ROOT:~0,-1%"
set "FLUTTER_EPHEMERAL_DIR=%PROJECT_DIR%\windows\flutter\ephemeral"
set "FLUTTER_TARGET=lib\main.dart"
set "DART_OBFUSCATION=false"
set "TRACK_WIDGET_CREATION=false"
set "TREE_SHAKE_ICONS=true"
set "PACKAGE_CONFIG=%PROJECT_DIR%\.dart_tool\package_config.json"

call "%FLUTTER_ROOT%\packages\flutter_tools\bin\tool_backend.bat" windows-x64 Release
if errorlevel 1 (
  echo tool_backend gagal.
  exit /b 1
)

"%CMAKE%" -S "%ROOT%windows" -B "%BUILD_DIR%" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_MAKE_PROGRAM="%NINJA_DIR%\ninja.exe" -DFLUTTER_TARGET_PLATFORM=windows-x64
if errorlevel 1 exit /b 1
"%CMAKE%" --build "%BUILD_DIR%"
if errorlevel 1 exit /b 1

if not exist "%RELEASE_DIR%\data" mkdir "%RELEASE_DIR%\data"
copy /Y "%BUILD_DIR%\runner\avd_launcher.exe" "%RELEASE_DIR%\avd_launcher.exe" >nul
copy /Y "%ROOT%windows\flutter\ephemeral\flutter_windows.dll" "%RELEASE_DIR%\" >nul
copy /Y "%ROOT%windows\flutter\ephemeral\icudtl.dat" "%RELEASE_DIR%\data\" >nul
if exist "%BUILD_DIR%\plugins\file_selector_windows\file_selector_windows_plugin.dll" (
  copy /Y "%BUILD_DIR%\plugins\file_selector_windows\file_selector_windows_plugin.dll" "%RELEASE_DIR%\" >nul
)
if exist "%ROOT%build\windows\app.so" copy /Y "%ROOT%build\windows\app.so" "%RELEASE_DIR%\data\app.so" >nul
if exist "%ROOT%build\flutter_assets" (
  if exist "%RELEASE_DIR%\data\flutter_assets" rmdir /S /Q "%RELEASE_DIR%\data\flutter_assets"
  xcopy /E /I /Y "%ROOT%build\flutter_assets" "%RELEASE_DIR%\data\flutter_assets" >nul
)

echo.
echo Selesai. Jalankan:
echo   %RELEASE_DIR%\avd_launcher.exe
exit /b 0
