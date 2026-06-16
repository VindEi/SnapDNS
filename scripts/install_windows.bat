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

:: Register and start the service
:: FIX: Escaped quotes inside binPath to support spaces in the installation directory path
sc create SnapDnsService binPath= "\"%~dp0SnapDnsService.exe\"" start= auto
sc start SnapDnsService

echo.
echo [SUCCESS] Service installed and started! You can now run snapdns.exe.
pause