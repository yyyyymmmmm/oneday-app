import OneDayCore
import OneDayDesign
import SwiftUI

/// 审批卡共用卡面（样式二期 S2-01/S2-02/S2-03）：聊天
/// 就地卡与枢纽待批卡同一实现、同一几何与句式——时
/// 间行＋问句标题（Core ApprovalHeadline 人话口径）＋
/// 一行说明（句尾行内蓝链）＋三档通栏裁决钮。两面只
/// 差详情入口一参：聊天＝就地展开（链接文案随展开态
/// 换「查看详情/收起详情」、展开区由 detailArea 注入）、
/// 枢纽＝打开改动 sheet（链接恒「查看改动」、展开区
/// 恒空）。卡体外框（内距/面色/圆角）由宿主持有，两
/// 面同值（spacingM／Palette.surface／
/// containerCorner）。
///
/// 旧形态退役记账：.bordered 家族按钮在 buttonStyle
/// 之后挂 frame，背景只按标签内容绘制、三钮 hug 成
/// 内容宽药丸居中飘（S2-01 机理）；正文最多五段灰字
/// ＋徽章行与标题重复表意（S2-02）。新形态逐项对照
/// Muse 审批卡参照：白卡、粗体问句、一行说明＋行
/// 内蓝链、通栏等宽三钮（主钮蓝实心白字）。
///
/// §245 补齐两件：①工具图标（行首，Core 单源映
/// 射，对标参照卡的工具图标位）；②防呆呈现合成一
/// 套——预检原因上卡面＋只给驳回，裁决回执原因经
/// 宿主 cardNotes 同槽呈现，原因都走「上卡面」一
/// 条通道。B-05（§301）：桥字段已合并为 reason＋
/// reason_phase，卡面只经 Core
/// ApprovalCardCopy.reasonLine 单读口取行，不再
/// 直读记录字段拼句。
struct ApprovalCardFace<DetailArea: View>: View {
    let record: WriteGateRecord
    /// 裁决提交中（宿主 store.decidingIDs 命中）：钮
    /// 栈换提交行，不许重复点
    let isDeciding: Bool
    /// 裁决失败的人话提示（宿主 store.cardNotes），
    /// 无则 nil
    let note: String?
    /// 多条排队时的进度文案（如「待批 1/3」），单条为 nil
    var queueProgress: String? = nil
    /// 详情链文案（宿主按入口形态与展开态给）
    let detailLinkTitle: String
    let onDetail: () -> Void
    /// 三档裁决的出口：一次点按直接落账
    let onAction: (ApprovalCardAction) -> Void
    /// 详情展开区（聊天注入 SmoothExpand 内容体；
    /// 枢纽传 EmptyView）
    @ViewBuilder let detailArea: () -> DetailArea

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack(spacing: OneDayMetrics.spacingXS) {
                Image(
                    systemName: ApprovalCardSpec.toolIconName(
                        for: record.subsystem
                    )
                )
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
                if let queueProgress {
                    Text(queueProgress)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.primary)
                        .lineLimit(1)
                }
                Spacer()
                if let createdAt = record.createdAt {
                    Text(ApprovalTimeText.relative(createdAt))
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }

            Text(ApprovalCardCopy.question(for: record))
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)

            summaryRow

            if let reasonLine = ApprovalCardCopy.reasonLine(for: record) {
                Label {
                    Text(reasonLine)
                        .foregroundStyle(Palette.warningText)
                        .lineLimit(2)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Palette.warning)
                }
                .font(.footnote)
            }

            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Palette.danger)
                    .lineLimit(2)
            }

            detailArea()

            actionArea
        }
    }

    /// 一行说明＋句尾行内蓝链：说明走 Core 一行口径
    /// （summaryLine）、单行截断；链接恒钉行尾不被截
    /// 掉（fixedSize 保位），点按走宿主详情入口
    private var summaryRow: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: OneDayMetrics.spacingXS
        ) {
            Text(ApprovalCardCopy.summaryLine(for: record))
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
            Button(detailLinkTitle) { onDetail() }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(Palette.primary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// 动作区：提交中换进度行；可裁决出通栏钮栈（高
    /// 风险写操作只给允许／拒绝两钮；防呆记录只给驳回）
    @ViewBuilder
    private var actionArea: some View {
        if isDeciding {
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text("正在提交裁决…")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
        } else if record.canDecide {
            let scopeText = ApprovalCardCopy.alwaysAllowScope(
                for: record
            )
            VStack(spacing: ApprovalCardSpec.buttonSpacing) {
                ForEach(
                    ApprovalCardSpec.actionStack(
                        canDecide: true,
                        blocked: record.isBlocked,
                        highRisk: record.isHighRisk
                    ),
                    id: \.self
                ) { action in
                    ApprovalCardButton(
                        action: action,
                        scopeText: action == .alwaysAllow
                            ? scopeText : nil
                    ) {
                        onAction(action)
                    }
                }
            }
        } else {
            Text("这类写入暂不支持在 App 内审批，请在 Hermes 中处理")
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(2)
        }
    }
}

/// 审批卡裁决钮（D10 定版④三档形态，高由 Spec 锁死）
private struct ApprovalCardButton: View {
    let action: ApprovalCardAction
    let scopeText: String?
    let onTap: () -> Void

    var body: some View {
        switch action.buttonRole {
        case .filledPrimary:
            Button(action: onTap) {
                Text(action.title())
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(
                        height: ApprovalCardSpec.buttonHeight(
                            for: action
                        )
                    )
                    .background(
                        Palette.primarySaturated, in: Capsule()
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.odPressable)
        case .outlinedSecondary:
            Button(action: onTap) {
                VStack(spacing: 1) {
                    Text(action.title())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let scopeText, !scopeText.isEmpty {
                        Text(L10n.format("仅限 %@", scopeText))
                            .font(.caption2)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(maxWidth: .infinity)
                .frame(
                    height: ApprovalCardSpec.buttonHeight(
                        for: action
                    )
                )
                .background(
                    Capsule().strokeBorder(
                        Palette.hairline, lineWidth: 1
                    )
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.odPressable)
        case .text:
            Button(action: onTap) {
                Text(action.title())
                    .font(.headline)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(
                        height: ApprovalCardSpec.buttonHeight(
                            for: action
                        )
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
