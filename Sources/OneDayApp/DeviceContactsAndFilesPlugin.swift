import Contacts
import Foundation
import OneDayCore
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Contacts 执行器（只读现查）

/// 通讯录执行器：只做关键词现查与本地列表读，写一
/// 律不做（设计档定版：高误伤）。受限授权时系统框
/// 架天然只返回被勾选子集——呈现层据权限态明说。
final class ContactsEngine: @unchecked Sendable {
    let store = CNContactStore()

    private static var keysToFetch: [CNKeyDescriptor] {
        // 键是 String 常量、描述符是 CNKeyDescriptor，
        // 异构字面量推断不稳——命令式组装（逐个桥 NSString）
        var keys: [CNKeyDescriptor] = []
        keys.append(CNContactGivenNameKey as NSString)
        keys.append(CNContactFamilyNameKey as NSString)
        keys.append(CNContactOrganizationNameKey as NSString)
        keys.append(CNContactPhoneNumbersKey as NSString)
        keys.append(CNContactEmailAddressesKey as NSString)
        keys.append(
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
        )
        return keys
    }

    func requestAccess() async -> DevicePermissionState {
        _ = try? await store.requestAccess(for: .contacts)
        return DevicePermissions.contactsState()
    }

    private static func item(_ contact: CNContact) -> DeviceContactItem {
        let name = CNContactFormatter.string(
            from: contact, style: .fullName
        ) ?? ""
        return DeviceContactItem(
            id: contact.identifier,
            name: name.isEmpty ? "(无姓名)" : name,
            phones: contact.phoneNumbers.map { $0.value.stringValue },
            emails: contact.emailAddresses.map { $0.value as String },
            organization: contact.organizationName.isEmpty
                ? nil : contact.organizationName
        )
    }

    static func contactObject(_ item: DeviceContactItem) -> [String: JSONValue] {
        var object: [String: JSONValue] = [
            "name": .string(item.name),
            "phones": .array(item.phones.map { .string($0) }),
            "emails": .array(item.emails.map { .string($0) }),
        ]
        if let organization = item.organization {
            object["organization"] = .string(organization)
        }
        return object
    }

    /// contacts_search：关键词现查、只回命中（限额收敛在 Core 解析层）
    func search(_ args: ContactsSearchArgs) throws -> JSONValue {
        let predicate = CNContact.predicateForContacts(
            matchingName: args.query
        )
        do {
            let found = try store.unifiedContacts(
                matching: predicate, keysToFetch: Self.keysToFetch
            )
            let items = found.prefix(args.limit).map(Self.item)
            return .object([
                "readAt": .string(DeviceISO8601.format(Date())),
                "query": .string(args.query),
                "count": .number(Double(items.count)),
                "contacts": .array(
                    items.map { .object(Self.contactObject($0)) }
                ),
            ])
        } catch {
            throw DeviceToolError.failed(
                "通讯录搜索失败：\(error.localizedDescription)"
            )
        }
    }

    /// 本地列表读（详情页）：进页才读、离页不留副本
    func allContacts(limit: Int = 1000) throws -> [DeviceContactItem] {
        let request = CNContactFetchRequest(keysToFetch: Self.keysToFetch)
        request.sortOrder = .userDefault
        var items: [DeviceContactItem] = []
        do {
            try store.enumerateContacts(with: request) { contact, stop in
                items.append(Self.item(contact))
                if items.count >= limit { stop.pointee = true }
            }
        } catch {
            throw DeviceToolError.failed(
                "通讯录没读出来：\(error.localizedDescription)"
            )
        }
        return items
    }

    /// 本地按名过滤（详情页搜索框）：与工具同谓词口径
    func searchLocal(query: String, limit: Int = 200) throws -> [DeviceContactItem] {
        let predicate = CNContact.predicateForContacts(matchingName: query)
        let found = try store.unifiedContacts(
            matching: predicate, keysToFetch: Self.keysToFetch
        )
        return found.prefix(limit).map(Self.item)
    }

