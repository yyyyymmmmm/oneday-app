import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 智能体身份缓存存储（§245 身份包，复杂化审计 C-2
/// 收敛）：名字与头像的真值只有服务端一份（名字＝
/// SOUL、头像＝伴生头像仓），本店只存带时间戳的缓
/// 存副本——呈现读副本、刷新整份替换副本，不存
/// 「覆盖」语义、不做双账裁决。用户在 App 里改名/
/// 换头像＝写穿服务端（AppState 编排），成功后以服
/// 务端回读刷新副本。
///
/// 落盘口径：
/// - 缓存值（Core IdentityNameCache/IdentityAvatar-
///   Cache）JSON 进 UserDefaults，与既有偏好同层。
/// - 头像图本体进 Application Support/AgentProfile/
///   avatar-cache.jpg（512 边长 JPEG）——图数据不进
///   UserDefaults、不进 Keychain（不是凭据）。
/// - 升级迁移：旧账键组（改名覆盖/来源/双槽头像/
///   时刻账）在 init 里经 Core IdentityLegacyMigra-
///   tion 最后一判播种新缓存后全量删除；本机侧胜出
///   的值置待推标记，首次连通刷新时写穿服务端。
@MainActor
@Observable
final class AgentProfileStore {
    private enum Keys {
        static let nameCache = "identity.nameCache"
        static let avatarCache = "identity.avatarCache"
        static let namePushPending = "identity.namePushPending"
        static let avatarPushPending = "identity.avatarPushPending"
        // 旧账键组（§245 迁移读后即删，勿再写）
        static let legacyNameOverride =
            "agentProfile.displayNameOverride"
        static let legacyNameOverrideProvenance =
            "agentProfile.displayNameOverrideProvenance"
        static let legacyLastKnownSoulName =
            "agentProfile.lastKnownSoulName"
        static let legacyLastKnownSoulUpdatedAt =
            "agentProfile.lastKnownSoulUpdatedAt"
        static let legacyAvatarPresetID =
            "agentProfile.avatarPresetID"
        static let legacyUsesCustomAvatar =
            "agentProfile.usesCustomAvatar"
        static let legacyAIItemID = "agentProfile.aiAvatarItemID"
        static let legacyAIPresetID =
            "agentProfile.aiAvatarPresetID"
        static let legacyAIUpdatedAt =
            "agentProfile.aiAvatarUpdatedAt"
        static let legacyAvatarSelectedAt =
            "agentProfile.avatarSelectedAt"
        static let legacyUserAvatarLocked =
            "agentProfile.userAvatarLocked"
    }

    /// 名字缓存（服务端现行身份名的副本）；从未刷新
    /// 到为 nil，呈现回落 Hermes
    private(set) var nameCache: IdentityNameCache?

    /// 头像缓存（头像仓当前指针的副本）；仓从未设过
    /// 当前头像/从未同步到为 nil，呈现回落缺省预置
    private(set) var avatarCache: IdentityAvatarCache?

    /// 迁移待推：本机旧选择胜出但尚未写穿服务端。
    /// true 时刷新链先推后读（AgentAvatarSync/名字刷
    /// 新），推成功即清；推失败保留缓存原样、不许以
    /// 服务端读数覆盖掉用户胜出值
    private(set) var namePushPending = false
    private(set) var avatarPushPending = false

    /// 变更修订号：每次缓存变更 +1——分享名片图等派
    /// 生渲染以此为重算键
    private(set) var revision = 0

    /// 当前头像图（解析缓存）：缓存图缺失/损坏时回
    /// 落缺省预置，不让任何露脸面开天窗
    private(set) var avatarUIImage: UIImage

    private var cachedAvatarImage: UIImage?

