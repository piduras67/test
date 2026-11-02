#!/bin/sh
cd "$(dirname "$0")"
echo "Ragdoll Range on http://localhost:8000"
(sleep 1; xdg-open http://localhost:8000 2>/dev/null || open http://localhost:8000) &
python3 -m http.server 8000
