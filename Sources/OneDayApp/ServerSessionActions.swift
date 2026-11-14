import OneDayCore
import OneDayDesign
import SwiftUI

/// 抽屉行统一的系统长按菜单挂点。修饰整个行的命中
/// 面，而不是只修饰文字或按钮内部某个子视图。
extension View {
    func drawerRowContextMenu<MenuItems: View>(
        @ViewBuilder menuItems: () -> MenuItems
    ) -> some View {
        self
            .contentShape(Rectangle())
            .contextMenu(menuItems: menuItems)
    }
}

/// 服务端会话四件的执行层（0.18.0，旁聊立项档 A.3 /
/// 验收项 A3-V）：改名/置顶/归档/删除全走服务端本
/// 体（PATCH / DELETE），2xx 只算受理——每件都 GET
/// 回读对账才算落定，未落定返回人话原因。§233 分
/// 档：置顶的**呈现层**改乐观（行组件先翻、失败清
/// 覆盖＋弹原因），本执行层口径不变；其余三件维持
/// 确认先行。抽屉名单与「全部对话」管理页共用本层与下
/// 方行组件，不许两处各写一套。
@MainActor
enum ServerSessionActions {
    enum Outcome: Equatable {
        case verified
        case failed(String)
    }

    private static func humanReason(_ error: Error) -> String {
        (error as? HermesError)?.userMessage ?? L10n.string("操作没完成，请稍后再试。")
    }

    /// 改名：PATCH {title} → GET 对账 title 一字不差
    static func rename(
        appState: AppState, id: String, title: String
    ) async -> Outcome {
        do {
            try await appState.performAdmin { client, config in
                try await client.updateServerSession(
                    config: config, id: id,
                    title: title, pinned: nil, archived: nil
                )
            }
            let row = try await appState.performAdmin { client, config in
                try await client.serverSession(config: config, id: id)
            }
            return row.cleanedServerTitle == title
                ? .verified
                : .failed(L10n.string("没改名成：服务器上的标题还是原来的，稍后再试一次。"))
        } catch {
            return .failed(humanReason(error))
        }
    }

    /// 置顶/取消置顶：PATCH {pinned} → GET 对账位值
    static func setPinned(
        appState: AppState, id: String, pinned: Bool
    ) async -> Outcome {
        do {
            try await appState.performAdmin { client, config in
                try await client.updateServerSession(
                    config: config, id: id,
                    title: nil, pinned: pinned, archived: nil
                )
            }
            let row = try await appState.performAdmin { client, config in
                try await client.serverSession(config: config, id: id)
            }
            return row.isPinned == pinned
                ? .verified
                : .failed(L10n.string("没置顶成：服务器上这条还是没置顶的样子，稍后再试一次。"))
        } catch {
            return .failed(humanReason(error))
        }
    }

    /// 归档/恢复：PATCH {archived} → GET 对账位值。
    /// 恢复落定后顺手清存量本地归档键（0.7.0 绕行遗
    /// 留——该键若还在，抽屉会继续按本地口径藏行）；
    /// 归档不再写本地键（服务端 archived=exclude 拉
    /// 取天然不含已归档行）。
    static func setArchived(
        appState: AppState, id: String, archived: Bool
    ) async -> Outcome {
        do {
            try await appState.performAdmin { client, config in
                try await client.updateServerSession(
                    config: config, id: id,
                    title: nil, pinned: nil, archived: archived
                )
            }
            let row = try await appState.performAdmin { client, config in
                try await client.serverSession(config: config, id: id)
            }
            guard row.isArchived == archived else {
                return .failed(L10n.string("没归档成：服务器上这条还是未归档的样子，稍后再试一次。"))
            }
            if !archived {
                appState.sideChats.unarchive(serverSessionID: id)
            }
            return .verified
        } catch {
            return .failed(humanReason(error))
        }
    }