    init() {
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()
        var loadedName: IdentityNameCache?
        var loadedAvatar: IdentityAvatarCache?
        var loadedImage: UIImage?
        var namePush = false
        var avatarPush = false

        if let data = defaults.data(forKey: Keys.nameCache) {
            loadedName = try? decoder.decode(
                IdentityNameCache.self, from: data
            )
        }
        if let data = defaults.data(forKey: Keys.avatarCache) {
            loadedAvatar = try? decoder.decode(
                IdentityAvatarCache.self, from: data
            )
        }
        if loadedName != nil || loadedAvatar != nil
            || defaults.object(forKey: Keys.nameCache) != nil
            || defaults.object(forKey: Keys.avatarCache) != nil {
            // 新账已立：直接读缓存（迁移只跑一次，旧
            // 账键在迁移时已清；此处残留一律不再理会）
            namePush = defaults.bool(forKey: Keys.namePushPending)
            avatarPush = defaults.bool(
                forKey: Keys.avatarPushPending
            )
            if case .image(_) = loadedAvatar?.selection {
                loadedImage = Self.loadCachedAvatarFile()
            }
        } else if Self.hasLegacyLedger(defaults) {
            // 旧账迁移（§245 一次性）：最后一判在 Core
            let migration = Self.migrateLegacy(defaults)
            loadedName = migration.nameCache
            loadedAvatar = migration.avatarCache
            loadedImage = migration.image
            namePush = migration.namePushPending
            avatarPush = migration.avatarPushPending
        }

        nameCache = loadedName
        avatarCache = loadedAvatar
        cachedAvatarImage = loadedImage
        namePushPending = namePush
        avatarPushPending = avatarPush
        avatarUIImage = Self.resolveAvatar(
            cache: loadedAvatar, cachedImage: loadedImage
        )
    }

    /// 对外头像（SwiftUI 图）：资产图与解析图同形，
    /// 消费面原有的 resizable/frame/clip 修饰链不变
    var avatarImage: Image {
        Image(uiImage: avatarUIImage)
    }

    /// 缓存里的现行名（呈现单一出口的上游）
    var cachedName: String? { nameCache?.name }

    /// 编辑器选中态：当前头像选择（缓存口径）——预
    /// 置看 id、图片看形态；无缓存回 nil（编辑器无
    /// 勾，呈现回落缺省但那不是「已选」）
    var currentAvatarSelection: AgentAvatarSelection? {
        switch avatarCache?.selection {
        case .preset(let id): return .preset(id: id)
        case .image(_): return .custom
        case nil: return nil
        }
    }

    // MARK: - 名字缓存

    /// 刷新替换名字缓存（服务端回读确认后调用）：整
    /// 份替换、cachedAt 记当下。值没变不惊动修订号
    func applyName(_ name: String, serverUpdatedAt: Date?) {
        let cache = IdentityNameCache(
            name: name, serverUpdatedAt: serverUpdatedAt,
            cachedAt: Date()
        )
        guard cache.name != nameCache?.name
                || cache.serverUpdatedAt != nameCache?.serverUpdatedAt
        else {
            nameCache = cache
            persistName()
            return
        }
        nameCache = cache
        persistName()
        revision += 1
    }

    /// 待推写穿成功后清标记（AppState 名字刷新链在推
    /// 成功后调用，随后以服务端回读整份替换缓存）
    func markNamePushed() {
        guard namePushPending else { return }
        namePushPending = false
        UserDefaults.standard.set(
            false, forKey: Keys.namePushPending
        )
    }

    private func persistName() {
        let defaults = UserDefaults.standard
        if let nameCache,
           let data = try? JSONEncoder().encode(nameCache) {
            defaults.set(data, forKey: Keys.nameCache)
        }
    }

    // MARK: - 头像缓存

