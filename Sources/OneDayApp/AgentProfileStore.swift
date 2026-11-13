import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 智能体本地档案存储（0.36.22，枢纽页对齐包）：本
/// 地档案（OneDayCore.AgentProfile）的落盘与头像解
/// 析——AppState 持有、全 App 露脸面经 AppState 读。
///
/// 落盘口径：
/// - 选择值进 UserDefaults（改名覆盖/预置 id/是否自
///   定义头像），与 chatModelID 等既有偏好同层。
/// - 自定义头像图本体进 Application Support/Agent-
///   Profile/avatar.jpg（512 边长 JPEG）——图数据不
///   进 UserDefaults、不进 Keychain（不是凭据）。
/// - 头像解析结果（UIImage）内存缓存，变更即刷新；
///   符号预置盘以 ImageRenderer 离屏渲染成图，与资
///   产图/自定义图统一成一条「当前头像图」出口，各
///   露脸面只消费这张图、不各自判档案。
@MainActor
@Observable
final class AgentProfileStore {
    private enum Keys {
        static let nameOverride = "agentProfile.displayNameOverride"
        static let avatarPresetID = "agentProfile.avatarPresetID"
        static let usesCustomAvatar = "agentProfile.usesCustomAvatar"
        // P1 身份包：AI 档槽位（仓条目 id/预置 id）与
        // 「用户手动选过」锁
        static let aiAvatarItemID = "agentProfile.aiAvatarItemID"
        static let aiAvatarPresetID = "agentProfile.aiAvatarPresetID"
        static let userAvatarLocked = "agentProfile.userAvatarLocked"
    }

    private(set) var profile: AgentProfile

    /// 变更修订号：每次档案变更 +1——分享名片图等派
    /// 生渲染以此为重算键（自定义图同为 .custom 选择
    /// 时，光看选择值看不出图已换）
    private(set) var revision = 0

    /// 当前头像图（解析缓存）：自定义图缺失/损坏时回
    /// 落缺省预置，不让任何露脸面开天窗
    private(set) var avatarUIImage: UIImage

    private var customAvatar: UIImage?

    /// AI 档槽位（P1）：头像仓当前头像在本机的投影；
    /// 只由头像仓同步写入，用户手动选择永不改它
    private(set) var aiAvatar: AgentAIAvatar?

    private var aiCustomAvatar: UIImage?

    /// 用户手动选过头像（P1 锁）：为真时 AI 档永远压
    /// 不过用户选择。存量迁移：锁键从未写过时，以
    /// 「预置 id 键存在过或用过自定义图」判手动选过
    /// （缺省态从不写这两键，未碰过编辑器的用户不锁）
    private(set) var userAvatarLocked: Bool

    init() {
        let defaults = UserDefaults.standard
        let name = defaults.string(forKey: Keys.nameOverride)
        let usesCustom = defaults.bool(forKey: Keys.usesCustomAvatar)
        let presetID = defaults.string(forKey: Keys.avatarPresetID)
            ?? AgentAvatarPreset.defaultID
        let locked: Bool
        if defaults.object(forKey: Keys.userAvatarLocked) != nil {
            locked = defaults.bool(forKey: Keys.userAvatarLocked)
        } else {
            locked = defaults.object(forKey: Keys.avatarPresetID) != nil
                || usesCustom
        }
        let loadedAI: AgentAIAvatar?
        let loadedAICustom: UIImage?
        if let itemID = defaults.string(forKey: Keys.aiAvatarItemID) {
            if let aiPreset = defaults.string(forKey: Keys.aiAvatarPresetID) {
                loadedAI = .preset(id: aiPreset)
                loadedAICustom = nil
            } else {
                loadedAI = .image(itemID: itemID)
                loadedAICustom = Self.loadAICustomAvatarFile()
            }
        } else {
            loadedAI = nil
            loadedAICustom = nil
        }
        // 先算局部量再统一赋值：@Observable 类的
        // init 在全部存储属性就位前不许读 self（CI
        // run 42878183115 实证——条件赋值 customAva-
        // tar 后读 self.profile 会被 definite-init
        // 检查拦下）
        let loadedProfile = AgentProfile(
            displayNameOverride: name,
            avatar: usesCustom
                ? .custom
                : .preset(id: presetID)
        )
        let loadedCustom = usesCustom
            ? Self.loadCustomAvatarFile()
            : nil
        profile = loadedProfile
        customAvatar = loadedCustom
        aiAvatar = loadedAI
        aiCustomAvatar = loadedAICustom
        userAvatarLocked = locked
        avatarUIImage = Self.resolveAvatar(
            profile: loadedProfile, customAvatar: loadedCustom,
            aiAvatar: loadedAI, aiCustomAvatar: loadedAICustom,
            userLocked: locked
        )
    }