    // MARK: 同步制（0.36.14）：清单＋全量记录一次枚举

    /// 同步快照：一次整本枚举同时产出清单条目（标
    /// 识＋指纹，送伴生比对）与全量最小字段记录
    /// （只取比对说有变的那些上传）。分组名靠分组
    /// 成员关系反查（联系人本体不带分组信息）；
    /// 受限授权下系统只给勾选子集，枚举天然收敛
    func syncSnapshot() throws -> (
        entries: [ContactManifestEntry],
        records: [SyncContactRecord]
    ) {
        let groupMap = groupNamesByContactID()
        let request = CNContactFetchRequest(keysToFetch: Self.keysToFetch)
        request.sortOrder = .userDefault
        var records: [SyncContactRecord] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                records.append(Self.syncRecord(
                    contact, groups: groupMap[contact.identifier] ?? []
                ))
            }
        } catch {
            throw DeviceToolError.failed(
                "通讯录没读出来：\(error.localizedDescription)"
            )
        }
        return (records.map(\.manifestEntry), records)
    }

    private static func syncRecord(
        _ contact: CNContact, groups: [String]
    ) -> SyncContactRecord {
        let name = CNContactFormatter.string(
            from: contact, style: .fullName
        ) ?? ""
        return SyncContactRecord(
            id: contact.identifier,
            displayName: name,
            familyName: contact.familyName.isEmpty
                ? nil : contact.familyName,
            givenName: contact.givenName.isEmpty
                ? nil : contact.givenName,
            organization: contact.organizationName.isEmpty
                ? nil : contact.organizationName,
            phones: contact.phoneNumbers.map {
                SyncLabeledValue(
                    label: $0.label.map {
                        CNLabeledValue<NSString>.localizedString(
                            forLabel: $0
                        )
                    } ?? "",
                    value: $0.value.stringValue
                )
            },
            emails: contact.emailAddresses.map {
                SyncLabeledValue(
                    label: $0.label.map {
                        CNLabeledValue<NSString>.localizedString(
                            forLabel: $0
                        )
                    } ?? "",
                    value: $0.value as String
                )
            },
            groups: groups
        )
    }

    /// 分组名反查：逐组取成员标识建映射（分组数
    /// 量级小，成本可控）；取不到分组就回空表（分
    /// 组只是记录的一个字段，缺了不拦整本同步）
    private func groupNamesByContactID() -> [String: [String]] {
        guard let groups = try? store.groups(matching: nil)
        else { return [:] }
        var map: [String: [String]] = [:]
        for group in groups {
            let predicate = CNContact.predicateForContactsInGroup(
                withIdentifier: group.identifier
            )
            var keys: [CNKeyDescriptor] = []
            keys.append(CNContactIdentifierKey as NSString)
            guard let members = try? store.unifiedContacts(
                matching: predicate, keysToFetch: keys
            ) else { continue }
            for member in members {
                map[member.identifier, default: []].append(group.name)
            }
        }
        return map
    }
}

// MARK: - 剪贴板执行器（设备扩容批一）

/// 剪贴板现读现写：内容在别家 App 手里时，读取动作
/// 本身会触发系统粘贴提示横幅（iOS 16+ 的规矩，数据
/// 源说明里已如实写明、不装无感）；只探测类型
/// （hasStrings 等）不触发提示，故先探测后取内容，
/// 非文字内容如实回类型、不编内容。写完回读比对才
/// 报成功（写纪律与既有写工具同）。
final class ClipboardEngine: @unchecked Sendable {

