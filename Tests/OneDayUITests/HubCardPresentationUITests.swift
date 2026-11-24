import XCTest

/// 【已退役 · 2026-11-25 · 0.51.0 收编轮】
/// 本文件原为 §502 中枢卡片呈现 UI 钉测，共 5 件：
///   - testHubOpensFullscreenAndCloseReturnsFast
///   - testHubFastRightDragDismisses
///   - testHubSlowLongDragDismisses
///   - testHubSlowShortDragSpringsBack
///   - testHubVerticalScrollDoesNotDismiss
/// 退役原因：提交 1860a9d0（用户自改 7 项之第 7 项「中枢改原生 Sheet」）
/// 已把中枢呈现由 fullScreenCover + HubCardHost 交互卡片整体换成
/// iOS 原生大档 Sheet；hub.card 元素已退出全部呈现路径，本套断言的
/// 卡片形态（满屏帧、右滑投影关闭、慢拖弹回、方向锁仲裁）在现行产品
/// 中已不存在，无真行为可测——不许换元素名续命。
/// 行为守门：HubPresentationProbeTests（开页／内容／底栏覆盖／关页回归）。
/// 判读：release-0510-hub-ui-triage-20261125.md（甲案）。
/// 文件保留作退役记录，不删。
