import OneDayCore
import OneDayDesign
import SwiftUI

/// 枢纽页身份段（规格 §3.5；§218 视觉与呈现重做，对
/// 标 Muse 档案页）：段内大名＋同源小头像、人设散文
/// （呈现提炼 SoulPresentationBuilder：简介灰字分段＋
/// 风格小节黑字）、全宽填充胶囊编辑钮、SOUL/记忆双
/// 卡入口。§218 销账两笔旧账：①人设正文不再把 SOUL
/// 原文 markdown 整段糊屏（`#` 脚手架与名标题在呈现
/// 层摘除，全文入口在 SOUL 卡与编辑面、零丢失）；
/// ②「当前档案：…」＋本机/服务器分工小字整块删除
/// （开发口吻，宪法⑧）——档案切换自有专门面承接。
/// 编辑钮仍跳 SoulEditorView 直编全文（§155 口径不
/// 变）；身份数据逻辑（末写胜/留痕）不在本面。
/// §222（2026-11-14 枢纽页全页对齐）：版式层级再对
/// 基准量测一轮——全行显式 listRowInsets 把左缘收
/// 到 pageGutter 一条线（旧版正文行吃 List 默认内边
/// 距、与编辑/卡片行错开约 4pt）、段间纵距走令牌梯
/// 队、正文行距放开（lineSpacing 6、行 pitch 对基
/// 准 ≈28）、编辑胶囊 50→44（守 minTapTarget 下限；
/// 基准量测 ≈36 更扁、差额如实记报告）、双卡高
/// 128→150、标题升 title2、日期移左下与字形同行、
/// 字形 30→40、卡间距 12→16。正文内容与提炼口径
/// 一字不动（提炼归专包）；渐变仍守冷中性。
struct HubIdentitySection: View {
    let store: AgentHubStore

    @Environment(AppState.self) private var appState

