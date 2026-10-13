@echo off
rem Play SSX 3: start the recompiled build from the project root (it opens
rem game\default.xbe relative to the working directory), with the keyboard
rem enabled as player 1 on top of any XInput controller.
rem
rem   Keyboard (the game window must have focus):
rem     Enter      START          Backspace  BACK
rem     Z X A S    A B X Y        Q E        white / black
rem     1 3        left / right trigger
rem     arrows     d-pad          numpad 8/4/2/6   left stick
rem     I J K L    right stick    Shift / Ctrl     stick clicks
rem   An Xbox/XInput controller works too and needs no setting.
rem
rem Logs go to play_stdout.txt / play_stderr.txt (console output slows it);
rem earlier runs are kept in logs\ (tools\archive_logs.ps1).
setlocal
cd /d "%~dp0.."
if not defined RECOMP_KEYBOARD set RECOMP_KEYBOARD=1
powershell -NoProfile -ExecutionPolicy Bypass -Command ". '%~dp0archive_logs.ps1'; Save-PreviousLogs '%CD%' 'play_'"
start "SSX 3" /b build\ssx3_recomp.exe > play_stdout.txt 2> play_stderr.txt
