#!/bin/zsh
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO_DIR="/Users/gary/XcodeProjects:BrownsRoster/BrownsRoster1"
LOG_DIR="$REPO_DIR/Logs"

mkdir -p "$LOG_DIR"
cd "$REPO_DIR"

echo "[$(date)] Starting Browns roster update"

python3 Scripts/GetRoster.py --no-notify --skip-headshots

git add BrownsRoster1/Resources/browns.db docs/roster

if git diff --cached --quiet; then
    echo "[$(date)] No roster files changed"
    exit 0
fi

git commit -m "Update roster database $(date +%Y-%m-%d)"
git push https://github.com/Garyi113/BrownsRoster.git main

echo "[$(date)] Browns roster update complete"
