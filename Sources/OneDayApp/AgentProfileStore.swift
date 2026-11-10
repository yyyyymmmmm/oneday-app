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

    init() {
        let defaults = UserDefaults.standard
        let name = defaults.string(forKey: Keys.nameOverride)
        let usesCustom = defaults.bool(forKey: Keys.usesCustomAvatar)
        let presetID = defaults.string(forKey: Keys.avatarPresetID)
            ?? AgentAvatarPreset.defaultID
        profile = AgentProfile(
            displayNameOverride: name,
            avatar: usesCustom
                ? .custom
                : .preset(id: presetID)
        )
        if usesCustom {
            customAvatar = Self.loadCustomAvatarFile()
        }
        avatarUIImage = Self.resolveAvatar(
            profile: profile, customAvatar: customAvatar
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

    /// 选预置形象：目录外 id 经 Core 收敛到缺省款
    func selectPreset(id: String) {
        let preset = AgentAvatarPreset.resolve(id: id)
        profile.avatar = .preset(id: preset.id)
        UserDefaults.standard.set(preset.id, forKey: Keys.avatarPresetID)
        UserDefaults.standard.set(false, forKey: Keys.usesCustomAvatar)
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
        refreshAvatar()
        revision += 1
        return true
    }

    private func refreshAvatar() {
        avatarUIImage = Self.resolveAvatar(
            profile: profile, customAvatar: customAvatar
        )
    }

    // MARK: - 头像解析

    private static func resolveAvatar(
        profile: AgentProfile, customAvatar: UIImage?
    ) -> UIImage {
        switch profile.avatar {
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
