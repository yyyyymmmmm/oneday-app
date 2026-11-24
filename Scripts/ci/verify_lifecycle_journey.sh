#!/usr/bin/env bash
set -euo pipefail

echo "=== OneDay 生命周期旅程验收门（第五批 #8） ==="
echo "1. 检查工程配置与版本号一致性..."
grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION|CFBundleShortVersionString|CFBundleVersion" Project.swift

echo "2. 检查 SwiftData 模型是否包含破坏性迁移风险..."
grep -rn "@Model" Sources/OneDayApp/ Sources/OneDayCore/ || true

echo "3. 检查符号动效登记门..."
python3 Scripts/ci/check_symbol_motion.py

echo "4. 生命周期五大场景人工/真机核验清单："
echo "  [ ] 首次安装：冷启引导、连接服务器、默认主线创建"
echo "  [ ] 覆盖升级：保留历史会话、草稿、文件缓存与登录态"
echo "  [ ] 卸载重装：凭据清理、重新登录拉回服务端历史会话"
echo "  [ ] 换机恢复：新设备登录同一服务器、主线/旁聊/点子/目标/资源库完整回读"
echo "  [ ] 断网/杀进程恢复：发件箱自动续发、进行中 run 对账落定、不丢不重"
echo "=== 生命周期旅程静态门检查通过 ==="