    /// clipboard_get 结果：文字原样回；链接回其文字
    /// 形态；只有图片时回类型说明、无内容
    func getResult() -> JSONValue {
        let board = UIPasteboard.general
        var result: [String: JSONValue] = [
            "readAt": .string(DeviceISO8601.format(Date())),
        ]
        if board.hasStrings, let text = board.string {
            result["type"] = .string("text")
            result["text"] = .string(text)
        } else if board.hasURLs, let url = board.url {
            result["type"] = .string("url")
            result["text"] = .string(url.absoluteString)
        } else if board.hasImages {
            result["type"] = .string("image")
            result["note"] = .string("剪贴板里是一张图片，没有文字内容")
        } else {
            result["type"] = .string("empty")
            result["note"] = .string("剪贴板是空的")
        }
        return .object(result)
    }

    /// clipboard_set：写入后回读比对（回读自家刚写
    /// 的内容不触发系统提示）；不一致即失败
    func setClipboard(
        _ args: ClipboardSetArgs
    ) throws -> (objectID: String, result: JSONValue) {
        let board = UIPasteboard.general
        board.string = args.text
        guard board.string == args.text else {
            throw DeviceToolError.failed("写入后核对不一致，不报成功")
        }
        return ("clipboard", .object([
            "written": .bool(true),
            "verified": .bool(true),
            "characters": .number(Double(args.text.count)),
        ]))
    }

    /// 详情页本地预览（页面只在用户亲手点按钮时调，
    /// 因为这一读同样可能触发系统粘贴提示）
    func currentText() -> String? {
        UIPasteboard.general.string
    }
}

// MARK: - 沙盒文件执行器（设备扩容批一）

/// App 自有 Documents 区的文本文件列/读/写：路径先
/// 过 Core 的 SandboxPath 规范化（防越界纯逻辑），落
/// 到 URL 后再做一次「解析符号链接＋标准化后仍在根
/// 内」的前缀校验，双保险。写完回读字节比对才报成
/// 功；二进制/超限如实报错、不静默截断。
final class SandboxFilesEngine: @unchecked Sendable {

    private var rootURL: URL {
        FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
    }

    /// 规范相对路径 → 根内 URL（越界即 invalidArguments）
    private func resolvedURL(
        forNormalizedPath path: String
    ) throws -> URL {
        var url = rootURL
        for component in path.split(separator: "/") {
            url = url.appendingPathComponent(String(component))
        }
        let root = rootURL.resolvingSymlinksInPath()
            .standardizedFileURL.path
        let resolved = url.resolvingSymlinksInPath()
            .standardizedFileURL.path
        guard resolved == root || resolved.hasPrefix(root + "/")
        else {
            throw DeviceToolError.invalidArguments(
                "路径越出了 OneDay 文件夹的范围"
            )
        }
        return url
    }

    /// 文件元数据对象（列表条目与写回放共用）：只
    /// 含名/路径/大小/修改时刻，不含内容
    static func fileObject(
        _ item: DeviceFileItem
    ) -> [String: JSONValue] {
        var object: [String: JSONValue] = [
            "name": .string(item.name),
            "path": .string(item.path),
            "isDirectory": .bool(item.isDirectory),
            "modifiedAt": .string(
                DeviceISO8601.format(item.modifiedAt)
            ),
        ]
        if !item.isDirectory {
            object["sizeBytes"] = .number(Double(item.sizeBytes))
        }
        return object
    }

