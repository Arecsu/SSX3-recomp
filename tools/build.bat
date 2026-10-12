@echo off
rem Release build with MSVC + the Ninja that ships with Visual Studio.
rem Ninja compiles the generated chunks in parallel; the VS generator would
rem compile them one at a time (the template sets no /MP).
rem   tools\build.bat [jobs]     (default 16) -> build\ssx3_recomp.exe
setlocal
set JOBS=%1
if "%JOBS%"=="" set JOBS=16
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
cd /d "%~dp0.."
if not exist build\build.ninja (
    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release || exit /b 1
)
cmake --build build --parallel %JOBS%
exit /b %errorlevel%
