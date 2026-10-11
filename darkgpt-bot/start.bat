@echo off
cd /d "%~dp0"
if not exist node_modules (
  echo Installing, one moment...
  call npm install
)
node bot.js
pause
