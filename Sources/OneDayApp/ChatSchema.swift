import SwiftData

/// 本地库版本化迁移链（根治版包 3，DESIGN §332；
/// 待办第 122 条 G-05）：自本版起本地库的 schema
/// 演进只许走版本链——任何结构变更必须新开下一
/// 版本并在 ChatMigrationPlan 追加迁移段，不许原
/// 地改已冻结版本的模型定义。指纹由 SchemaFoun-
/// dationAppTests 钉死（两版的存储属性全集逐一
/// 登记，原地改动必然触发红）。
///
/// 版本沿革：
/// - V1（1.0.0）：§332 冻结时的现行两模型。台账
///   187 升版时已按规程复制冻结为独立定义（Chat-
///   SchemaV1Models.swift，嵌套于本枚举、实体名
///   不变），永不再改。
/// - V2（2.0.0）：台账 187 消息反应——ChatEntry
///   加 serverRowID（服务端行 id 钉桩）与 reac-
///   tionsData（反应镜像）两可选字段（均带默认
///   值，V1→V2 走轻量迁移段）。§383 升版时已按
///   规程复制冻结为独立定义（ChatSchemaV2-
///   Models.swift，嵌套于本枚举），永不再改。
/// - V3（3.0.0）：台账 154 消息级幂等——Chat-
///   Entry 加 clientMessageID（发件箱出队幂等
///   身份，可选带默认值，V2→V3 走轻量迁移
///   段）。现行模型本体在 ChatStore.swift。
enum ChatSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    /// 备份命名用的版本字面（与 versionIdentifier
    /// 同值，改版时两处同拍更新）
    static let versionTag = "1.0.0"

    static var models: [any PersistentModel.Type] {
        // 嵌套冻结副本（ChatSchemaV1Models.swift）：
        // 无限定名在本枚举作用域内先解到嵌套类型
        [ChatThread.self, ChatEntry.self]
    }
}

enum ChatSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    /// 备份命名用的版本字面（同 V1 口径）
    static let versionTag = "2.0.0"

    static var models: [any PersistentModel.Type] {
        // 嵌套冻结副本（ChatSchemaV2Models.swift）：
        // 无限定名在本枚举作用域内先解到嵌套类型
        [ChatThread.self, ChatEntry.self]
    }
}

enum ChatSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
    }

    /// 备份命名用的版本字面（同 V1 口径）
    static let versionTag = "3.0.0"

    static var models: [any PersistentModel.Type] {
        // 现行模型本体（ChatStore.swift）：本枚举无
        // 嵌套同名类型，无限定名解到全局现行模型
        [ChatThread.self, ChatEntry.self]
    }
}

/// 当前版本别名：容器工厂只许引用本别名指向的版
/// 本立 Schema；升版时改指新版一处即可
typealias CurrentChatSchema = ChatSchemaV3

/// 迁移计划（§332）：版本序列与逐级迁移段的唯一
/// 声明处。V1→V2、V2→V3 都只有带默认值的可选字段
/// 新增，走轻量迁移段（SwiftData 推断迁移）——不
/// 许绕过计划直接换 Schema 打开旧库
enum ChatMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ChatSchemaV1.self, ChatSchemaV2.self, ChatSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: ChatSchemaV1.self,
                toVersion: ChatSchemaV2.self
            ),
            .lightweight(
                fromVersion: ChatSchemaV2.self,
                toVersion: ChatSchemaV3.self
            ),
        ]
    }
}
