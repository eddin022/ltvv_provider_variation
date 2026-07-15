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

"%RSCRIPT%" "ards_classifier.R"
set RCODE=%ERRORLEVEL%

popd
exit /b %RCODE%
