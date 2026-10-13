@echo off
rem Release build with MSVC + the Ninja that ships with Visual Studio.
rem Ninja compiles the generated chunks in parallel; the VS generator would
rem compile them one at a time (the template sets no /MP).
rem   tools\build.bat [jobs] [abi]   (default 16) -> build\ssx3_recomp.exe
rem   "abi" builds build-abi\ with -DRECOMP_ABI_CHECK: every call checks that
rem   the callee preserved ebx/esi/edi and logs "[ABI] sub_XXXXXXXX" when not.
setlocal
set JOBS=%1
if "%JOBS%"=="" set JOBS=16
set DIR=build
set FLAGS=
if /i "%2"=="abi" (
    set DIR=build-abi
    set FLAGS=-DCMAKE_C_FLAGS=/DRECOMP_ABI_CHECK
)
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
cd /d "%~dp0.."
if not exist %DIR%\build.ninja (
    cmake -S . -B %DIR% -G Ninja -DCMAKE_BUILD_TYPE=Release %FLAGS% || exit /b 1
)
cmake --build %DIR% --parallel %JOBS%
exit /b %errorlevel%
