import AVFoundation
import OneDayCore
import SwiftUI

/// 活头像呈现面（§479.6）：当前状态有片段且环境
/// 允许动 → 原生 AVPlayer 播放面；其余一切情形
/// （减少动态效果、片段缺失/损坏、绑定不符、目录
/// 缺失）→ 静态头像图，与无此功能时形态逐字一
/// 致。圆裁剪与尺寸由宿主（HubAvatarButton）沿
/// 用，本件只管盘内内容。播放节制：离屏即停、
/// 回屏续播；片段全程静音。
struct LivingAvatarView: View {
    @ObservedObject var controller: LivingAvatarController
    var fallback: Image

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State private var isOnScreen = false
    /// 解码/加载失败过的片段名：本会话内不再重试
    /// 该段、直落静态（规格 §8：损坏回落静态）
    @State private var failedClip: String?

    var body: some View {
        content
            .onAppear {
                isOnScreen = true
                // 出现即重算状态并重排时间唤醒点：
                // 离屏/退后台期间唤醒 Task 可能被挂
                // 起，回来先对一次表。片段裁决本体
                // 随状态发布与宿主重渲（新绑定带来
                // 新 fallback 输入）重跑，不在此处
                controller.refresh()
            }
            .onDisappear { isOnScreen = false }
    }

    @ViewBuilder
    private var content: some View {
        if !reduceMotion,
           case .clip(let fileName, let transient) =
               resolution,
           failedClip != fileName,
           let url = controller.clipURL(fileName) {
            LivingAvatarPlayerSurface(
                url: url, loops: !transient,
                isPlaying: isOnScreen,
                onFailure: { failedClip = fileName }
            )
        } else {
            fallback
                .resizable()
                .scaledToFill()
        }
    }

    private var resolution: LivingClipResolution {
        controller.resolution(
            appearance: colorScheme == .dark
                ? .dark : .light
        )
    }
}

/// AVPlayer 双层交叉淡化面：新片段首帧就绪才淡
/// 入（0.25s，规格 §4）、旧层淡出后释放；循环段
/// 走 AVPlayerLooper 无缝循环（苹果官方件），瞬
/// 时段单播末帧定格（回落时机归状态机的时间窗、
/// 不归播放器）。同片段同模式不重启，防同态抖动。
private struct LivingAvatarPlayerSurface: UIViewRepresentable {
    var url: URL
    var loops: Bool
    var isPlaying: Bool
    var onFailure: () -> Void

    func makeUIView(
        context: Context
    ) -> LivingAvatarPlayerUIView {
        LivingAvatarPlayerUIView()
    }

    func updateUIView(
        _ view: LivingAvatarPlayerUIView, context: Context
    ) {
        view.onFailure = onFailure
        view.setClip(url: url, loops: loops)
        view.setPlaying(isPlaying)
    }

    static func dismantleUIView(
        _ view: LivingAvatarPlayerUIView, coordinator: ()
    ) {
        view.teardown()
    }
}

private final class LivingAvatarPlayerUIView: UIView {
    var onFailure: (() -> Void)?

    /// 访问全程主线程约束（挂载/KVO 回调均跳回主
    /// 队列后才碰成员），故 @unchecked Sendable：
    /// KVO 闭包跨隔离只传引用、不在后台队列动它。
    private final class Slot: @unchecked Sendable {
        let url: URL
        let loops: Bool
        let player: AVPlayer
        let layer: AVPlayerLayer
        var looper: AVPlayerLooper?
        var readyObservation: NSKeyValueObservation?
        var statusObservation: NSKeyValueObservation?

        init(url: URL, loops: Bool) {
            self.url = url
            self.loops = loops
            let item = AVPlayerItem(url: url)
            if loops {
                let queue = AVQueuePlayer()
                queue.isMuted = true
                player = queue
                layer = AVPlayerLayer(player: queue)
                looper = AVPlayerLooper(
                    player: queue, templateItem: item
                )
            } else {
                let single = AVPlayer(playerItem: item)
                single.isMuted = true
                single.actionAtItemEnd = .pause
                player = single
                layer = AVPlayerLayer(player: single)
            }
            layer.videoGravity = .resizeAspectFill
            layer.opacity = 0
        }

        func dispose() {
            readyObservation?.invalidate()
            statusObservation?.invalidate()
            player.pause()
            looper?.disableLooping()
            layer.removeFromSuperlayer()
        }
    }

    private var current: Slot?
    private var incoming: Slot?
    private var playing = false

    override func layoutSubviews() {
        super.layoutSubviews()
        current?.layer.frame = bounds
        incoming?.layer.frame = bounds
    }

