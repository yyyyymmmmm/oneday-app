// P3 架构治理：已退役（全仓零调用点）。
// 原 ScrollViewTapDismissInstaller / TapDismissInstallerView 通过遍历私有 HostingScrollView
// 层级挂载 UITapGestureRecognizer 收起键盘；在迁移至原生 ChatNativeListView（onBlankTap）
// 与原生 .scrollDismissesKeyboard(.interactively) 后已无任何调用方，本文件清空保留占位以兼容 project.pbxproj。