    /// 对外头像（SwiftUI 图）：资产图与解析图同形，
    /// 消费面原有的 resizable/frame/clip 修饰链不变
    var avatarImage: Image {
        Image(uiImage: avatarUIImage)
    }

    // MARK: - 变更

    /// 改名：传 nil＝清覆盖、恢复跟随自动解析链；非
    /// 空入参净化不过（纯空白/超长）拒收、档案不动
    /// （空白清覆盖由编辑面先行分类后以 nil 调用）
    func setDisplayNameOverride(_ raw: String?) {
        guard let raw else {
            profile.displayNameOverride = nil
            UserDefaults.standard.removeObject(forKey: Keys.nameOverride)
            revision += 1
            return
        }
        guard let clean = AgentDisplayName.sanitizedOverride(raw) else {
            return
        }
        profile.displayNameOverride = clean
        UserDefaults.standard.set(clean, forKey: Keys.nameOverride)
        revision += 1
    }

    /// 选预置形象：目录外 id 经 Core 收敛到缺省款。
    /// 手动选择即上锁（P1）：此后 AI 档不再压过它
    func selectPreset(id: String) {
        let preset = AgentAvatarPreset.resolve(id: id)
        profile.avatar = .preset(id: preset.id)
        UserDefaults.standard.set(preset.id, forKey: Keys.avatarPresetID)
        UserDefaults.standard.set(false, forKey: Keys.usesCustomAvatar)
        lockUserAvatar()
        refreshAvatar()
        revision += 1
    }

    /// 设相册自定义头像：解码→居中裁方→压到 512→落
    /// 文件；任一步失败回 false、档案保持原样（调用
    /// 方据此如实报错，不假装换成）
    func setCustomAvatar(data: Data) -> Bool {
        guard let prepared = Self.preparedCustomAvatar(from: data),
              let jpeg = prepared.jpegData(compressionQuality: 0.85)
        else { return false }
        do {
            try jpeg.write(to: Self.avatarFileURL, options: .atomic)
        } catch {
            return false
        }
        customAvatar = prepared
        profile.avatar = .custom
        UserDefaults.standard.set(true, forKey: Keys.usesCustomAvatar)
        lockUserAvatar()
        refreshAvatar()
        revision += 1
        return true
    }

    private func lockUserAvatar() {
        userAvatarLocked = true
        UserDefaults.standard.set(true, forKey: Keys.userAvatarLocked)
    }

    // MARK: - AI 档（头像仓同步，P1）

    /// 仓当前条目是预置引用：只记 id，图由本机目录解析
    func applyAIAvatarPreset(id: String, itemID: String) {
        let resolved = AgentAvatarPreset.resolve(id: id)
        aiAvatar = .preset(id: resolved.id)
        UserDefaults.standard.set(itemID, forKey: Keys.aiAvatarItemID)
        UserDefaults.standard.set(resolved.id, forKey: Keys.aiAvatarPresetID)
        refreshAvatar()
        revision += 1
    }

    /// 仓当前条目是图片：制备口径与用户自定义图一致
    /// （裁方/512/JPEG），落 avatar-ai.jpg 与用户图分
    /// 文件；失败回 false、AI 档保持原样
    @discardableResult
    func applyAIAvatarImage(data: Data, itemID: String) -> Bool {
        guard let prepared = Self.preparedCustomAvatar(from: data),
              let jpeg = prepared.jpegData(compressionQuality: 0.85)
        else { return false }
        do {
            try jpeg.write(to: Self.aiAvatarFileURL, options: .atomic)
        } catch {
            return false
        }
        aiCustomAvatar = prepared
        aiAvatar = .image(itemID: itemID)
        UserDefaults.standard.set(itemID, forKey: Keys.aiAvatarItemID)
        UserDefaults.standard.removeObject(forKey: Keys.aiAvatarPresetID)
        refreshAvatar()
        revision += 1
        return true
    }

    /// 仓里没有当前头像（从未设过）：AI 档清槽，呈现
    /// 回落用户选择。注意仓不可达不走这里——同步层失
    /// 败时根本不调用，AI 档保持上次值
    func clearAIAvatar() {
        guard aiAvatar != nil else { return }
        aiAvatar = nil
        aiCustomAvatar = nil
        UserDefaults.standard.removeObject(forKey: Keys.aiAvatarItemID)
        UserDefaults.standard.removeObject(forKey: Keys.aiAvatarPresetID)
        refreshAvatar()
        revision += 1
    }

