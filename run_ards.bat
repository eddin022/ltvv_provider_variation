@echo off
setlocal

set "ENV=C:\Users\cas28278\AppData\Local\miniconda3\envs\myR"
set "CONDA_PREFIX=%ENV%"
set "PATH=%ENV%\Library\bin;%ENV%\Scripts;%ENV%\bin;%ENV%\lib\R\bin\x64;%PATH%"

"%ENV%\lib\R\bin\x64\Rscript.exe" "ards_classifier.R"