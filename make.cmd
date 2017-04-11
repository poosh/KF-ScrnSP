@echo off
color 07

setlocal
set KFDIR=D:\Games\kf
set STEAMDIR=c:\Steam\steamapps\common\KillingFloor
rem remember current directory
set CURDIR=%~dp0

cd /D %KFDIR%\System
del ScrnSP.u

ucc make
set ERR=%ERRORLEVEL%
if %ERR% NEQ 0 goto error
color 0A

rem mark package as server-side only 
ucc packageflag ScrnSP.u ScrnSPSR.u +ServerSideOnly 
del ScrnSP.u
ren ScrnSPSR.u ScrnSP.u


del KillingFloor.log
del steam_appid.txt

del %STEAMDIR%\System\KillingFloor.log
copy ScrnSP.* %STEAMDIR%\System\


rem return to previous directory
cd /D %CURDIR%

endlocal

echo --------------------------------
echo Compile successful.
echo --------------------------------
goto end

:error
color 0C
echo ################################
echo Compile ERROR! Code = %ERR%.
echo ################################

:end
pause

set ERRORLEVEL=%ERR%