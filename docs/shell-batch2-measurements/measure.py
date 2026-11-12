#!/usr/bin/env python3
"""
症三·浮空距离量测脚本（2026-11-12）

量测自家坞胶囊下缘到屏底的距离，与标准带（34-36pt）对比。

录屏信息：
- 分辨率：720x1566 px
- 机型推断：iPhone 14 Pro / 15 Pro 类（@3x，逻辑分辨率 240x522 pt）
- 换算：1 pt = 3 px

标准 iOS Home Indicator 区域：
- 高度：34pt（@3x = 102px）
- 包含上下安全边距

量测方法：
1. 在录屏帧中标记关键点：
   - 胶囊下缘（视觉边界）
   - 屏幕底部边缘
2. 计算像素差值，换算为 pt
3. 与标准带（34-36pt）对比

裁决：
- ≈34-36pt → 视觉拉伸问题，归症一
- 明显超出 → 容器传播多余安全区，记录候选
"""

import sys

# 录屏规格
VIDEO_WIDTH_PX = 720
VIDEO_HEIGHT_PX = 1566
SCALE_FACTOR = 3  # @3x
VIDEO_WIDTH_PT = VIDEO_WIDTH_PX / SCALE_FACTOR  # 240pt
VIDEO_HEIGHT_PT = VIDEO_HEIGHT_PX / SCALE_FACTOR  # 522pt

# 标准值
STANDARD_HOME_INDICATOR_MIN_PT = 34
STANDARD_HOME_INDICATOR_MAX_PT = 36

print("症三·浮空距离量测")
print("=" * 50)
print(f"录屏分辨率：{VIDEO_WIDTH_PX}×{VIDEO_HEIGHT_PX} px")
print(f"逻辑分辨率：{VIDEO_WIDTH_PT}×{VIDEO_HEIGHT_PT} pt (@3x)")
print(f"标准带：{STANDARD_HOME_INDICATOR_MIN_PT}-{STANDARD_HOME_INDICATOR_MAX_PT} pt")
print()

# 手动量测点（需要在图片上标记后填入）
print("请在 frame-001.png 中测量以下坐标（px）：")
print("1. 胶囊下缘 y 坐标（视觉边界，不含阴影）")
print("2. 屏幕底部 y 坐标（应为 1566）")
print()

# 示例量测（待实际测量后替换）
# 从视觉观察，胶囊通常位于顶部状态栏下方
# 底部坞通常距离屏幕底部 34-40pt
# 但这里要量的是"胶囊下缘到屏底"，如果是顶部胶囊，这个值会很大
#
# 重新理解：简报说的"自家坞胶囊"可能是指底部坞中的胶囊形元素？
# 还是说聊天页顶部的 IdentityCapsuleView？
#
# 根据症状描述"浮空距离"和"坞下缘→屏底"，应该是指：
# 底部某个元素（可能是输入栏或坞栏）的下缘到屏幕底部的距离

print("⚠️  需要明确：")
print("   '自家坞胶囊'指的是：")
print("   A. 顶部 IdentityCapsuleView（聊天页顶栏中央）")
print("   B. 底部输入栏的圆角容器")
print("   C. 底部 TabView 坞栏本体")
print()
print("根据'坞下缘→屏底'描述，推测是 C（底部坞栏）")
print()

# 量测示例（待确认后填入真实值）
if len(sys.argv) >= 3:
    element_bottom_y_px = int(sys.argv[1])
    screen_bottom_y_px = int(sys.argv[2])

    distance_px = screen_bottom_y_px - element_bottom_y_px
    distance_pt = distance_px / SCALE_FACTOR

    print(f"元素下缘：{element_bottom_y_px} px")
    print(f"屏幕底部：{screen_bottom_y_px} px")
    print(f"距离：{distance_px} px = {distance_pt:.1f} pt")
    print()

    if STANDARD_HOME_INDICATOR_MIN_PT <= distance_pt <= STANDARD_HOME_INDICATOR_MAX_PT:
        print(f"✓ 量值在标准带内（{STANDARD_HOME_INDICATOR_MIN_PT}-{STANDARD_HOME_INDICATOR_MAX_PT}pt）")
        print("  → 裁决：视觉拉伸问题，归症一收口")
        print("  → 不动容器")
    else:
        print(f"✗ 量值超出标准带（{distance_pt:.1f} pt）")
        print("  → 裁决：容器传播多余安全区候选")
        print("  → 修复待审计裁决，本轮不动 contentHost")
else:
    print("用法：python measure.py <元素下缘y坐标px> <屏幕底部y坐标px>")
    print("示例：python measure.py 1464 1566")
