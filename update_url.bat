@echo off
echo ========================================
echo  Update API URL for Railway Deployment
echo ========================================
echo.

if "%1"=="" (
    echo Usage: update_url.bat [YOUR_RAILWAY_URL]
    echo Example: update_url.bat https://autocraft-production.up.railway.app
    echo.
    pause
    exit /b 1
)

echo Updating API URL to: %1
echo.

python update_api_url.py %1

echo.
pause