    private func refreshAvatar() {
        avatarUIImage = Self.resolveAvatar(
            profile: profile, customAvatar: customAvatar,
            aiAvatar: aiAvatar, aiCustomAvatar: aiCustomAvatar,
            userLocked: userAvatarLocked
        )
    }

    // MARK: - 头像解析

    /// 解析顺序（P1 裁决在 Core AgentAvatarChoice）：
    /// 用户锁 → 用户选择；未锁 → AI 档；AI 图胜出且本
    /// 机图在 → AI 图；任一图缺失回落缺省预置，不空白
    private static func resolveAvatar(
        profile: AgentProfile, customAvatar: UIImage?,
        aiAvatar: AgentAIAvatar?, aiCustomAvatar: UIImage?,
        userLocked: Bool
    ) -> UIImage {
        if AgentAvatarChoice.aiImageWins(
            userLocked: userLocked, ai: aiAvatar
        ), let aiCustomAvatar {
            return aiCustomAvatar
        }
        let choice = AgentAvatarChoice.resolve(
            userLocked: userLocked, ai: aiAvatar, user: profile.avatar
        )
        switch choice {
        case .custom:
            if let customAvatar { return customAvatar }
            return presetImage(AgentAvatarPreset.resolve(id: AgentAvatarPreset.defaultID))
        case .preset(let id):
            return presetImage(AgentAvatarPreset.resolve(id: id))
        }
    }

    private static func presetImage(_ preset: AgentAvatarPreset) -> UIImage {
        if let assetName = preset.assetName,
           let image = UIImage(named: assetName) {
            return image
        }
        if let symbolName = preset.symbolName {
            let disc = AgentAvatarPresetDisc(
                symbolName: symbolName, tint: presetTint(id: preset.id)
            )
            let renderer = ImageRenderer(
                content: disc.frame(width: 240, height: 240)
            )
            renderer.scale = 2
            if let image = renderer.uiImage { return image }
        }
        // 资产与渲染双落空的最后兜底：空白图也不崩
        return UIImage()
    }

    /// 符号盘底色（App 层令牌映射，Core 目录只记 id）：
    /// 与活动行图标盒的 pastel 同族；编辑器预览共用
    static func presetTint(id: String) -> Color {
        switch id {
        case "paw": return Palette.tintSky
        case "sparkles": return Palette.tintLavender
        case "atom": return Palette.tintGreen
        default: return Palette.tintSky
        }
    }

    // MARK: - 自定义图文件与制备

    private static var avatarFileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        let dir = base.appendingPathComponent(
            "AgentProfile", isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir.appendingPathComponent("avatar.jpg")
    }

    private static func loadCustomAvatarFile() -> UIImage? {
        guard let data = try? Data(contentsOf: avatarFileURL) else {
            return nil
        }
        return UIImage(data: data)
    }

    /// AI 档图文件：与用户图同目录、分文件（avatar-ai
    /// .jpg），两边互不覆盖
    private static var aiAvatarFileURL: URL {
        avatarFileURL.deletingLastPathComponent()
            .appendingPathComponent("avatar-ai.jpg")
    }

    private static func loadAICustomAvatarFile() -> UIImage? {
        guard let data = try? Data(contentsOf: aiAvatarFileURL) else {
            return nil
        }
        return UIImage(data: data)
    }

    /// 相册图制备：按 UIImage 方向居中裁方（draw 居中
    /// 覆盖），边长超 512 再等比压到 512——头像最大
    /// 呈现 110pt，512 足够 @3x 富余
    private static func preparedCustomAvatar(from data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let side = min(size.width, size.height)
        let square = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side)
        ).image { _ in
            image.draw(in: CGRect(
                x: (side - size.width) / 2,
                y: (side - size.height) / 2,
                width: size.width, height: size.height
            ))
        }
        guard side > 512 else { return square }
        return UIGraphicsImageRenderer(
            size: CGSize(width: 512, height: 512)
        ).image { _ in
            square.draw(in: CGRect(x: 0, y: 0, width: 512, height: 512))
        }
    }
}

/// 符号预置盘：pastel 底＋墨色 glyph（与活动行图标
/// 盒同语言）。供存储层离屏渲染与编辑器预览共用。
struct AgentAvatarPresetDisc: View {
    let symbolName: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle().fill(tint)
            Image(systemName: symbolName)
                .font(.system(size: 100, weight: .regular))
                .foregroundStyle(Palette.ink)
        }
    }
}
