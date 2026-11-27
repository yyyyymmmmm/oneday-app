#!/bin/bash
# 账号持久化构建验证脚本
set -e

export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

BRANCH="feat/login-account-persist"
WORKTREE_PATH=~/build/oneday-auth2-check
DERIVED_PATH=~/build/auth2-derived

echo "=== 检查通道空闲 ==="
BUILD_COUNT=$(ps aux | grep -E "xcodebuild|tuist" | grep -v grep | wc -l | tr -d ' ')
if [ "$BUILD_COUNT" -gt 0 ]; then
    echo "通道忙（$BUILD_COUNT 个进程），等待 30 秒..."
    sleep 30
    BUILD_COUNT=$(ps aux | grep -E "xcodebuild|tuist" | grep -v grep | wc -l | tr -d ' ')
    if [ "$BUILD_COUNT" -gt 0 ]; then
        echo "仍有 $BUILD_COUNT 个构建进程，退出等待下次"
        exit 1
    fi
fi

echo "=== 清理旧 worktree ==="
if [ -d "$WORKTREE_PATH" ]; then
    cd "$WORKTREE_PATH" && git worktree remove --force . 2>/dev/null || true
    rm -rf "$WORKTREE_PATH"
fi

echo "=== 创建新 worktree ==="
cd ~/workspace/oneday-ios-client-professional-redesign
git worktree add "$WORKTREE_PATH" "$BRANCH"

echo "=== tuist generate ==="
cd "$WORKTREE_PATH"
tuist generate --no-open

echo "=== xcodebuild 构建 ==="
xcodebuild build \
    -workspace OneDayApp.xcworkspace \
    -scheme OneDayApp \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_PATH" \
    CODE_SIGNING_ALLOWED=NO

echo "=== 构建成功 ==="
