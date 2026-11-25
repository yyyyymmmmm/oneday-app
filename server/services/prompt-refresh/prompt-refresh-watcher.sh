#!/bin/bash
# prompt-refresh-watcher.sh -- hermes-deploy 2.7.1
#
# Rule (user, 2026-11-26): memory/config updates must reach the main
# OneDay conversation WITHOUT discarding it. Hermes builds a session's
# system prompt once and reuses it across turns; for api_server
# sessions the built prompt lives only in the gateway process memory
# (the sessions.system_prompt row stays NULL), so a gateway restart is
# the refresh: the next turn of the existing conversation rebuilds its
# prompt from the current files. Conversation history is never touched.
#
# This watcher runs from host cron every 10 minutes. When any watched
# file (memories/MEMORY.md, memories/USER.md, config.yaml) is newer
# than the stamp, and the gateway looks idle (no message written in
# the last 240s -- a live run writes rows as it works), it restarts
# the hermes container once, waits for /health, advances the stamp and
# logs. Busy ticks simply retry 10 minutes later.
#
# Install (on the server, as root):
#   mkdir -p /root/prompt-refresh
#   cp prompt-refresh-watcher.sh /root/prompt-refresh/
#   chmod +x /root/prompt-refresh/prompt-refresh-watcher.sh
#   crontab: */10 * * * * /root/prompt-refresh/prompt-refresh-watcher.sh
# Remove: delete the crontab line; the stamp/log stay as records.
set -u
DEPLOY=/www/dk_project/dk_app/hermes
STATE=/root/prompt-refresh
STAMP=$STATE/stamp
LOG=$STATE/watcher.log
mkdir -p "$STATE"
[ -f "$STAMP" ] || touch -d "1970-01-01" "$STAMP"

changed=0
for f in "$DEPLOY/data/memories/MEMORY.md" "$DEPLOY/data/memories/USER.md" "$DEPLOY/data/config.yaml"; do
  [ -f "$f" ] && [ "$f" -nt "$STAMP" ] && changed=1
done
[ "$changed" = "1" ] || exit 0

# Busy check: newest message row age (seconds) via the container python.
age=$(docker exec hermes python3 -c "
import sqlite3, time
db = sqlite3.connect('file:/opt/data/state.db?mode=ro', uri=True)
r = db.execute('SELECT MAX(timestamp) FROM messages').fetchone()
print(int(time.time() - r[0]) if r and r[0] else 999999)
" 2>/dev/null || echo 0)
case "$age" in ''|*[!0-9]*) age=0 ;; esac
if [ "$age" -lt 240 ]; then
  echo "$(date '+%F %T') skip: gateway busy (last message ${age}s ago)" >> "$LOG"
  exit 0
fi

cd "$DEPLOY" && docker compose restart hermes >> "$LOG" 2>&1
for i in $(seq 1 20); do
  sleep 6
  if curl -s -m 4 http://127.0.0.1:8642/health 2>/dev/null | grep -q '"ok"'; then
    touch "$STAMP"
    echo "$(date '+%F %T') refreshed: gateway restarted after memory/config change" >> "$LOG"
    exit 0
  fi
done
echo "$(date '+%F %T') ERROR: gateway did not come back healthy after restart" >> "$LOG"
exit 1
