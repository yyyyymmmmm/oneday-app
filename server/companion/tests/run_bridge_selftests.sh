#!/bin/sh
# Run the bridges' own selftests against the exact module copies that
# ship in the companion image (staged into a temp dir, repo stays clean).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
STAGE=$(mktemp -d)
cp "$ROOT"/modules/*.py "$STAGE"/
if [ -d "$ROOT/modules/assets" ]; then cp -r "$ROOT/modules/assets" "$STAGE/"; fi
cp "$HERE"/overview_bridge_selftest.py "$HERE"/device_bridge_selftest.py \
   "$HERE"/device_sync_selftest.py "$HERE"/write_gate_rules_selftest.py \
   "$HERE"/write_gate_anchor_selftest.py "$HERE"/write_gate_blocked_selftest.py \
   "$HERE"/write_gate_anchor_ledger_selftest.py \
   "$HERE"/oneday_bridge_p2_selftest.py "$HERE"/oneday_bridge_p3_selftest.py \
   "$HERE"/oneday_bridge_p4_selftest.py "$HERE"/oneday_bridge_p5_selftest.py \
   "$HERE"/oneday_bridge_p6_selftest.py "$HERE"/oneday_bridge_p7_selftest.py \
   "$HERE"/oneday_bridge_p8_selftest.py "$HERE"/oneday_bridge_p9_selftest.py \
   "$HERE"/fileproc_bridge_spreadsheet_selftest.py \
   "$HERE"/fileproc_bridge_rendition_selftest.py \
   "$HERE"/channels_bridge_selftest.py \
   "$HERE"/oneday_delivery_selftest.py \
   "$HERE"/oneday_delivery_sentinel_selftest.py \
   "$HERE"/oneday_bridge_traces_mcp_selftest.py \
   "$HERE"/oneday_bridge_gd1b_selftest.py \
   "$HERE"/oneday_bridge_gd23_selftest.py \
   "$HERE"/oneday_bridge_goalsingle_selftest.py \
   "$HERE"/oneday_bridge_id2_selftest.py \
   "$HERE"/oneday_filelibrary_selftest.py \
   "$HERE"/oneday_bridge_library_selftest.py \
   "$HERE"/oneday_automation_selftest.py "$STAGE"/
cd "$STAGE" || exit 1
DEVICE_BRIDGE_KEY=companion-selftest-key
export DEVICE_BRIDGE_KEY
overall=0
for t in overview_bridge_selftest oneday_bridge_p2_selftest oneday_bridge_p3_selftest oneday_bridge_p4_selftest oneday_bridge_p5_selftest oneday_bridge_p6_selftest oneday_bridge_p7_selftest oneday_bridge_p8_selftest oneday_bridge_p9_selftest oneday_bridge_traces_mcp_selftest oneday_bridge_gd1b_selftest oneday_bridge_gd23_selftest oneday_bridge_goalsingle_selftest oneday_bridge_id2_selftest oneday_automation_selftest; do
  echo "===== $t"
  if python3 "$t.py"; then echo "RESULT $t: OK"; else echo "RESULT $t: FAILED"; overall=1; fi
done
# device selftest runs against a LIVE bridge: start the module copy first
echo "===== device_bridge_selftest"
mkdir -p "$STAGE/device-data"
DATA_DIR="$STAGE/device-data" DEVICE_PORT=8647 \
  python3 device_bridge.py > "$STAGE/device-bridge.log" 2>&1 &
BRIDGE_PID=$!
i=0
while [ $i -lt 30 ]; do
  if python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8647/health', timeout=2)" 2>/dev/null; then break; fi
  i=$((i+1)); sleep 0.5
done
if python3 device_bridge_selftest.py; then echo "RESULT device_bridge_selftest: OK"; else echo "RESULT device_bridge_selftest: FAILED"; overall=1; fi
kill $BRIDGE_PID 2>/dev/null
# write-gate rules selftest boots its own bridge copy (fake hermes
# modules, scratch port) — added with the 0.36.21 approval-card package
echo "===== write_gate_rules_selftest"
if python3 write_gate_rules_selftest.py; then echo "RESULT write_gate_rules_selftest: OK"; else echo "RESULT write_gate_rules_selftest: FAILED"; overall=1; fi
# anchor selftest boots its own bridge copy (fake hermes modules +
# fake state.db) — added with the §128 approval-anchor package
echo "===== write_gate_anchor_selftest"
if python3 write_gate_anchor_selftest.py; then echo "RESULT write_gate_anchor_selftest: OK"; else echo "RESULT write_gate_anchor_selftest: FAILED"; overall=1; fi
# blocked selftest boots its own bridge copy (fake hermes modules) —
# added with companion 1.0.29 (reason / reason_phase / decide-attempts
# trace for never-approvable staged records; B-05 single field 1.0.63)
echo "===== write_gate_blocked_selftest"
if python3 write_gate_blocked_selftest.py; then echo "RESULT write_gate_blocked_selftest: OK"; else echo "RESULT write_gate_blocked_selftest: FAILED"; overall=1; fi
# anchor-ledger selftest boots its own bridge copy (fake hermes
# modules + fake state.db) — added with the §234 C-5 package
# (write-once approval anchors)
echo "===== write_gate_anchor_ledger_selftest"
if python3 write_gate_anchor_ledger_selftest.py; then echo "RESULT write_gate_anchor_ledger_selftest: OK"; else echo "RESULT write_gate_anchor_ledger_selftest: FAILED"; overall=1; fi
# sync selftest boots its own bridge copy on a scratch port
echo "===== device_sync_selftest"
if python3 device_sync_selftest.py; then echo "RESULT device_sync_selftest: OK"; else echo "RESULT device_sync_selftest: FAILED"; overall=1; fi
# spreadsheet selftest boots its own fileproc module copy on a
# scratch port (endpoint moved off the oneday bridge 2026-11-14)
echo "===== fileproc_bridge_spreadsheet_selftest"
if python3 fileproc_bridge_spreadsheet_selftest.py; then echo "RESULT fileproc_bridge_spreadsheet_selftest: OK"; else echo "RESULT fileproc_bridge_spreadsheet_selftest: FAILED"; overall=1; fi
# rendition selftest boots its own fileproc module copy on a scratch port
echo "===== fileproc_bridge_rendition_selftest"
if python3 fileproc_bridge_rendition_selftest.py; then echo "RESULT fileproc_bridge_rendition_selftest: OK"; else echo "RESULT fileproc_bridge_rendition_selftest: FAILED"; overall=1; fi
# delivery selftest boots its own bridge copy on a scratch port
echo "===== oneday_delivery_selftest"
if python3 oneday_delivery_selftest.py; then echo "RESULT oneday_delivery_selftest: OK"; else echo "RESULT oneday_delivery_selftest: FAILED"; overall=1; fi
# sentinel selftest boots its own bridge copy + a fake state.db
echo "===== oneday_delivery_sentinel_selftest"
if python3 oneday_delivery_sentinel_selftest.py; then echo "RESULT oneday_delivery_sentinel_selftest: OK"; else echo "RESULT oneday_delivery_sentinel_selftest: FAILED"; overall=1; fi
# file-library selftest boots its own bridge copy + a scratch
# data root (A-06 aggregated read surface, companion 1.0.66)
echo "===== oneday_filelibrary_selftest"
if python3 oneday_filelibrary_selftest.py; then echo "RESULT oneday_filelibrary_selftest: OK"; else echo "RESULT oneday_filelibrary_selftest: FAILED"; overall=1; fi
# library MCP facade selftest boots its own bridge copy + a
# scratch file-library root (agent-side read door, 1.0.73)
echo "===== oneday_bridge_library_selftest"
if python3 oneday_bridge_library_selftest.py; then echo "RESULT oneday_bridge_library_selftest: OK"; else echo "RESULT oneday_bridge_library_selftest: FAILED"; overall=1; fi
# channels selftest boots its own bridge copy (temp HERMES_HOME +
# stub Telegram API) — added with the channels phase-1 package
echo "===== channels_bridge_selftest"
if python3 channels_bridge_selftest.py; then echo "RESULT channels_bridge_selftest: OK"; else echo "RESULT channels_bridge_selftest: FAILED"; overall=1; fi
# ledger selftest runs from the repo tree (its Part C boots the real
# front/ for the panel proxy), booting scratch bridges on scratch ports
echo "===== ledger_selftest"
if python3 "$HERE/ledger_selftest.py"; then echo "RESULT ledger_selftest: OK"; else echo "RESULT ledger_selftest: FAILED"; overall=1; fi
rm -rf "$STAGE"
exit $overall