    /// 删除：DELETE → GET 应取不到（报错才算删净）；
    /// 还能读到即未落定。真删不可恢复，二次确认在
    /// 调用方（行组件/管理页批量栏）。§232 起本函
    /// 数是乐观删除的后台执行口（SessionDeletion-
    /// Coordinator 默认执行口）：用户侧时序由协调
    /// 器管（本地先删/失败恢复），本函数的落定判
    /// 定口径不变
    static func delete(
        appState: AppState, id: String
    ) async -> Outcome {
        do {
            try await appState.performAdmin { client, config in
                try await client.deleteServerSession(config: config, id: id)
            }
        } catch let error as HermesError {
            // 404＝服务端本就没这条（他处已删/存量残影）：
            // 不直接判败，落到下方回查定夺——回查读不到
            // 即目标已达成（0.50.30）
            if case .unexpectedStatus(_, let status) = error,
               status == 404 {
                // 落回查裁决
            } else {
                return .failed(humanReason(error))
            }
        } catch {
            return .failed(humanReason(error))
        }
        do {
            _ = try await appState.performAdmin { client, config in
                try await client.serverSession(config: config, id: id)
            }
            return .failed(L10n.string("没删掉：这条会话在服务器上还在，稍后再试一次。"))
        } catch {
            return .verified
        }
    }
}

/// 服务端会话行共用组件（0.18.0，A3-V）：点按打开
/// ＋长按四件菜单——**重命名／置顶／归档／删除**
/// （序钉死，恢复/取消置顶占同位切换文案）。改名走
/// 本组件内 alert、删除走二次确认、进行中禁菜单、
/// 失败弹人话原因；落定后只经 onChanged 请宿主重
/// 拉刷新（以服务端为准），不在本地改行数据冒充。
/// 主线行不使用本组件（钦定保护：无菜单、不可改
/// 名/归档/删除）。
struct ServerSessionRow<Content: View>: View {
    let session: ServerSession
    /// 行标题（宿主按统一管线 resolvedTitle 算好；
    /// 改名预填与删除确认文案用）
    let title: String
    /// 点按（同步）：打开续聊等宿主动作
    var onOpen: () -> Void
    /// 点按（异步）：抽屉归档区「点按恢复」这类带网
    /// 络的点按走这里，结果同样过落定/失败呈现
    var onOpenAsync: (() async -> ServerSessionActions.Outcome)? = nil
    /// 任一动作落定后的宿主刷新（重拉名单）
    var onChanged: () -> Void
    /// 删除请求钩子（§232 乐观删除）：二次确认通
    /// 过后即触发——宿主在此同拍摘自家名单行并经
    /// SessionDeletionCoordinator 起手（本地先删、
    /// 服务端后台删、最终失败自动恢复＋提醒）；本
    /// 组件不再等服务端落定，改名/置顶/归档仍走落
    /// 定口径不经此钩（组版收口：抽屉长按包原接
    /// §223 的 onDeleted 落定收口钩，本树删除时序
    /// 已改乐观——未收养行删除同走本钩，物理收口
    /// 由协调器落定后统一经 DeletedSessionCloseout）
    var onDeleteRequested: ((ServerSession) -> Void)? = nil
    /// 删除菜单项标题：必须走 LocalizedStringKey——普通
    /// String 变量进 Label 是原文直出、永不本地化（CI 英
    /// 文区域快照实证：同菜单其余三项字面量都译成英文、
    /// 唯删除项停在中文）。默认「删除」，抽屉宿主传「删
    /// 除会话」与本地行同名
    var deleteMenuTitle: LocalizedStringKey = "删除"
    @ViewBuilder var content: () -> Content

    @Environment(AppState.self) private var appState
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var showBucketArchiveConfirm = false
    @State private var busy = false
    @State private var errorText: String?
    /// 置顶乐观覆盖（§233）：点按当拍先以此值呈现，
    /// 后台落定后宿主重拉的服务端值与之一致即自然接
    /// 管；失败清覆盖（回到服务端现值）＋弹原因，与
    /// 技能/MCP 开关同构。其余动作不走覆盖
    @State private var pinOverride: Bool?

    /// 0.27.0：本行是否为已判死的合并桶——归档/删
    /// 除前必须过带牵连说明的二次确认（见下）
    private var isMergeBucket: Bool {
        SideChatLink.isMergeBucket(session.id)
    }

    private var isPinned: Bool { pinOverride ?? (session.isPinned == true) }
    private var isArchived: Bool { session.isArchived == true }

    /// 行状态值（0.43.0，A11Y-V6）：置顶/归档以值
    /// 播报（取词走 L10n 与界面同语言）；两态并存
    /// 以「，」拼（读序：置顶先行）、无态为空串
    /// （修饰符对空值不播报）
    private var stateValue: String {
        var parts: [String] = []
        if isPinned { parts.append(L10n.string("已置顶")) }
        if isArchived { parts.append(L10n.string("已归档")) }
        return parts.joined(separator: "，")
    }

