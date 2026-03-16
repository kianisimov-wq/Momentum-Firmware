#!/usr/bin/env bash

set -euo pipefail

REMOTE="${1:-origin}"
BRANCH="${2:-main}"
INTERVAL_SECONDS="${3:-180}"

if ! [[ "$INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || [[ "$INTERVAL_SECONDS" -lt 60 ]]; then
  echo "Usage: $0 [remote] [branch] [interval_seconds>=60]"
  echo "Example: $0 origin main 180"
  exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs/flipper-gitwatch"
LABEL="com.flipper.gitwatch"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$LABEL.plist"
WATCH_SCRIPT="$REPO_DIR/scripts/watch_remote_updates.sh"
STDOUT_LOG="$LOG_DIR/git-watch.log"
STDERR_LOG="$LOG_DIR/git-watch.err.log"

mkdir -p "$LAUNCH_AGENTS_DIR"
mkdir -p "$LOG_DIR"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>$LABEL</string>

    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>-lc</string>
      <string>cd "$REPO_DIR" &amp;&amp; git fetch "$REMOTE" --quiet &amp;&amp; if git rev-parse "$REMOTE/$BRANCH" &gt;/dev/null 2&gt;&amp;1; then if [ "$(git rev-parse HEAD)" = "$(git rev-parse "$REMOTE/$BRANCH")" ]; then echo "[$(date '+%Y-%m-%d %H:%M:%S')] Up to date with $REMOTE/$BRANCH."; else echo "[$(date '+%Y-%m-%d %H:%M:%S')] Updates detected on $REMOTE/$BRANCH"; git log --oneline --max-count 10 HEAD.."$REMOTE/$BRANCH"; fi; else echo "[$(date '+%Y-%m-%d %H:%M:%S')] Remote branch $REMOTE/$BRANCH not found."; fi</string>
    </array>

    <key>WorkingDirectory</key>
    <string>$REPO_DIR</string>

    <key>StandardOutPath</key>
    <string>$STDOUT_LOG</string>

    <key>StandardErrorPath</key>
    <string>$STDERR_LOG</string>

    <key>StartInterval</key>
    <integer>$INTERVAL_SECONDS</integer>

    <key>RunAtLoad</key>
    <true/>
  </dict>
</plist>
PLIST

if launchctl list | grep -q "$LABEL"; then
  launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
fi

launchctl load "$PLIST_PATH"

echo "Installed LaunchAgent: $LABEL"
echo "Plist: $PLIST_PATH"
echo "Remote/branch: $REMOTE/$BRANCH"
echo "Interval: $INTERVAL_SECONDS seconds"
echo "Log file: $STDOUT_LOG"
echo "Error log: $STDERR_LOG"
echo ""
echo "Useful commands:"
echo "  launchctl list | grep $LABEL"
echo "  tail -f \"$STDOUT_LOG\""
echo "  tail -f \"$STDERR_LOG\""
echo "  launchctl unload \"$PLIST_PATH\""