    /// 同步/写穿后的头像缓存整份替换（AgentAvatar-
    /// Sync 与写穿链共用唯一入口）：imageData 非 nil
    /// 时制备落盘为缓存图；为 nil 且新缓存仍是图片
    /// 形态时保留既有缓存图（同条目只刷时刻不重下
    /// 载）。cache 为 nil＝仓明确没有当前头像，清缓
    /// 存、呈现回落缺省预置
    func applyAvatarFromSync(
        cache: IdentityAvatarCache?, imageData: Data?
    ) {
        let defaults = UserDefaults.standard
        var newImage = cachedAvatarImage
        if let imageData {
            guard let prepared = Self.preparedCustomAvatar(
                from: imageData
            ),
                  let jpeg = prepared.jpegData(
                      compressionQuality: 0.85
                  )
            else {
                // 图制备失败：整份不动（保上次缓存），
                // 不许拿坏图把呈现打空
                return
            }
            do {
                try jpeg.write(
                    to: Self.cachedAvatarFileURL, options: .atomic
                )
            } catch {
                return
            }
            newImage = prepared
        }
        let changed = cache != avatarCache
        avatarCache = cache
        if case .image(_) = cache?.selection {
            cachedAvatarImage = newImage
        } else {
            cachedAvatarImage = nil
            if cache?.selection != nil || imageData == nil {
                try? FileManager.default.removeItem(
                    at: Self.cachedAvatarFileURL
                )
            }
        }
        if let cache,
           let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: Keys.avatarCache)
        } else if cache == nil {
            defaults.removeObject(forKey: Keys.avatarCache)
        }
        refreshAvatarImage()
        if changed { revision += 1 }
    }

    /// 待推写穿成功后清标记（AgentAvatarSync 在推成
    /// 功、整份替换缓存前调用）
    func markAvatarPushed() {
        guard avatarPushPending else { return }
        avatarPushPending = false
        UserDefaults.standard.set(
            false, forKey: Keys.avatarPushPending
        )
    }

    /// 待推写穿用的缓存图原始字节（已是制备过的
    /// JPEG，直接上仓）；无图回 nil
    func cachedAvatarImageData() -> Data? {
        try? Data(contentsOf: Self.cachedAvatarFileURL)
    }

    /// 缓存图在盘（同条目免重下载的判据）
    var hasCachedAvatarImage: Bool {
        cachedAvatarImage != nil
    }

    private func refreshAvatarImage() {
        avatarUIImage = Self.resolveAvatar(
            cache: avatarCache, cachedImage: cachedAvatarImage
        )
    }

    // MARK: - 头像解析

    /// 解析顺序：缓存预置→目录图；缓存图片→缓存图
    /// （缺失回落缺省预置）；无缓存→缺省预置。不空
    /// 白、不猜别的来源——服务端单真值、缓存是唯一
    /// 本地副本
    private static func resolveAvatar(
        cache: IdentityAvatarCache?, cachedImage: UIImage?
    ) -> UIImage {
        switch cache?.selection {
        case .preset(let id):
            return presetImage(AgentAvatarPreset.resolve(id: id))
        case .image(_):
            if let cachedImage { return cachedImage }
            return presetImage(
                AgentAvatarPreset.resolve(
                    id: AgentAvatarPreset.defaultID
                )
            )
        case nil:
            return presetImage(
                AgentAvatarPreset.resolve(
                    id: AgentAvatarPreset.defaultID
                )
            )
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
    /// Fill）；盘色不按预置分色，全目录同盘。编辑器
    /// 预览与离屏渲染共用此口。
    static func presetTint(id: String) -> Color {
        Palette.fillSecondary
    }

    // MARK: - 迁移（§245 一次性）

    private struct MigrationResult {
        var nameCache: IdentityNameCache?
        var avatarCache: IdentityAvatarCache?
        var image: UIImage?
        var namePushPending: Bool
        var avatarPushPending: Bool
    }

    private static func hasLegacyLedger(
        _ defaults: UserDefaults
    ) -> Bool {
        defaults.object(forKey: Keys.legacyNameOverride) != nil
            || defaults.object(forKey: Keys.legacyAvatarPresetID) != nil
            || defaults.object(forKey: Keys.legacyAIItemID) != nil
            || defaults.bool(forKey: Keys.legacyUsesCustomAvatar)
            || defaults.object(forKey: Keys.legacyLastKnownSoulName) != nil
    }

    /// 旧账最后一判→播种新缓存→旧账键与旧图文件全
    /// 清。裁决语义在 Core IdentityLegacyMigration，
    /// 这里只做键/文件的搬运。
    private static func migrateLegacy(
        _ defaults: UserDefaults
    ) -> MigrationResult {
        let now = Date()
        var result = MigrationResult(
            nameCache: nil, avatarCache: nil, image: nil,
            namePushPending: false, avatarPushPending: false
        )

        // —— 名字 ——
        let override = defaults.string(forKey: Keys.legacyNameOverride)
        let provenance: LegacyNameOverrideProvenance?
        if let data = defaults.data(
            forKey: Keys.legacyNameOverrideProvenance
        ) {
            provenance = try? JSONDecoder().decode(
                LegacyNameOverrideProvenance.self, from: data
            )
        } else {
            provenance = nil
        }
        let soulName = defaults.string(
            forKey: Keys.legacyLastKnownSoulName
        )
        let soulAt: Date? = defaults.object(
            forKey: Keys.legacyLastKnownSoulUpdatedAt
        ) != nil
            ? Date(timeIntervalSince1970: defaults.double(
                forKey: Keys.legacyLastKnownSoulUpdatedAt))
            : nil
        let nameOutcome = IdentityLegacyMigration.effectiveName(
            override: override, provenance: provenance,
            soulName: soulName, soulUpdatedAt: soulAt
        )
        if let name = nameOutcome.name {
            result.nameCache = IdentityNameCache(
                name: name, serverUpdatedAt: soulAt, cachedAt: now
            )
            result.namePushPending = nameOutcome.needsPush
        }

        // —— 头像 ——
        let usesCustom = defaults.bool(
            forKey: Keys.legacyUsesCustomAvatar
        )
        let presetID = defaults.string(
            forKey: Keys.legacyAvatarPresetID
        ) ?? AgentAvatarPreset.defaultID
        let userSelection: AgentAvatarSelection = usesCustom
            ? .custom : .preset(id: presetID)
        let selectedAt: Date? = defaults.object(
            forKey: Keys.legacyAvatarSelectedAt
        ) != nil
            ? Date(timeIntervalSince1970: defaults.double(
                forKey: Keys.legacyAvatarSelectedAt))
            : nil
        let userEverSelected = selectedAt != nil
            || defaults.object(forKey: Keys.legacyAvatarPresetID) != nil
            || usesCustom
        let aiItemID = defaults.string(forKey: Keys.legacyAIItemID)
        let aiPresetID = defaults.string(forKey: Keys.legacyAIPresetID)
        let aiAt: Date? = defaults.object(
            forKey: Keys.legacyAIUpdatedAt
        ) != nil
            ? Date(timeIntervalSince1970: defaults.double(
                forKey: Keys.legacyAIUpdatedAt))
            : nil
        let avatarOutcome = IdentityLegacyMigration.effectiveAvatar(
            aiPresetID: aiPresetID, aiItemID: aiItemID,
            aiUpdatedAt: aiAt, user: userSelection,
            userSelectedAt: selectedAt,
            userEverSelected: userEverSelected
        )
        if let selection = avatarOutcome.selection {
            // 胜出方的图源文件：AI 胜→avatar-ai.jpg；
            // 用户胜→avatar.jpg。图片形态才搬图
            let winnerIsAI = !avatarOutcome.userWon
            let sourceURL = winnerIsAI
                ? legacyAIFileURL : legacyUserFileURL
            var image: UIImage?
            if selection == .custom,
               let data = try? Data(contentsOf: sourceURL),
               let loaded = UIImage(data: data) {
                try? FileManager.default.createDirectory(
                    at: cachedAvatarFileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? data.write(to: cachedAvatarFileURL, options: .atomic)
                image = loaded
            }
            let cacheSelection: IdentityAvatarSelection
            switch selection {
            case .preset(let id):
                cacheSelection = .preset(id: id)
            case .custom:
                cacheSelection = .image(
                    itemID: avatarOutcome.aiItemID ?? ""
                )
            }
            result.avatarCache = IdentityAvatarCache(
                selection: cacheSelection,
                itemID: avatarOutcome.userWon
                    ? nil : avatarOutcome.aiItemID,
                serverUpdatedAt: avatarOutcome.userWon
                    ? nil : avatarOutcome.aiUpdatedAt,
                cachedAt: now
            )
            result.image = image
            result.avatarPushPending = avatarOutcome.userWon
        }

        // —— 落盘新账、清旧账 ——
        if let nameCache = result.nameCache,
           let data = try? JSONEncoder().encode(nameCache) {
            defaults.set(data, forKey: Keys.nameCache)
        }
        if let avatarCache = result.avatarCache,
           let data = try? JSONEncoder().encode(avatarCache) {
            defaults.set(data, forKey: Keys.avatarCache)
        }
        defaults.set(
            result.namePushPending, forKey: Keys.namePushPending
        )
        defaults.set(
            result.avatarPushPending, forKey: Keys.avatarPushPending
        )
        for key in [
            Keys.legacyNameOverride, Keys.legacyNameOverrideProvenance,
            Keys.legacyLastKnownSoulName,
            Keys.legacyLastKnownSoulUpdatedAt,
            Keys.legacyAvatarPresetID, Keys.legacyUsesCustomAvatar,
            Keys.legacyAIItemID, Keys.legacyAIPresetID,
            Keys.legacyAIUpdatedAt, Keys.legacyAvatarSelectedAt,
            Keys.legacyUserAvatarLocked,
        ] {
            defaults.removeObject(forKey: key)
        }
        try? FileManager.default.removeItem(at: legacyUserFileURL)
        try? FileManager.default.removeItem(at: legacyAIFileURL)
        return result
    }

    // MARK: - 图文件与制备

    private static var profileDirURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        let dir = base.appendingPathComponent(
            "AgentProfile", isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }

    /// 缓存图文件（§245 单图）：头像仓当前图片在本机
    /// 的唯一副本
    private static var cachedAvatarFileURL: URL {
        profileDirURL.appendingPathComponent("avatar-cache.jpg")
    }

    /// 旧图文件（迁移读后即删）
    private static var legacyUserFileURL: URL {
        profileDirURL.appendingPathComponent("avatar.jpg")
    }

    private static var legacyAIFileURL: URL {
        profileDirURL.appendingPathComponent("avatar-ai.jpg")
    }

    private static func loadCachedAvatarFile() -> UIImage? {
        guard let data = try? Data(contentsOf: cachedAvatarFileURL)
        else { return nil }
        return UIImage(data: data)
    }

    /// 相册图制备：按 UIImage 方向居中裁方（draw 居中
    /// 覆盖），边长超 512 再等比压到 512——头像最大
    /// 呈现是分享名片 132pt（§224 审计），512 足够
    /// @3x 富余。写穿上传与缓存落盘共用同一制备。
    static func preparedCustomAvatar(from data: Data) -> UIImage? {
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

    /// 写穿上传用的制备 JPEG（编辑器选图→AppState 写
    /// 穿链取字节）：制备失败回 nil、调用方如实报错
    static func preparedAvatarJPEG(from data: Data) -> Data? {
        preparedCustomAvatar(from: data)?
            .jpegData(compressionQuality: 0.85)
    }
}

/// 符号预置盘：系统冷中性填充底＋墨色 glyph（§224）。
/// 供存储层离屏渲染与编辑器预览共用。字形占盘比
/// glyphRatio＝字形字号/盘直径；提高符号视觉占比，
/// 编辑预览与离屏渲染通过同一组件保持一致。
struct AgentAvatarPresetDisc: View {
    let symbolName: String
    let tint: Color
    /// 盘直径（pt）：字形字号按此乘 glyphRatio 推导，
    /// 调用方须与实际渲染帧边长同值（离屏渲染 240、
    /// 编辑器预览走列表行档）
    let diameter: CGFloat

    /// 字形字号比；SF Symbol 字框留白使视觉墨迹小于字号。
    static let glyphRatio: CGFloat = 0.92

    private var effectiveGlyphRatio: CGFloat {
        if diameter <= OneDayMetrics.avatarListRow { return 0.72 }
        if diameter <= OneDayMetrics.avatarSectionHead { return 0.80 }
        return Self.glyphRatio
    }

    var body: some View {
        ZStack {
            Circle().fill(tint)
            Image(systemName: symbolName)
                .font(.system(
                    size: diameter * effectiveGlyphRatio,
                    weight: .regular
                ))
                .foregroundStyle(Palette.ink)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }
}