    var body: some View {
        Button {
            if let onOpenAsync {
                perform { await onOpenAsync() }
            } else {
                onOpen()
            }
        } label: {
            content()
        }
        .buttonStyle(.odPressable)
        // 0.43.0（A11Y-V6）：置顶/归档态补值播报——
        // 行面只有 pin 字形与段位区分、VO 读不到状
        // 态；值随态拼（两键已在目录），无态不挂空值
        .accessibilityValue(stateValue)
        .drawerRowContextMenu {
            managementActions
            deleteAction
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            deleteAction
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            managementActions
        }
        .alert(
            "重命名会话",
            isPresented: $showRename
        ) {
            TextField("会话标题", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") { commitRename() }
        }
        .confirmationDialog(
            "删除这条会话？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                // §232：确认即乐观起手，不上 busy 锁、
                // 不等服务端（协调器后台收口/恢复）
                onDeleteRequested?(session)
            }
            Button("取消", role: .cancel) {}
        } message: {
            // 0.27.0：合并桶的删除确认必须写明牵连
            // 主线历史（这两条桶的本体不在 App 侧处
            // 置范围，删除决定权在用户、信息给足）
            if isMergeBucket {
                Text(SideChatLink.mergeBucketWarning)
            } else {
                Text("「\(title)」删除后不可恢复。")
            }
        }
        .confirmationDialog(
            "归档这条合并记录？",
            isPresented: $showBucketArchiveConfirm,
            titleVisibility: .visible
        ) {
            Button("归档", role: .destructive) {
                perform {
                    await ServerSessionActions.setArchived(
                        appState: appState, id: session.id,
                        archived: true
                    )
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(SideChatLink.mergeBucketWarning)
        }
        .alert(
            "没改成",
            isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )
        ) {
            Button("好", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    // 长按与滑动共用入口，确认、上锁和服务端回查口径不分叉。
    @ViewBuilder
    private var managementActions: some View {
        Button {
            renameText = title
            showRename = true
        } label: {
            Label("重命名", systemImage: "pencil")
        }
        .disabled(busy)
        Button {
            // §233：置顶是纯排序态——点按当拍先
            // 翻呈现（pinOverride），后台落定走既
            // 有 perform 纪律，失败清覆盖＋弹原因
            let target = !isPinned
            pinOverride = target
            perform(onFailed: { pinOverride = nil }) {
                await ServerSessionActions.setPinned(
                    appState: appState, id: session.id,
                    pinned: target
                )
            }
        } label: {
            Label(
                isPinned ? "取消置顶" : "置顶",
                systemImage: isPinned ? "pin.slash" : "pin"
            )
        }
        .disabled(busy)
        Button {
            // 0.27.0：合并桶的「归档」先过二次确认
            // （恢复方向不拦——它不伤记录）
            if isMergeBucket, !isArchived {
                showBucketArchiveConfirm = true
            } else {
                perform {
                    await ServerSessionActions.setArchived(
                        appState: appState, id: session.id,
                        archived: !isArchived
                    )
                }
            }
        } label: {
            Label(
                isArchived ? "恢复" : "归档",
                systemImage: isArchived
                    ? "arrow.uturn.backward" : "archivebox"
            )
        }
        .disabled(busy)
    }

    private var deleteAction: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label(deleteMenuTitle, systemImage: "trash")
        }
        .disabled(busy)
    }

    private func commitRename() {
        let newTitle = renameText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !newTitle.isEmpty, newTitle != title else { return }
        perform {
            await ServerSessionActions.rename(
                appState: appState, id: session.id, title: newTitle
            )
        }
    }

    /// 动作统一走法：进行中上锁；落定→宿主重拉；未
    /// 落定→弹原因（行数据不动，等重拉对齐服务端）。
    /// onFailed（§233）：乐观覆盖类动作失败时先清覆
    /// 盖恢复呈现，再弹原因
    private func perform(
        onFailed: (() -> Void)? = nil,
        _ action: @escaping () async -> ServerSessionActions.Outcome
    ) {
        guard !busy else { return }
        busy = true
        Task {
            let outcome = await action()
            busy = false
            switch outcome {
            case .verified:
                onChanged()
            case .failed(let reason):
                onFailed?()
                errorText = reason
            }
        }
    }

}
