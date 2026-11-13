#!/bin/bash
# 键盘真崩符号化尝试（实验用）：对 .ips 在案五处偏移在 CI runner 的
# 模拟器运行时镜像上尝试 atos 符号化。目标 UUID（自 .ips usedImages）：
#   SwiftData          2449226E-2E13-3AD7-8AE3-5A808ECD2224
#   _SwiftData_SwiftUI D38C54B9-7E0A-372B-84C7-2199F8B45417
# 偏移：SwiftData 502888/569200/645616；
#       _SwiftData_SwiftUI 23828/24356（通知路径）与
#       18164/39656/16992/10620/13052/10788/10520（#3 第二路径）
# 能到哪步算哪步：全部尝试的原始输出都落本脚本 stdout，不许静默。
set +e
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
SD_UUID="2449226E-2E13-3AD7-8AE3-5A808ECD2224"
UI_UUID="D38C54B9-7E0A-372B-84C7-2199F8B45417"
SD_OFFS="502888 569200 645616"
UI_OFFS="23828 24356 18164 39656 16992 10620 13052 10788 10520"

echo "=== env ==="
xcodebuild -version
uname -a
echo "--- simctl runtimes ---"
xcrun simctl list runtimes 2>&1 | head -30
echo "--- atos ---"
xcrun -f atos; which dwarfdump otool nm dyld_shared_cache_util 2>&1

try_atos() {
  # $1=binary $2=uuid $3..=offsets(decimal)
  local bin="$1" uuid="$2"; shift 2
  echo "--- atos on: $bin"
  local got
  got=$(dwarfdump --uuid "$bin" 2>/dev/null | awk '{print $2}')
  echo "    binary UUID: ${got:-<none>}  target: $uuid"
  if [ "$got" != "$uuid" ]; then echo "    UUID MISMATCH — skip"; return; fi
  local off
  for off in "$@"; do
    printf "    off %s (0x%x): " "$off" "$off"
    xcrun atos -arch arm64 -o "$bin" -l 0x100000000 \
      "$(printf '0x%x' $((0x100000000 + off)))" 2>&1 | head -2
  done
}

echo "=== search: standalone framework binaries under CoreSimulator ==="
find /Library/Developer/CoreSimulator /Volumes \
  -name "SwiftData" -path "*SwiftData.framework*" -type f 2>/dev/null | head
find /Library/Developer/CoreSimulator /Volumes \
  -name "_SwiftData_SwiftUI" -path "*_SwiftData_SwiftUI.framework*" -type f \
  2>/dev/null | head

while IFS= read -r bin; do
  [ -n "$bin" ] && try_atos "$bin" "$SD_UUID" $SD_OFFS
done <<EOF
$(find /Library/Developer/CoreSimulator /Volumes -name "SwiftData" -path "*SwiftData.framework*" -type f 2>/dev/null | head -4)
EOF
while IFS= read -r bin; do
  [ -n "$bin" ] && try_atos "$bin" "$UI_UUID" $UI_OFFS
done <<EOF
$(find /Library/Developer/CoreSimulator /Volumes -name "_SwiftData_SwiftUI" -path "*_SwiftData_SwiftUI.framework*" -type f 2>/dev/null | head -4)
EOF

echo "=== search: dyld shared caches ==="
CACHES=$(find /Library/Developer/CoreSimulator /Volumes \
  -name "dyld_shared_cache_arm64*" -type f 2>/dev/null | head -4)
echo "$CACHES"
for cache in $CACHES; do
  echo "--- cache: $cache"
  ls -la "$cache" 2>/dev/null
  echo "    [try] atos directly against cache (SwiftData base 0x1d25c8000 per .ips #4)"
  for off in $SD_OFFS; do
    printf "    SD off %s: " "$off"
    xcrun atos -arch arm64 -o "$cache" -l 0x1d25c8000 \
      "$(printf '0x%x' $((0x1d25c8000 + off)))" 2>&1 | head -2
  done
  DSCU=$(xcrun -f dyld_shared_cache_util 2>/dev/null || which dyld_shared_cache_util 2>/dev/null)
  echo "    dyld_shared_cache_util: ${DSCU:-<absent>}"
  if [ -n "$DSCU" ]; then
    "$DSCU" -list "$cache" 2>&1 | grep -i -E "SwiftData" | head
  fi
done

echo "=== try: dsc_extractor (Xcode bundled) ==="
DSCX=$(find /Applications/Xcode*.app -name "dsc_extractor*" 2>/dev/null | head -2)
echo "${DSCX:-<absent>}"

echo "=== try: symbolicatecrash on collected .ips ==="
SYMC=$(find /Applications/Xcode*.app -name "symbolicatecrash" 2>/dev/null | head -1)
echo "symbolicatecrash: ${SYMC:-<absent>}"
mkdir -p symbolication-out
if [ -n "$SYMC" ]; then
  export DEVELOPER_DIR="$(xcode-select -p)"
  for ips in crash-hunt/DiagnosticReports/*.ips; do
    [ -f "$ips" ] || continue
    base=$(basename "$ips" .ips)
    echo "--- symbolicatecrash $base"
    perl "$SYMC" "$ips" > "symbolication-out/$base.symbolicated.txt" 2>&1
    grep -n -E "SwiftData" "symbolication-out/$base.symbolicated.txt" | head -20
  done
fi

echo "=== collect repro progress markers ==="
mkdir -p repro-progress-collect
n=0
while IFS= read -r f; do
  n=$((n+1))
  cp "$f" "repro-progress-collect/progress-$n.txt" 2>/dev/null
  echo "--- $f"
  cat "$f" 2>/dev/null
done <<EOF
$(find ~/Library/Developer/CoreSimulator/Devices -name "repro-progress.txt" 2>/dev/null | head -6)
EOF
echo "=== symbolicate.sh done ==="
