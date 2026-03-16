#!/usr/bin/env bash

set -euo pipefail

PID_FILE="$HOME/.flipper-gitwatch.pid"

if [[ ! -f "$PID_FILE" ]]; then
  echo "No PID file found. Watcher is likely not running."
  exit 0
fi

pid="$(cat "$PID_FILE" || true)"
if [[ -z "$pid" ]]; then
  rm -f "$PID_FILE"
  echo "PID file was empty. Cleaned up."
  exit 0
fi

if kill -0 "$pid" >/dev/null 2>&1; then
  kill "$pid"
  echo "Stopped watcher process: $pid"
else
  echo "Process $pid was not running."
fi

rm -f "$PID_FILE"