    var body: some View {
        if store.identityFailed {
            ContentUnavailableView {
                Label("人设没读出来，可能是网络或服务暂时没响应", systemImage: "exclamationmark.triangle")
            } description: {
                Text("请稍后再试。")
            } actions: {
                Button("重试") {
                    Task { await store.loadIdentityIfNeeded() }
                }
                .buttonStyle(.bordered)
            }
        } else if let sections = store.soulSections {
            let presentation = SoulPresentationBuilder.build(
                from: sections, displayName: store.displayName
            )
            List {
                Section {
                    headerRow
                    if presentation.isEmpty {
                        emptyPersonaRow
                    } else {
                        personaBlock(presentation.introParagraphs)
                        if !presentation.styleParagraphs.isEmpty {
                            styleBlock(presentation.styleParagraphs)
                        }
                    }
                    editRow
                }
                Section {
                    cardsRow
                }
            }
            .listStyle(.plain)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 段内大名（左对齐）＋右端小头像：与页头大头像同
    /// 源（AppState 单一出口），不再放装饰符号占位
    private var headerRow: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(store.displayName)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer()
            appState.agentAvatarImage
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(Palette.hairline, lineWidth: 0.5)
                }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(
            top: OneDayMetrics.spacingSM,
            leading: OneDayMetrics.pageGutter,
            bottom: OneDayMetrics.spacingXS,
            trailing: OneDayMetrics.pageGutter
        ))
    }

    /// 人设为空时的安静占位（不编造内容）：只给出去处
    private var emptyPersonaRow: some View {
        Text("暂无人设内容，点下方编辑添加。")
            .font(.body)
            .foregroundStyle(Palette.inkSecondary)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
                top: OneDayMetrics.spacingXS,
                leading: OneDayMetrics.pageGutter,
                bottom: OneDayMetrics.spacingXS,
                trailing: OneDayMetrics.pageGutter
            ))
    }

    /// 简介区：提炼后的散文段落，灰字、段间留节奏
    private func personaBlock(_ paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            ForEach(
                Array(paragraphs.enumerated()), id: \.offset
            ) { _, paragraph in
                Text(paragraph)
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineSpacing(6)
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(
            top: OneDayMetrics.spacingXS,
            leading: OneDayMetrics.pageGutter,
            bottom: OneDayMetrics.spacingXS,
            trailing: OneDayMetrics.pageGutter
        ))
    }

    /// 风格区：「风格」小标签＋黑字段落（与基准同权重对）
    private func styleBlock(_ paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Text("风格")
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
            ForEach(
                Array(paragraphs.enumerated()), id: \.offset
            ) { _, paragraph in
                Text(paragraph)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(6)
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(
            top: OneDayMetrics.spacingSM,
            leading: OneDayMetrics.pageGutter,
            bottom: OneDayMetrics.spacingXS,
            trailing: OneDayMetrics.pageGutter
        ))
    }

    /// 全宽编辑钮（§218：填充胶囊，系统填充色深色自适
    /// 应）：跳人设编辑面 SoulEditorView 编辑全文，保存
    /// 与确认都在那一面完成（§155 口径不变）
    private var editRow: some View {
        NavigationLink {
            SoulEditorView(store: store)
        } label: {
            HStack(spacing: OneDayMetrics.spacingXS) {
                Image(systemName: "pencil")
                Text("编辑")
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: OneDayMetrics.minTapTarget)
            .background(Palette.fillSecondary, in: Capsule())
        }
        .buttonStyle(.odPressable)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(
            top: OneDayMetrics.spacingM,
            leading: OneDayMetrics.pageGutter,
            bottom: OneDayMetrics.spacingS,
            trailing: OneDayMetrics.pageGutter
        ))
    }

    /// 双卡并列等宽（§218 卡面重排；§222 再对基准量
    /// 测）：标题＋「请谨慎访问」小字居左上、日期与字
    /// 形同居底行（日期左下、字形右下），卡面留白；
    /// SOUL 卡更新日期是真数据（取不到仍省略、不编
    /// 造；记忆卡无日期数据源、恒不显）。渐变守冷中
    /// 性（SOUL＝岩板蓝灰、记忆＝深钢蓝向单强调蓝靠
    /// 拢），不照抄基准的暖色；暗色给同系深值
    private var cardsRow: some View {
        HStack(spacing: OneDayMetrics.spacingM) {
            NavigationLink {
                HubSoulDetailView(store: store)
            } label: {
                identityCard(
                    title: "SOUL",
                    date: store.soulDocument?.updatedAt,
                    glyph: "heart.fill",
                    gradient: Self.soulGradient
                )
            }
            .buttonStyle(.odPressable)

            NavigationLink {
                MemoryView()
            } label: {
                identityCard(
                    title: "记忆",
                    date: nil,
                    glyph: "text.bubble.fill",
                    gradient: Self.memoryGradient
                )
            }
            .buttonStyle(.odPressable)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(
            top: OneDayMetrics.spacingS,
            leading: OneDayMetrics.pageGutter,
            bottom: OneDayMetrics.spacingM,
            trailing: OneDayMetrics.pageGutter
        ))
    }

    private func identityCard(
        title: String, date: Date?,
        glyph: String, gradient: LinearGradient
    ) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            Text("请谨慎访问")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            HStack(alignment: .bottom) {
                if let date {
                    Text(AdminFormat.day(date))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Image(systemName: glyph)
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(OneDayMetrics.spacingM)
        .frame(maxWidth: .infinity)
        // §155（准入四问④）：最小高自适应——大字号时卡
        // 随内容长高不裁字（定高在大字号档装不下三行
        // 文本）；§222 常态高 128→150 对基准量测
        .frame(minHeight: 150)
        .background(
            gradient,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner)
        )
    }

    /// SOUL 卡渐变（岩板蓝灰，冷中性；暗色同系深值）
    private static let soulGradient = LinearGradient(
        colors: [
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0x3E / 255.0, green: 0x4E / 255.0, blue: 0x61 / 255.0, alpha: 1)
                    : UIColor(red: 0x6B / 255.0, green: 0x7D / 255.0, blue: 0x90 / 255.0, alpha: 1)
            }),
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0x27 / 255.0, green: 0x33 / 255.0, blue: 0x41 / 255.0, alpha: 1)
                    : UIColor(red: 0x47 / 255.0, green: 0x57 / 255.0, blue: 0x69 / 255.0, alpha: 1)
            }),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// 记忆卡渐变（深钢蓝，向单强调蓝靠拢；暗色同系深值）
    private static let memoryGradient = LinearGradient(
        colors: [
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0x2F / 255.0, green: 0x47 / 255.0, blue: 0x66 / 255.0, alpha: 1)
                    : UIColor(red: 0x5B / 255.0, green: 0x7C / 255.0, blue: 0xA8 / 255.0, alpha: 1)
            }),
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0x1E / 255.0, green: 0x30 / 255.0, blue: 0x47 / 255.0, alpha: 1)
                    : UIColor(red: 0x3A / 255.0, green: 0x57 / 255.0, blue: 0x7E / 255.0, alpha: 1)
            }),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// SOUL 全文详情（SOUL 卡点按落点，规格 #41）：只读
/// 呈现解析前的全文；编辑走身份段的编辑钮（人设编辑
/// 面 SoulEditorView）
struct HubSoulDetailView: View {
    let store: AgentHubStore

    var body: some View {
        ScrollView {
            Text(store.soulDocument?.content ?? "")
                .font(.body)
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OneDayMetrics.pageGutter)
        }
        .background(Palette.pageBG)
        .navigationTitle("人设全文")
        .navigationBarTitleDisplayMode(.inline)
    }
}