    /// 某相对路径的当前条目（不在/越界回 nil）：写
    /// 回放与详情页共用
    func item(relativePath: String) -> DeviceFileItem? {
        guard !relativePath.isEmpty,
              let url = try? resolvedURL(
                forNormalizedPath: relativePath
              ),
              let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey, .fileSizeKey,
                .contentModificationDateKey,
              ])
        else { return nil }
        return DeviceFileItem(
            name: url.lastPathComponent,
            path: relativePath,
            isDirectory: values.isDirectory ?? false,
            sizeBytes: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate
                ?? Date(timeIntervalSince1970: 0)
        )
    }

    /// 一层列表（不递归；工具与详情页共用）：目录
    /// 在前、同类按名序，输出确定性
    func listItems(
        relativePath: String
    ) throws -> [DeviceFileItem] {
        let url = try resolvedURL(forNormalizedPath: relativePath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: url.path, isDirectory: &isDirectory
        ) else {
            throw DeviceToolError.failed(
                relativePath.isEmpty
                    ? "文件夹不存在"
                    : "文件夹不存在：\(relativePath)"
            )
        }
        guard isDirectory.boolValue else {
            throw DeviceToolError.failed(
                "「\(relativePath)」是文件，不是文件夹"
            )
        }
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [
                    .isDirectoryKey, .fileSizeKey,
                    .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw DeviceToolError.failed(
                "文件夹没读出来：\(error.localizedDescription)"
            )
        }
        let prefix = relativePath.isEmpty ? "" : relativePath + "/"
        let items = children.map { child -> DeviceFileItem in
            let values = try? child.resourceValues(forKeys: [
                .isDirectoryKey, .fileSizeKey,
                .contentModificationDateKey,
            ])
            return DeviceFileItem(
                name: child.lastPathComponent,
                path: prefix + child.lastPathComponent,
                isDirectory: values?.isDirectory ?? false,
                sizeBytes: Int64(values?.fileSize ?? 0),
                modifiedAt: values?.contentModificationDate
                    ?? Date(timeIntervalSince1970: 0)
            )
        }
        return items.sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory && !$1.isDirectory
            }
            return $0.name.localizedStandardCompare($1.name)
                == .orderedAscending
        }
    }

    /// files_list 结果：条目上限在 Core 常量，超了
    /// 截断并标 truncated（不装全给了）
    func listResult(_ args: FilesListArgs) throws -> JSONValue {
        let items = try listItems(relativePath: args.path)
        let capped = Array(
            items.prefix(SandboxPath.maxListEntries)
        )
        var result: [String: JSONValue] = [
            "path": .string(args.path),
            "readAt": .string(DeviceISO8601.format(Date())),
            "count": .number(Double(capped.count)),
            "entries": .array(
                capped.map { .object(Self.fileObject($0)) }
            ),
        ]
        if items.count > capped.count {
            result["truncated"] = .bool(true)
        }
        return .object(result)
    }

    /// 读文本（工具与详情页预览共用）：不存在/是目
    /// 录/超限/非 UTF-8 文本一律如实报错
    func readText(relativePath: String) throws -> String {
        let url = try resolvedURL(forNormalizedPath: relativePath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: url.path, isDirectory: &isDirectory
        ) else {
            throw DeviceToolError.failed("文件不存在：\(relativePath)")
        }
        guard !isDirectory.boolValue else {
            throw DeviceToolError.failed(
                "「\(relativePath)」是文件夹，读不出文本"
            )
        }
        let attributes = try? FileManager.default
            .attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value
            ?? 0
        guard size <= SandboxPath.maxContentBytes else {
            throw DeviceToolError.failed(
                "文件超过 256 KB 上限，不整份读取"
            )
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DeviceToolError.failed(
                "文件没读出来：\(error.localizedDescription)"
            )
        }
        guard let text = String(data: data, encoding: .utf8)
        else {
            throw DeviceToolError.failed(
                "这个文件不是文本内容，读不出文字"
            )
        }
        return text
    }

    /// files_read 结果：内容＋字节数＋现读时刻
    func readResult(_ args: FilesReadArgs) throws -> JSONValue {
        let text = try readText(relativePath: args.path)
        return .object([
            "path": .string(args.path),
            "readAt": .string(DeviceISO8601.format(Date())),
            "bytes": .number(Double(text.utf8.count)),
            "content": .string(text),
        ])
    }

    /// files_write：父目录自动建、原子写、回读逐字
    /// 节比对才报成功；objectID＝规范相对路径（账
    /// 本只存路径这一元数据，不存内容）
    func writeFile(
        _ args: FilesWriteArgs
    ) throws -> (objectID: String, result: JSONValue) {
        let url = try resolvedURL(forNormalizedPath: args.path)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: url.path, isDirectory: &isDirectory
        ), isDirectory.boolValue {
            throw DeviceToolError.failed(
                "同名文件夹已存在，写不进去：\(args.path)"
            )
        }
        let data = Data(args.content.utf8)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            throw DeviceToolError.failed(
                "写入文件失败：\(error.localizedDescription)"
            )
        }
        guard let back = try? Data(contentsOf: url),
              back == data
        else {
            throw DeviceToolError.failed("写入后核对不一致，不报成功")
        }
        return (args.path, .object([
            "path": .string(args.path),
            "written": .bool(true),
            "verified": .bool(true),
            "bytes": .number(Double(data.count)),
        ]))
    }

    // MARK: 批三·图片落盘与读数（相机产物/识别输入）

    /// 拍照/扫描的图片落盘：统一进 captures/ 子目录，
    /// 原子写、回读逐字节核对才回条目（回读验证纪
    /// 律）；fileName 由引擎按「photo-/scan-＋印记」
    /// 规则生成、不含路径成分
    func saveCapture(
        data: Data, fileName: String
    ) throws -> DeviceFileItem {
        let relativePath = "captures/" + fileName
        let url = try resolvedURL(forNormalizedPath: relativePath)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            throw DeviceToolError.failed(
                "图片保存失败：\(error.localizedDescription)"
            )
        }
        guard let back = try? Data(contentsOf: url),
              back == data
        else {
            throw DeviceToolError.failed("图片保存后核对不一致，不报成功")
        }
        guard let item = item(relativePath: relativePath) else {
            throw DeviceToolError.failed("图片保存后读不到，不报成功")
        }
        return item
    }

    /// 读二进制（识别输入用）：边界与 readText 同一
    /// 套（根内解析＋符号链接前缀复核），上限由调用
    /// 方给（图片口径 20 MB、与文本的 256 KB 分开）
    func readData(
        relativePath: String, maxBytes: Int
    ) throws -> Data {
        let url = try resolvedURL(forNormalizedPath: relativePath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: url.path, isDirectory: &isDirectory
        ) else {
            throw DeviceToolError.failed("文件不存在：\(relativePath)")
        }
        guard !isDirectory.boolValue else {
            throw DeviceToolError.failed(
                "「\(relativePath)」是文件夹，读不出内容"
            )
        }
        let attributes = try? FileManager.default
            .attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value
            ?? 0
        guard size <= maxBytes else {
            throw DeviceToolError.failed(
                "文件超过 \(maxBytes / 1024 / 1024) MB 上限，不读取"
            )
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw DeviceToolError.failed(
                "文件没读出来：\(error.localizedDescription)"
            )
        }
    }

    /// captures/ 里的图片条目（相机详情页与扫描回放
    /// 共用）：目录还不存在时回空表、不报错
    func captureItems() -> [DeviceFileItem] {
        (try? listItems(relativePath: "captures")) ?? []
    }

    /// 文件呈现（批四 file_preview/file_print/share_
    /// sheet 共用）：规范相对路径 → 根内 URL（与读
    /// 写同一条 resolvedURL 边界：符号链接双保险在
    /// 里面）；文件不在如实报错、不许把不存在的路
    /// 径递给系统呈现面
    func urlForPreview(relativePath: String) throws -> URL {
        let url = try resolvedURL(
            forNormalizedPath: relativePath
        )
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: url.path, isDirectory: &isDirectory
        ) else {
            throw DeviceToolError.failed(
                "文件不存在：\(relativePath)"
            )
        }
        guard !isDirectory.boolValue else {
            throw DeviceToolError.failed(
                "「\(relativePath)」是文件夹，没法预览或打印"
            )
        }
        return url
    }
}


extension ContactsEngine: DeviceCapabilityPlugin {
    static let capabilityDomain = "contacts"
}
extension ClipboardEngine: DeviceCapabilityPlugin {
    static let capabilityDomain = "clipboard"
}
extension SandboxFilesEngine: DeviceCapabilityPlugin {
    static let capabilityDomain = "files"
}
