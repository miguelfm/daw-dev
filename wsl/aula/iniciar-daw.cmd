@echo off
title Inicializacion de DAW Dev
echo ========================================================
echo       Inicializando contorna Debian DAW Dev
echo ========================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\DAW-Aula\iniciar-usuario.ps1"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERRO] Produciuse un erro durante a inicializacion (%ERRORLEVEL%).
) else (
    echo.
    echo [OK] Contorna DAW Dev inicializada correctamente.
)
echo.
pause
