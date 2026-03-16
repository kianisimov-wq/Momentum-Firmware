#!/usr/bin/env bash

set -euo pipefail

REMOTE="${1:-origin}"
BRANCH="${2:-main}"
INTERVAL_MINUTES="${3:-0}"

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

notify_mac() {
  local message="$1"
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$message\" with title \"Git Remote Updates\"" >/dev/null 2>&1 || true
  fi
}

check_once() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[$(timestamp)] Not inside a git repository."
    return 1
  fi

  if ! git fetch "$REMOTE" --quiet; then
    echo "[$(timestamp)] Could not fetch from remote '$REMOTE'."
    echo "Hint: add it first with: git remote add $REMOTE <repo-url>"
    return 1
  fi

  local local_ref
  local remote_ref
  local_ref="$(git rev-parse HEAD)"
  remote_ref="$(git rev-parse "$REMOTE/$BRANCH" 2>/dev/null || true)"

  if [[ -z "$remote_ref" ]]; then
    echo "[$(timestamp)] Remote branch '$REMOTE/$BRANCH' was not found."
    echo "Hint: verify branch with: git branch -r"
    return 1
  fi

  if [[ "$local_ref" == "$remote_ref" ]]; then
    echo "[$(timestamp)] Up to date with $REMOTE/$BRANCH."
    return 0
  fi

  local incoming_count
  local local_only_count
  incoming_count="$(git rev-list --count "$local_ref..$remote_ref")"
  local_only_count="$(git rev-list --count "$remote_ref..$local_ref")"

  echo "[$(timestamp)] Changes detected against $REMOTE/$BRANCH"
  echo "Incoming commits (their side): $incoming_count"
  echo "Local-only commits (your side): $local_only_count"

  if [[ "$incoming_count" -gt 0 ]]; then
    echo "Recent incoming commits:"
    git log --oneline --max-count 10 "$local_ref..$remote_ref"
    notify_mac "$incoming_count new commit(s) on $REMOTE/$BRANCH"
  fi

  if [[ "$local_only_count" -gt 0 ]]; then
    echo "Recent local-only commits:"
    git log --oneline --max-count 10 "$remote_ref..$local_ref"
  fi
}

if ! [[ "$INTERVAL_MINUTES" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 [remote] [branch] [interval_minutes]"
  echo "Example: $0 origin main 3"
  exit 1
fi

if [[ "$INTERVAL_MINUTES" -eq 0 ]]; then
  check_once
  exit $?
fi

sleep_seconds=$((INTERVAL_MINUTES * 60))
echo "Watching $REMOTE/$BRANCH every $INTERVAL_MINUTES minute(s). Press Ctrl+C to stop."

while true; do
  check_once || true
  sleep "$sleep_seconds"
done
