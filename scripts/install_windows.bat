@echo off
echo ====================================================
echo SnapDNS Service Installer (Windows)
echo ====================================================
:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Please right-click this file and select "Run as Administrator".
    pause
    exit /b 1
)

:: Register or update and start the service
sc query SnapDnsService >nul 2>&1
if %errorLevel% equ 0 (
    echo Updating existing SnapDnsService...
    sc stop SnapDnsService >nul 2>&1
    sc config SnapDnsService binPath= "\"%~dp0SnapDnsService.exe\"" start= auto >nul
) else (
    echo Registering SnapDnsService...
    sc create SnapDnsService binPath= "\"%~dp0SnapDnsService.exe\"" start= auto >nul
)

sc start SnapDnsService

echo.
echo [SUCCESS] Service installed and started! You can now run snapdns.exe.
pause
