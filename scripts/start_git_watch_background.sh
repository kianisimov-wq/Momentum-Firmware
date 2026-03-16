#!/usr/bin/env bash

set -euo pipefail

REMOTE="${1:-origin}"
BRANCH="${2:-main}"
INTERVAL_MINUTES="${3:-3}"

if ! [[ "$INTERVAL_MINUTES" =~ ^[0-9]+$ ]] || [[ "$INTERVAL_MINUTES" -lt 1 ]]; then
  echo "Usage: $0 [remote] [branch] [interval_minutes>=1]"
  echo "Example: $0 origin main 3"
  exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PID_FILE="$HOME/.flipper-gitwatch.pid"
LOG_FILE="$HOME/.flipper-gitwatch.log"

if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" || true)"
  if [[ -n "${old_pid:-}" ]] && kill -0 "$old_pid" >/dev/null 2>&1; then
    echo "Watcher already running with PID $old_pid"
    echo "Log: $LOG_FILE"
    exit 0
  fi
fi

nohup bash -lc "cd \"$REPO_DIR\" && ./scripts/watch_remote_updates.sh \"$REMOTE\" \"$BRANCH\" \"$INTERVAL_MINUTES\"" >> "$LOG_FILE" 2>&1 &
new_pid=$!
echo "$new_pid" > "$PID_FILE"

echo "Started watcher in background."
echo "PID: $new_pid"
echo "Tracking: $REMOTE/$BRANCH every $INTERVAL_MINUTES minute(s)"
echo "Log: $LOG_FILE"
echo "Stop with: ./scripts/stop_git_watch_background.sh"