    func setPlaying(_ value: Bool) {
        playing = value
        if value {
            current?.player.play()
            incoming?.player.play()
        } else {
            current?.player.pause()
            incoming?.player.pause()
        }
    }

    func setClip(url: URL, loops: Bool) {
        if let current, current.url == url,
           current.loops == loops, incoming == nil {
            return
        }
        if let incoming, incoming.url == url,
           incoming.loops == loops {
            return
        }
        // 换段未半途又改主意：旧的半成品直接弃
        incoming?.dispose()
        incoming = nil

        let slot = Slot(url: url, loops: loops)
        slot.layer.frame = bounds
        layer.addSublayer(slot.layer)
        incoming = slot
        if playing { slot.player.play() }

        slot.statusObservation = slot.player.currentItem?
            .observe(\.status, options: [.new]) {
                [weak self, weak slot] item, _ in
                guard item.status == .failed else { return }
                DispatchQueue.main.async {
                    guard let self, let slot,
                          self.incoming === slot
                    else { return }
                    self.incoming = nil
                    slot.dispose()
                    self.onFailure?()
                }
            }
        slot.readyObservation = slot.layer.observe(
            \.isReadyForDisplay, options: [.new, .initial]
        ) { [weak self, weak slot] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                guard let self, let slot,
                      self.incoming === slot
                else { return }
                self.crossfade(to: slot)
            }
        }
    }

    private func crossfade(to slot: Slot) {
        let old = current
        current = slot
        incoming = nil
        UIView.animate(withDuration: 0.25) {
            slot.layer.opacity = 1
            old?.layer.opacity = 0
        } completion: { _ in
            if self.current === slot {
                old?.dispose()
            }
        }
    }

    func teardown() {
        current?.dispose()
        incoming?.dispose()
        current = nil
        incoming = nil
    }
}

#if DEBUG
/// 活头像状态画廊（§479 验收，仅 DEBUG）：启动参
/// 数 -livingAvatarGallery 直达；按钮喂真实状态机
/// 事件、呈示走真实播放器/目录/绑定裁决（绑定 id
/// 从目录自读，与生产同一条裁决链），供逐状态实
/// 跑截图。发布包无此面。
struct LivingAvatarGalleryView: View {
    @StateObject private var controller: LivingAvatarController = {
        let controller = LivingAvatarController()
        // 绑定在创建期就装好：首帧裁决必须已经看
        // 得见绑定 id（onAppear 装配晚于首帧、首
        // 帧会误落静态兜底，首跑实证）
        let bound = controller.catalog?.boundAvatarID
        controller.avatarItemIDProvider = { bound }
        return controller
    }()
    @State private var dark = false

    var body: some View {
        VStack(spacing: 20) {
            LivingAvatarView(
                controller: controller,
                fallback: Image(systemName: "pawprint.fill")
            )
            .frame(width: 180, height: 180)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(.gray.opacity(0.4))
            }
            Text(stateLabel)
                .font(.headline)
                .accessibilityIdentifier("gallery.state")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 76))],
                spacing: 10
            ) {
                driveButton("空闲") {
                    controller.sleepThreshold = 1800
                    controller.note(.streamLost)
                }
                driveButton("思考") {
                    controller.note(.runStarted)
                }
                driveButton("干活写") {
                    controller.note(.runStarted)
                    controller.note(.toolStarted(.write))
                }
                driveButton("干活通用") {
                    controller.note(.runStarted)
                    controller.note(.toolStarted(.general))
                }
                driveButton("说话") {
                    controller.note(.runStarted)
                    controller.note(.textDelta)
                }
                driveButton("完成") {
                    controller.note(.terminalCompleted)
                }
                driveButton("卡住") {
                    controller.note(.terminalFailed)
                }
                driveButton("睡着") {
                    // 先以交互清错态置窗，再把阈值压
                    // 到 1 秒让入睡即刻可达
                    controller.note(.interaction)
                    controller.sleepThreshold = 1
                    controller.note(.streamLost)
                }
                driveButton("醒来") {
                    // 先喂交互（阈值仍为 1、机器仍判
                    // 睡着才进醒来位），再恢复阈值——
                    // 顺序反了机器先按新阈值判回空闲、
                    // 醒来位永不触发（首跑实证）
                    controller.note(.interaction)
                    controller.sleepThreshold = 1800
                }
                driveButton("深色") { dark.toggle() }
            }
            .padding(.horizontal)
        }
        .preferredColorScheme(dark ? .dark : .light)
    }

    private var stateLabel: String {
        switch controller.state {
        case .working(let family):
            return "working-\(family.rawValue)"
        default:
            return controller.state.key
        }
    }

    private func driveButton(
        _ title: String, action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
    }
}
#endif
