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
/// §477（2026-11-24 全抄）：横边距 pageGutter 20→
/// hubGutter 16（中枢局部令牌）；简介/风格字档降
/// 16 档收 pitch 至 ≈20；「风格」标签改三级灰 13
/// 档；摘要量由 Builder §477 摘要化承接（首段＋气
/// 质），编辑钮与双卡随之回首屏；双卡本体不动。
struct HubIdentitySection: View {
    let store: AgentHubStore

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
            // §434：段容器由 List 改白页平铺（Scroll-
            // View＋VStack）——参照身份格是整页排版
            // 不是系统列表 chrome；各行原 listRowIn-
            // sets 逐值转 padding、纵距口径不变，内
            // 容与提炼零改动
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
                    cardsRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 段内大名（左对齐）：§434 前与右端小头像同行
    /// （与页头大头像同源）；页头改居中 hero 后小头
    /// 像与 hero 重复、退役，本行只留名作正文题——
    /// 对位参照身份格以名起头的排版
    private var headerRow: some View {
        Text(store.displayName)
            // §500：段内大名 28 bold → 22 semibold
            // （量测实测参照 ≈22 semibold——全页唯一
            // 「又大又粗」处，hub-type-measurement-
            // 20261124.md）；FontRoles.screenName 本
            // 体不动（抽屉名字头等他面沿用）
            .font(.title2.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .padding(.horizontal, OneDayMetrics.hubGutter)
            .padding(.top, OneDayMetrics.spacingSM)
            .padding(.bottom, OneDayMetrics.spacingXS)
    }

    /// 人设为空时的安静占位（不编造内容）：只给出去处
    private var emptyPersonaRow: some View {
        Text("暂无人设内容，点下方编辑添加。")
            .font(.body)
            .foregroundStyle(Palette.inkSecondary)
            .padding(.horizontal, OneDayMetrics.hubGutter)
            .padding(.top, OneDayMetrics.spacingXS)
            .padding(.bottom, OneDayMetrics.spacingXS)
    }

    /// 简介区：提炼后的散文段落，灰字、段间留节奏
    /// §477：字档 .body(17) 降 .callout(16)；§500 订
    /// 正：§477 注记的参照摘要 ≈15–16 系误记——实
    /// 测 ≈13 regular 灰，再降 FontRoles.meta
    /// （Footnote 13，hub-type-measurement-
    /// 20261124.md）；pitch 随字号自然收，不用负
    /// lineSpacing 硬拧
    private func personaBlock(_ paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            ForEach(
                Array(paragraphs.enumerated()), id: \.offset
            ) { _, paragraph in
                Text(paragraph)
                    .font(.meta)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(.horizontal, OneDayMetrics.hubGutter)
        .padding(.top, OneDayMetrics.spacingXS)
        .padding(.bottom, OneDayMetrics.spacingXS)
    }

    /// 风格区：「风格」小标签＋黑字段落（与基准同权重对）
    private func styleBlock(_ paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Text("风格")
                // §500：13 → 11（量测实测参照 ≈11）
                .font(.caption2)
                .foregroundStyle(Palette.inkMuted)
            ForEach(
                Array(paragraphs.enumerated()), id: \.offset
            ) { _, paragraph in
                Text(paragraph)
                    // §500：16 → 15（FontRoles.rowSub-
                    // title，量测实测参照 ≈15）
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.ink)
            }
        }
        .padding(.horizontal, OneDayMetrics.hubGutter)
        .padding(.top, OneDayMetrics.spacingSM)
        .padding(.bottom, OneDayMetrics.spacingXS)
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
            // §500：编辑钮字 17 semibold → 15 semi-
            // bold（量测实测参照 ≈15 semibold）
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: OneDayMetrics.minTapTarget)
            .background(Palette.fillSecondary, in: Capsule())
        }
        .buttonStyle(.odPressable)
        .padding(.horizontal, OneDayMetrics.hubGutter)
        .padding(.top, OneDayMetrics.spacingM)
        .padding(.bottom, OneDayMetrics.spacingS)
    }

    /// 双卡并列等宽（§218 卡面重排；§222 再对基准量
    /// 测）：标题＋「请谨慎访问」小字居左上、日期与字
    /// 形同居底行（日期左下、字形右下），卡面留白；
    /// SOUL 卡更新日期是真数据（取不到仍省略、不编
    /// 造；记忆卡服务端暂无文件日期字段、恒不显，
    /// 待补字段接线）。§449.8（用户 05:34 亲令与
    /// Muse 对齐）：渐变改参照采样暖棕/深红、覆盖
    /// §218 冷中性口径（仅本双卡）；日期格式改
    /// MM.DD.YY
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
        .padding(.horizontal, OneDayMetrics.hubGutter)
        .padding(.top, OneDayMetrics.spacingS)
        .padding(.bottom, OneDayMetrics.spacingM)
    }

    private func identityCard(
        title: String, date: Date?,
        glyph: String, gradient: LinearGradient
    ) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            Text(title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            Text("请谨慎访问")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            HStack(alignment: .bottom) {
                if let date {
                    Text(Self.cardDate(date))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Image(systemName: glyph)
                    .font(.system(size: FrameworkIcon.identityGlyphSize, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
                    .accessibilityHidden(true)
            }
        }
        .padding(OneDayMetrics.spacingM)
        .frame(maxWidth: .infinity)
        // §155（准入四问④）：最小高自适应——大字号时卡
        // 随内容长高不裁字（定高在大字号档装不下三行
        // 文本）；§222 常态高 128→150 对基准量测
        .frame(minHeight: 163)
        // §449 圆角规范核：补 .continuous——连续圆
        // 角（squircle）是 iOS 系统标准形态，Roun-
        // dedRectangle 默认 .circular 不合规范口径；
        // 半径值 23（containerCorner 梯队锚点）不动
        .background(
            gradient,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.containerCorner,
                style: .continuous
            )
        )
    }

    /// 卡面日期口径（§449.8 对 Muse 参照帧采样）：
    /// MM.DD.YY（如 11.24.26）——日期是文件的更新
    /// 日期、服务端真值（SOUL＝soulDocument.
    /// updatedAt，解码键表 §449.8 补 camelCase 后
    /// 可达）；记忆卡服务端暂无文件日期字段（GET
    /// /api/memory 只给计数），date 恒 nil 省略、
    /// 待服务端补字段后接线，不编造
    private static func cardDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM.dd.yy"
        return formatter.string(from: date)
    }

    /// SOUL 卡渐变（§449.8：用户 05:34 亲令与
    /// Muse 对齐，覆盖 §218 冷中性口径——本双卡
    /// 按参照帧像素采样：暖棕 #7C6B59→#AB8D71；
    /// 暗色同色系压深）
    private static let soulGradient = LinearGradient(
        colors: [
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0x57 / 255.0, green: 0x49 / 255.0, blue: 0x3B / 255.0, alpha: 1)
                    : UIColor(red: 0x7C / 255.0, green: 0x6B / 255.0, blue: 0x59 / 255.0, alpha: 1)
            }),
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0x77 / 255.0, green: 0x64 / 255.0, blue: 0x4C / 255.0, alpha: 1)
                    : UIColor(red: 0xAB / 255.0, green: 0x8D / 255.0, blue: 0x71 / 255.0, alpha: 1)
            }),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// 记忆卡渐变（§449.8：参照采样深红 #7B1C20
    /// →#962C36；暗色同色系压深）
    private static let memoryGradient = LinearGradient(
        colors: [
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0x57 / 255.0, green: 0x12 / 255.0, blue: 0x16 / 255.0, alpha: 1)
                    : UIColor(red: 0x7B / 255.0, green: 0x1C / 255.0, blue: 0x20 / 255.0, alpha: 1)
            }),
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0x6E / 255.0, green: 0x1F / 255.0, blue: 0x28 / 255.0, alpha: 1)
                    : UIColor(red: 0x96 / 255.0, green: 0x2C / 255.0, blue: 0x36 / 255.0, alpha: 1)
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
