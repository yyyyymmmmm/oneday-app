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
struct ApprovalCardFace<DetailArea: View>: View {
    let record: WriteGateRecord
    /// 裁决提交中（宿主 store.decidingIDs 命中）：钮
    /// 栈换提交行，不许重复点
    let isDeciding: Bool
    /// 裁决失败的人话提示（宿主 store.cardNotes），
    /// 无则 nil
    let note: String?
    /// 详情链文案（宿主按入口形态与展开态给）
    let detailLinkTitle: String
    let onDetail: () -> Void
    /// 三档裁决的出口：确认弹窗与 store 调用由宿主
    /// 接（聊天自持弹窗、枢纽走段级 target，两面既有
    /// 裁决路径不变）
    let onAction: (ApprovalCardAction) -> Void
    /// 详情展开区（聊天注入 SmoothExpand 内容体；
    /// 枢纽传 EmptyView）
    @ViewBuilder let detailArea: () -> DetailArea

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            // 徽章行已删（S2-02）：子系统胶囊与「待审
            // 批」橙字都与问句/头条重复表意，只留时间
            if let createdAt = record.createdAt {
                HStack {
                    Spacer()
                    Text(ApprovalTimeText.relative(createdAt))
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }

            Text(ApprovalCardCopy.question(for: record))
                .font(.headline)
                .foregroundStyle(Palette.ink)

            summaryRow

            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Palette.danger)
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

    /// 动作区：提交中换进度行；可裁决出三档通栏钮
    /// 栈（构成与次序＝Core ApprovalCardSpec 单源）；
    /// 不可裁决只留去向说明，不摆假按钮
    @ViewBuilder
    private var actionArea: some View {
        if isDeciding {
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text("正在提交裁决…")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        } else if record.canDecide {
            VStack(spacing: ApprovalCardSpec.buttonSpacing) {
                ForEach(
                    ApprovalCardSpec.actionStack(canDecide: true),
                    id: \.self
                ) { action in
                    ApprovalCardButton(action: action) {
                        onAction(action)
                    }
                }
            }
        } else {
            Text("这类写入暂不支持在 App 内审批，请在 Hermes 中处理")
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
        }
    }
}

/// 审批卡裁决钮（自绘通栏胶囊）：标签 Text 在背景之
/// 内层满宽——宽恒等于卡宽、三钮同高同宽，主次只差
/// 填充与字色（主钮恒主题蓝实心＋白字、次钮浅灰填
/// 充＋墨字；驳回不预红、确认走宿主既有
/// confirmationDialog，与参照「拒绝」中性灰同口径）
private struct ApprovalCardButton: View {
    let action: ApprovalCardAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(action.title())
                .font(.headline)
                .foregroundStyle(
                    action.isPrimary ? Color.white : Palette.ink
                )
                .frame(maxWidth: .infinity)
                .frame(height: ApprovalCardSpec.buttonHeight)
                .background(
                    action.isPrimary
                        ? Palette.primary : Palette.selectionFill,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.odPressable)
    }
}
