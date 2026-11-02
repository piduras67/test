@echo off
cd /d "%~dp0"
echo Starting Baseplate on http://localhost:8000  (close this window to stop)
where py >nul 2>nul && (start "" http://localhost:8000 & py -m http.server 8000 & goto :eof)
where python >nul 2>nul && (start "" http://localhost:8000 & python -m http.server 8000 & goto :eof)
where npx >nul 2>nul && (start "" http://localhost:8000 & npx --yes http-server -p 8000 -c-1 & goto :eof)
echo Python or Node.js is needed. Install Python from https://www.python.org/downloads/ and run this again.
pause
