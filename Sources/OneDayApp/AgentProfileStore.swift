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
        // 身份反映修复：覆盖来源记录与最近已知服务
        // 器身份名（对账用，裁决在 Core）
        static let nameOverrideProvenance =
            "agentProfile.displayNameOverrideProvenance"
        static let lastKnownSoulName = "agentProfile.lastKnownSoulName"
        static let avatarPresetID = "agentProfile.avatarPresetID"
        static let usesCustomAvatar = "agentProfile.usesCustomAvatar"
        // P1 身份包：AI 档槽位（仓条目 id/预置 id）
        static let aiAvatarItemID = "agentProfile.aiAvatarItemID"
        static let aiAvatarPresetID = "agentProfile.aiAvatarPresetID"
        // 末写胜（2026-11-13）：AI 档写入时刻（服务器
        // 收到写入的时刻，epoch 秒）与用户选择时刻、
        // 服务器名写入时刻——裁决只认这三份时刻，
        // §203 的 userAvatarLocked 锁键自此退役（init
        // 迁移时删除）
        static let aiAvatarUpdatedAt = "agentProfile.aiAvatarUpdatedAt"
        static let avatarSelectedAt = "agentProfile.avatarSelectedAt"
        static let lastKnownSoulUpdatedAt =
            "agentProfile.lastKnownSoulUpdatedAt"
        static let legacyUserAvatarLocked =
            "agentProfile.userAvatarLocked"
    }

    private(set) var profile: AgentProfile

    /// 改名覆盖的来源记录（身份反映修复）：新写入
    /// 的覆盖必带；存量裸覆盖为 nil——对账时按无来
    /// 源处理（不得压住服务器现行名）
    private(set) var nameOverrideProvenance:
        AgentNameOverrideProvenance?

    /// 最近一次解析到的服务器身份名：编辑器写入覆
    /// 盖时用作来源里的「当时服务器名」，落盘保住冷
    /// 启后首解析前的写入也有对账基准
    private(set) var lastKnownSoulName: String?

    /// 服务器名的写入时刻（桥报 updatedAt，服务器收
    /// 到写入的时刻）：名字末写胜裁决的服务器侧凭据；
    /// 桥不可达/旧桥无账时为 nil，裁决退回来源对账
    /// 近似（Core AgentNameLWW）
    private(set) var lastKnownSoulUpdatedAt: Date?

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

    /// 用户最近一次在本机选择头像的时刻（末写胜凭
    /// 据，与 AI 档 updatedAt 比时间定胜负）：从未在
    /// 编辑器里选过为 nil——缺省档案无时刻、挡不住
    /// AI 档。存量迁移：新键缺失而旧选择键在（预置
    /// id 键存在过或用过自定义图）＝升级前手动选过，
    /// 以首次运行新版的时刻落账——升级瞬间保持现状
    /// 不突变，此后任一侧新写入按时间竞争
    private(set) var avatarSelectedAt: Date?

    init() {
        let defaults = UserDefaults.standard
        let name = defaults.string(forKey: Keys.nameOverride)
        let loadedProvenance: AgentNameOverrideProvenance?
        if let data = defaults.data(forKey: Keys.nameOverrideProvenance) {
            loadedProvenance = try? JSONDecoder().decode(
                AgentNameOverrideProvenance.self, from: data
            )
        } else {
            loadedProvenance = nil
        }
        nameOverrideProvenance = loadedProvenance
        lastKnownSoulName = defaults.string(
            forKey: Keys.lastKnownSoulName
        )
        lastKnownSoulUpdatedAt = defaults.object(
            forKey: Keys.lastKnownSoulUpdatedAt
        ) != nil
            ? Date(timeIntervalSince1970: defaults.double(
                forKey: Keys.lastKnownSoulUpdatedAt))
            : nil
        let usesCustom = defaults.bool(forKey: Keys.usesCustomAvatar)
        let presetID = defaults.string(forKey: Keys.avatarPresetID)
            ?? AgentAvatarPreset.defaultID
        // 末写胜迁移：§203 锁键自此退役（删除）；升级
        // 前手动选过（选择键在）又没有时刻账的，以首
        // 次运行新版的时刻落账——升级瞬间保持现状不
        // 突变，此后任一侧新写入按时间竞争
        defaults.removeObject(forKey: Keys.legacyUserAvatarLocked)
        let selectedAt: Date?
        if defaults.object(forKey: Keys.avatarSelectedAt) != nil {
            selectedAt = Date(timeIntervalSince1970: defaults.double(
                forKey: Keys.avatarSelectedAt))
        } else if defaults.object(forKey: Keys.avatarPresetID) != nil
                    || usesCustom {
            let now = Date()
            defaults.set(
                now.timeIntervalSince1970, forKey: Keys.avatarSelectedAt
            )
            selectedAt = now
        } else {
            selectedAt = nil
        }
        // AI 档时刻缺失（升级前槽位）：按最早处理——
        // 下一次头像仓同步就会以桥报的真时刻刷新
        let aiAt: Date = defaults.object(
            forKey: Keys.aiAvatarUpdatedAt
        ) != nil
            ? Date(timeIntervalSince1970: defaults.double(
                forKey: Keys.aiAvatarUpdatedAt))
            : .distantPast
        let loadedAI: AgentAIAvatar?
        let loadedAICustom: UIImage?
        if let itemID = defaults.string(forKey: Keys.aiAvatarItemID) {
            if let aiPreset = defaults.string(forKey: Keys.aiAvatarPresetID) {
                loadedAI = .preset(id: aiPreset, updatedAt: aiAt)
                loadedAICustom = nil
            } else {
                loadedAI = .image(itemID: itemID, updatedAt: aiAt)
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
        avatarSelectedAt = selectedAt
        avatarUIImage = Self.resolveAvatar(
            profile: loadedProfile, customAvatar: loadedCustom,
            aiAvatar: loadedAI, aiCustomAvatar: loadedAICustom,
            userSelectedAt: selectedAt
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
    /// （空白清覆盖由编辑面先行分类后以 nil 调用）。
    /// 写入同时落来源记录（时刻＋当时服务器名），无
    /// 来源的覆盖自此不再产生（身份反映修复）
    func setDisplayNameOverride(_ raw: String?) {
        let defaults = UserDefaults.standard
        guard let raw else {
            profile.displayNameOverride = nil
            nameOverrideProvenance = nil
            defaults.removeObject(forKey: Keys.nameOverride)
            defaults.removeObject(
                forKey: Keys.nameOverrideProvenance
            )
            revision += 1
            return
        }
        guard let clean = AgentDisplayName.sanitizedOverride(raw) else {
            return
        }
        profile.displayNameOverride = clean
        defaults.set(clean, forKey: Keys.nameOverride)
        let provenance = AgentNameOverrideProvenance(
            writtenAt: Date(), soulNameAtWrite: lastKnownSoulName
        )
        nameOverrideProvenance = provenance
        if let data = try? JSONEncoder().encode(provenance) {
            defaults.set(data, forKey: Keys.nameOverrideProvenance)
        }
        revision += 1
    }

    /// 记下最新解析到的服务器身份名（AppState 每次
    /// 解析/重解析/刷新成功后调用）：既是后续写入覆
    /// 盖的对账基准，也供对账裁决取现行名。updatedAt
    /// 是桥报的服务器写入时刻（取不到传 nil，本次不
    /// 更新已存时刻——旧时刻总比编一个强）
    func noteSoulName(_ name: String, updatedAt: Date? = nil) {
        if let updatedAt, updatedAt != lastKnownSoulUpdatedAt {
            lastKnownSoulUpdatedAt = updatedAt
            UserDefaults.standard.set(
                updatedAt.timeIntervalSince1970,
                forKey: Keys.lastKnownSoulUpdatedAt
            )
        }
        guard lastKnownSoulName != name else { return }
        lastKnownSoulName = name
        UserDefaults.standard.set(name, forKey: Keys.lastKnownSoulName)
    }

    /// 覆盖对账（末写胜）：服务器身份名每次确认后调
    /// 用——裁决（Core AgentNameLWW）说清就真清（覆
    /// 盖与来源一并删），各露脸面随档案修订号自然跟
    /// 上现行名。回 true＝本次清掉了一个覆盖
    @discardableResult
    func reconcileNameOverride(currentSoulName: String) -> Bool {
        guard AgentNameLWW.shouldClearOverride(
            override: profile.displayNameOverride,
            provenance: nameOverrideProvenance,
            soulName: currentSoulName,
            soulUpdatedAt: lastKnownSoulUpdatedAt
        ) else { return false }
        profile.displayNameOverride = nil
        nameOverrideProvenance = nil
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.nameOverride)
        defaults.removeObject(forKey: Keys.nameOverrideProvenance)
        revision += 1
        return true
    }

    /// 选预置形象：目录外 id 经 Core 收敛到缺省款。
    /// 选择即落时刻账（末写胜）：这次选择与 AI 档按
    /// 写入时间竞争，不再有「手动即永久锁」一说
    func selectPreset(id: String) {
        let preset = AgentAvatarPreset.resolve(id: id)
        profile.avatar = .preset(id: preset.id)
        UserDefaults.standard.set(preset.id, forKey: Keys.avatarPresetID)
        UserDefaults.standard.set(false, forKey: Keys.usesCustomAvatar)
        stampAvatarSelection()
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
        stampAvatarSelection()
        refreshAvatar()
        revision += 1
        return true
    }

    /// 用户选择落时刻账：末写胜的用户侧凭据（取代
    /// §203 的 lockUserAvatar 上锁——锁已退役）
    private func stampAvatarSelection() {
        let now = Date()
        avatarSelectedAt = now
        UserDefaults.standard.set(
            now.timeIntervalSince1970, forKey: Keys.avatarSelectedAt
        )
    }

    // MARK: - AI 档（头像仓同步，P1）

    /// 仓当前条目是预置引用：只记 id 与写入时刻，图
    /// 由本机目录解析
    func applyAIAvatarPreset(id: String, itemID: String, updatedAt: Date) {
        let resolved = AgentAvatarPreset.resolve(id: id)
        aiAvatar = .preset(id: resolved.id, updatedAt: updatedAt)
        UserDefaults.standard.set(itemID, forKey: Keys.aiAvatarItemID)
        UserDefaults.standard.set(resolved.id, forKey: Keys.aiAvatarPresetID)
        UserDefaults.standard.set(
            updatedAt.timeIntervalSince1970, forKey: Keys.aiAvatarUpdatedAt
        )
        refreshAvatar()
        revision += 1
    }

    /// 仓当前条目是图片：制备口径与用户自定义图一致
    /// （裁方/512/JPEG），落 avatar-ai.jpg 与用户图分
    /// 文件；失败回 false、AI 档保持原样
    @discardableResult
    func applyAIAvatarImage(
        data: Data, itemID: String, updatedAt: Date
    ) -> Bool {
        guard let prepared = Self.preparedCustomAvatar(from: data),
              let jpeg = prepared.jpegData(compressionQuality: 0.85)
        else { return false }
        do {
            try jpeg.write(to: Self.aiAvatarFileURL, options: .atomic)
        } catch {
            return false
        }
        aiCustomAvatar = prepared
        aiAvatar = .image(itemID: itemID, updatedAt: updatedAt)
        UserDefaults.standard.set(itemID, forKey: Keys.aiAvatarItemID)
        UserDefaults.standard.removeObject(forKey: Keys.aiAvatarPresetID)
        UserDefaults.standard.set(
            updatedAt.timeIntervalSince1970, forKey: Keys.aiAvatarUpdatedAt
        )
        refreshAvatar()
        revision += 1
        return true
    }

    /// 同一条目被再次设为当前（仓侧 select 重设指
    /// 针）：字节与 id 都没变、只有写入时刻变——只刷
    /// 槽位时刻，不重下载、不重制备。条目对不上直接
    /// 忽略（同步层下一拍会走全量应用路）
    func refreshAIAvatarTimestamp(itemID: String, updatedAt: Date) {
        guard case .image(let id, let at) = aiAvatar,
              id == itemID, at != updatedAt
        else { return }
        aiAvatar = .image(itemID: itemID, updatedAt: updatedAt)
        UserDefaults.standard.set(
            updatedAt.timeIntervalSince1970, forKey: Keys.aiAvatarUpdatedAt
        )
        refreshAvatar()
        revision += 1
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
        UserDefaults.standard.removeObject(forKey: Keys.aiAvatarUpdatedAt)
        refreshAvatar()
        revision += 1
    }

    private func refreshAvatar() {
        avatarUIImage = Self.resolveAvatar(
            profile: profile, customAvatar: customAvatar,
            aiAvatar: aiAvatar, aiCustomAvatar: aiCustomAvatar,
            userSelectedAt: avatarSelectedAt
        )
    }

    // MARK: - 头像解析

    /// 解析顺序（末写胜裁决在 Core AgentAvatarChoice）：
    /// AI 档与用户选择比写入时刻，后写者胜；AI 图胜
    /// 出且本机图在 → AI 图；任一图缺失回落缺省预置，
    /// 不空白
    private static func resolveAvatar(
        profile: AgentProfile, customAvatar: UIImage?,
        aiAvatar: AgentAIAvatar?, aiCustomAvatar: UIImage?,
        userSelectedAt: Date?
    ) -> UIImage {
        if AgentAvatarChoice.aiImageWins(
            ai: aiAvatar, userSelectedAt: userSelectedAt
        ), let aiCustomAvatar {
            return aiCustomAvatar
        }
        let choice = AgentAvatarChoice.resolve(
            ai: aiAvatar, user: profile.avatar,
            userSelectedAt: userSelectedAt
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
                symbolName: symbolName, tint: presetTint(id: preset.id),
                diameter: 240
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
    /// §224 起统一系统冷中性填充（secondarySystem-
    /// Fill）——旧 pastel 三色（tintSky/tintLavender/
    /// tintGreen）是自调点缀色、与页面底色不匹配，
    /// 用户 2026-11-14 点名「不舒服、不匹配」，自此
    /// 退役；盘色不再按预置分色，全目录同盘。编辑器
    /// 预览与离屏渲染共用此口。
    static func presetTint(id: String) -> Color {
        Palette.fillSecondary
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
    /// 呈现是分享名片 132pt（§224 审计），512 足够
    /// @3x 富余
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

/// 符号预置盘：系统冷中性填充底＋墨色 glyph（§224）。
/// 供存储层离屏渲染与编辑器预览共用。字形占盘比
/// glyphRatio＝字形字号/盘直径：旧值 100/240≈0.42
/// 让小字形浮在大色盘中央（用户 2026-11-14 点名
/// 「不对劲」），改 0.65 对齐大厂占位口径（Muse 身
/// 份段 emoji 实测约 0.65、苹果通讯录占位同量级）。
struct AgentAvatarPresetDisc: View {
    let symbolName: String
    let tint: Color
    /// 盘直径（pt）：字形字号按此乘 glyphRatio 推导，
    /// 调用方须与实际渲染帧边长同值（离屏渲染 240、
    /// 编辑器预览走列表行档）
    let diameter: CGFloat

    /// 字形占盘直径比（§224 定版）
    static let glyphRatio: CGFloat = 0.65

    var body: some View {
        ZStack {
            Circle().fill(tint)
            Image(systemName: symbolName)
                .font(.system(
                    size: diameter * Self.glyphRatio,
                    weight: .regular
                ))
                .foregroundStyle(Palette.ink)
        }
    }
}
