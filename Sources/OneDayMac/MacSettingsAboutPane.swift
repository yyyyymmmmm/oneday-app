import SwiftUI
import OneDayCore
import OneDayDesign

/// 帮助、更新说明、关于与法律文档页（棒 5 / mac-07，对位 #87/#88/#89）：
/// 版本号直读 Bundle.main 真值；更新说明复用 Core ReleaseNotes 单源；
/// 隐私政策与用户协议与 iOS LegalDocumentView 同文。
struct MacSettingsAboutPane: View {
    @State private var legalKind: MacLegalSheetKind?

    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "—"
    }

    private var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "—"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("OneDay for macOS")
                            .font(.system(size: 16, weight: .semibold))
                        Text("v\(shortVersion) (\(buildVersion))")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section("连接帮助") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("服务器地址")
                        .font(.system(size: 13, weight: .medium))
                    Text("形如 https://hermes.example.com，不要带结尾斜杠；局域网自建服务器可使用 http。")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("登录凭据")
                        .font(.system(size: 13, weight: .medium))
                    Text("使用伴生面板密码一步登录，密钥保存在系统钥匙串中，不上传给任何第三方。")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }

            Section("法律与开源") {
                Button("隐私政策") { legalKind = .privacy }
                Button("用户协议") { legalKind = .terms }
                Link("在 GitHub 提交问题", destination: URL(string: "https://github.com/yyyyymmmmm/oneday-app/issues")!)
                Link("Hermes 开源项目", destination: URL(string: "https://github.com/NousResearch/hermes-agent")!)
            }

            Section("更新说明") {
                ForEach(ReleaseNotes.entries(currentVersion: shortVersion).prefix(8)) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("v\(entry.version)")
                                .font(.system(size: 13, weight: .semibold))
                            if entry.version == shortVersion {
                                Text("当前版本")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Palette.successText)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Palette.success.opacity(0.12), in: Capsule())
                            }
                        }
                        ForEach(entry.highlights, id: \.self) { line in
                            Text("· \(line)")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $legalKind) { kind in
            MacLegalSheetView(kind: kind)
        }
    }
}

enum MacLegalSheetKind: String, Identifiable {
    case privacy, terms
    var id: String { rawValue }
    var title: String { self == .privacy ? "隐私政策" : "用户协议" }

    var bodyText: String {
        switch self {
        case .privacy:
            return """
            生效日期：2026 年 11 月 11 日

            1. 没有账号，也不收集使用数据
            OneDay 没有账号体系，不要求注册，我们也没有承接用户数据的服务器。App 不向我们回传你的对话、文件、设备数据或使用行为；不集成广告或第三方统计 SDK。

            2. 服务器地址与凭据只存本机
            你填写的服务器地址与登录凭据只保存在这台 Mac 的系统钥匙串中，用于连接你自己的 Hermes 服务器，不上传给任何第三方。

            3. 对话与文件只在你与你的服务器之间流转
            你的对话内容以及上传/生成的文件只在本机与你的 Hermes 服务器之间直接传输。
            """
        case .terms:
            return """
            生效日期：2026 年 11 月 11 日

            1. 服务定位
            OneDay 是原生客户端软件，用于连接你自己部署的 Hermes 服务。OneDay 本身不提供云托管服务。

            2. 自托管与操作确认
            服务器的部署、运行与数据安全由你或你的服务器提供方负责。涉及审批的命令与写入操作会在执行前请你确认，请勿批准你不理解的操作。

            3. 开源与责任限制
            OneDay 按「现状」提供，其使用与分发遵循仓库内所附许可证；Hermes 权利归其权利人所有。
            """
        }
    }
}

private struct MacLegalSheetView: View {
    let kind: MacLegalSheetKind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(kind.title)
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
            }
            Divider()
            ScrollView {
                Text(kind.bodyText)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .frame(width: 480, height: 380)
    }
}
