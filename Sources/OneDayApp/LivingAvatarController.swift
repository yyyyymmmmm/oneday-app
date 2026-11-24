import Foundation
import OneDayCore

/// 活头像控制器（§479）：App 侧唯一持有者——Core
/// 状态机＋片段目录＋当前头像绑定，三者合成呈现裁
/// 决。喂食点只有 ChatView.followRunEvents 的同位
/// 转译（与 liveActivityPhrase 同源同点），本类不
/// 开任何网络/事件通道。时间驱动的变化（完成回
/// 落、错态过期、入睡）靠状态机给的下一个变化点
/// 精确唤醒，不轮询。
@MainActor
final class LivingAvatarController: ObservableObject {
    @Published private(set) var state: LivingAvatarState = .idle

    private var machine: LivingAvatarStateMachine
    private var wakeTask: Task<Void, Never>?
    let catalog: LivingAvatarCatalog?

    /// 当前头像条目 id 的读口（AppState 接
    /// AgentProfileStore.avatarCache）：绑定裁决
    /// 每次呈现时现读，不缓存第二份真值
    var avatarItemIDProvider: () -> String? = { nil }

    init() {
        machine = LivingAvatarStateMachine(startedAt: Date())
        catalog = LivingAvatarBundle.loadCatalog()
        refresh()
    }

    /// 喂一个语义事件（runs 事件流转译，见
    /// ChatView 接线对照）
    func note(_ event: LivingAvatarEvent) {
        machine.handle(event, at: Date())
        refresh()
    }

    /// 重算当前状态并排下一个时间唤醒点
    func refresh() {
        let now = Date()
        let resolved = machine.state(at: now)
        if resolved != state { state = resolved }
        wakeTask?.cancel()
        wakeTask = nil
        guard let next = machine.nextTransitionDate(after: now)
        else { return }
        let delay = max(0.05, next.timeIntervalSince(now))
        wakeTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(delay * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// 睡眠阈值（规格默认 30 分钟，§479.4）：注册
    /// 表键后续接，本期经此口调；画廊/测试亦走此
    /// 口、不另开后门。
    var sleepThreshold: TimeInterval {
        get { machine.sleepThreshold }
        set {
            machine.sleepThreshold = newValue
            refresh()
        }
    }

    /// 呈现裁决：状态×明暗×当前绑定（目录缺失时
    /// 全静态，与无此功能时形态一致）
    func resolution(
        appearance: LivingAppearance
    ) -> LivingClipResolution {
        guard let catalog else {
            return .staticImage(.catalogMissing)
        }
        return catalog.resolve(
            state: state, appearance: appearance,
            currentAvatarItemID: avatarItemIDProvider()
        )
    }

    func clipURL(_ fileName: String) -> URL? {
        LivingAvatarBundle.clipURL(fileName)
    }
}

/// 内置片段资源的包内定位（§479.3：一期片段随
/// App 内置；资源可能落 LivingAvatar 子目录或包
/// 根，两处都探、取先命中者）
enum LivingAvatarBundle {
    static func loadCatalog() -> LivingAvatarCatalog? {
        guard let url = resourceURL(
            name: "living-avatar-manifest", ext: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return LivingAvatarCatalog(manifestData: data)
    }

    static func clipURL(_ fileName: String) -> URL? {
        let name = (fileName as NSString)
            .deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        guard !name.isEmpty, !ext.isEmpty else { return nil }
        return resourceURL(name: name, ext: ext)
    }

    private static func resourceURL(
        name: String, ext: String
    ) -> URL? {
        Bundle.main.url(
            forResource: name, withExtension: ext,
            subdirectory: "LivingAvatar"
        ) ?? Bundle.main.url(
            forResource: name, withExtension: ext
        )
    }
}
