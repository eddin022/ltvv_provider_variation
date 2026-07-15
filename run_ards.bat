@echo off
setlocal

:: Change to the directory containing this script so relative paths resolve correctly
pushd "%~dp0"

:: Set RSCRIPT to your Rscript.exe path before running, e.g.:
::   set RSCRIPT=C:\Users\yourname\AppData\Local\miniconda3\envs\myR\lib\R\bin\x64\Rscript.exe
:: Or add Rscript to your system PATH and leave this variable unset.

if not defined RSCRIPT (
    set "RSCRIPT=Rscript"
)

:: If RSCRIPT points into a conda env, add that env's DLL directories to PATH
:: so Windows can find the required shared libraries (fixes 0xC0000135).
for %%F in ("%RSCRIPT%") do set "RSCRIPT_DIR=%%~dpF"
for %%A in ("%RSCRIPT_DIR%..") do for %%B in ("%%~fA\..") do ^
for %%C in ("%%~fB\..") do for %%D in ("%%~fC\..") do set "CONDA_ENV=%%~fD"
if exist "%CONDA_ENV%\Library\bin" (
    set "PATH=%CONDA_ENV%\Library\bin;%CONDA_ENV%\Library\mingw-w64\bin;%CONDA_ENV%\Scripts;%CONDA_ENV%\bin;%PATH%"
)

"%RSCRIPT%" "ards_classifier.R"
set RCODE=%ERRORLEVEL%

popd
exit /b %RCODE%
