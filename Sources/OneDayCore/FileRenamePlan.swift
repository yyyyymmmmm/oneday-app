import Foundation

/// 改名判定（§131 对齐包，D8）：Hermes 0.23.0 文件
/// API 无改名/移动端点（openapi 实查：/api/files 只
/// 有 GET/DELETE，余 read/download/upload/mkdir），
/// 宿主改名走既有原语组合链——下载原文件→以新名上
/// 传→回读列表校验新条目在且字节数一致→才删旧文
/// 件。本表只管判定不管执行：新名规整（与新建文件
/// 夹同纪律并加扩展名保留校验）、目标路径拼装、组
/// 合链的字节上限（复用上传上限——超过上限的件组
/// 合链搬不动，如实拒绝、不许先删后传）。
public enum FileRenamePlan {
    /// 新名规整：去首尾空白后非空、不含路径分隔与换
    /// 行、不是 "." / ".."；返回规整后的名字，非法
    /// 回 nil（与 FileBrowserLogic.isValidFolderName
    /// 同纪律，判定单源在本表供改名专用口径）
    public static func normalizedName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"),
              !name.contains("\n"), !name.contains("\0")
        else { return nil }
        return name
    }

    /// 改名是否保持扩展名：扩展名被改掉（或被删）时
    /// 文件类型随之变脸，宿主须向用户明示后再继续
    /// ——本判据只报事实，确认归宿主
    public static func keepsExtension(
        oldName: String, newName: String
    ) -> Bool {
        (oldName as NSString).pathExtension.lowercased()
            == (newName as NSString).pathExtension.lowercased()
    }

    /// 目标路径：同目录换末段（改名不许顺带搬家——
    /// 路径分隔已在 normalizedName 挡下，拼装走
    /// FileBrowserLogic.joinPath 单源）
    public static func targetPath(
        currentPath: String, newName: String
    ) -> String {
        FileBrowserLogic.joinPath(
            directory: (currentPath as NSString)
                .deletingLastPathComponent,
            name: newName
        )
    }

    /// 组合链可搬字节数：与上传同闸（25MB）。下载回
    /// 来的真实字节数超闸即整链放弃、原件不动
    public static func isChainAllowed(byteCount: Int) -> Bool {
        FileBrowserLogic.isUploadSizeAllowed(byteCount: byteCount)
    }

    /// 同名冲突判定：目标已在父目录列表中（且不是它
    /// 自己）即冲突——组合链不许静默覆盖别人的文件
    public static func conflicts(
        targetPath: String, currentPath: String,
        siblingPaths: [String]
    ) -> Bool {
        targetPath != currentPath && siblingPaths.contains(targetPath)
    }
}
