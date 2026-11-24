import OneDayCore
import OneDayDesign
import SwiftUI

/// 例程关系图（台账 174，OB-F2 降维版；DESIGN §391）：
/// 定时任务的只读关系图——左列任务节点、右列投递目标
/// 节点、连线表「任务投递到目标」。点任务节点进既有详
/// 情页；点目标节点高亮投递到它的全部任务（再点取消）。
/// 桌面节点画布不移植：无拖拽、无缩放、无编辑——图数
/// 据走 Core CronRelationGraph 单源组装，本面只呈现。
struct CronRelationGraphView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedTargetID: String?

    private var store: CronStore { appState.sharedCronStore() }
    private var jobs: [CronJob] { store.jobs }
    private var graph: CronRelationGraph {
        CronRelationGraph.build(jobs: jobs)
    }

    /// 节点行高与行距（布局常量：连线坐标由行序纯算，
    /// 不测量、不回写）
    private static let nodeHeight: CGFloat = 52
    private static let nodeGap: CGFloat = 12
    private static var rowUnit: CGFloat { nodeHeight + nodeGap }

    var body: some View {
        ScrollView {
            if jobs.isEmpty {
                ODEmptyState(
                    "还没有定时任务",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: "新建定时任务后，这里会画出任务与投递目标的关系。"
                )
                .padding(.top, OneDayMetrics.spacingXXL)
            } else {
                graphCanvas
                    .padding(.horizontal, OneDayMetrics.pageGutter)
                    .padding(.vertical, OneDayMetrics.spacingM)
            }
        }
        .background(Palette.pageBG)
        .navigationTitle("关系图")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadIfNeeded() }
    }

    private var graphCanvas: some View {
        let graph = self.graph
        let rows = max(jobs.count, graph.targets.count)
        let height = CGFloat(rows) * Self.rowUnit - Self.nodeGap
        return GeometryReader { proxy in
            let jobColumnWidth = proxy.size.width * 0.56
            let targetX = proxy.size.width * 0.68
            let targetWidth = proxy.size.width - targetX
            ZStack(alignment: .topLeading) {
                edgesLayer(
                    graph: graph,
                    jobRightX: jobColumnWidth,
                    targetLeftX: targetX,
                    height: height
                )
                ForEach(Array(jobs.enumerated()), id: \.element.id) {
                    index, job in
                    jobNode(job)
                        .frame(
                            width: jobColumnWidth,
                            height: Self.nodeHeight
                        )
                        .offset(y: CGFloat(index) * Self.rowUnit)
                }
                ForEach(
                    Array(graph.targets.enumerated()), id: \.element.id
                ) { index, target in
                    targetNode(target)
                        .frame(
                            width: targetWidth,
                            height: Self.nodeHeight
                        )
                        .offset(
                            x: targetX,
                            y: CGFloat(index) * Self.rowUnit
                        )
                }
            }
        }
        .frame(height: height)
    }

    /// 连线层：每条边自任务右缘中点曲线到目标左缘中点；
    /// 选中目标时只亮它的边，其余边降透明
    private func edgesLayer(
        graph: CronRelationGraph,
        jobRightX: CGFloat, targetLeftX: CGFloat, height: CGFloat
    ) -> some View {
        let jobIndex = Dictionary(
            uniqueKeysWithValues: jobs.enumerated().map {
                ($0.element.id, $0.offset)
            }
        )
        let targetIndex = Dictionary(
            uniqueKeysWithValues: graph.targets.enumerated().map {
                ($0.element.id, $0.offset)
            }
        )
        return Canvas { context, size in
            for edge in graph.edges {
                guard let ji = jobIndex[edge.jobID],
                      let ti = targetIndex[edge.targetID] else {
                    continue
                }
                let start = CGPoint(
                    x: jobRightX,
                    y: CGFloat(ji) * Self.rowUnit + Self.nodeHeight / 2
                )
                let end = CGPoint(
                    x: targetLeftX,
                    y: CGFloat(ti) * Self.rowUnit + Self.nodeHeight / 2
                )
                var path = Path()
                path.move(to: start)
                path.addCurve(
                    to: end,
                    control1: CGPoint(
                        x: start.x + (end.x - start.x) * 0.5,
                        y: start.y
                    ),
                    control2: CGPoint(
                        x: start.x + (end.x - start.x) * 0.5,
                        y: end.y
                    )
                )
                let isSelected = selectedTargetID == nil
                    || selectedTargetID == edge.targetID
                context.stroke(
                    path,
                    with: .color(
                        Palette.inkMuted.opacity(
                            isSelected ? 0.55 : 0.15
                        )
                    ),
                    lineWidth: 1.5
                )
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func jobNode(_ job: CronJob) -> some View {
        let dimmed = selectedTargetID != nil
            && graph.edges.first { $0.jobID == job.id }?.targetID
                != selectedTargetID
        return NavigationLink {
            CronJobDetailView(job: job) {
                Task { await store.refresh() }
            }
        } label: {
            HStack(spacing: OneDayMetrics.spacingS) {
                StatusDot(
                    color: job.enabled
                        ? Palette.success : Palette.inkMuted
                )
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingMicro
                ) {
                    Text(job.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(job.scheduleText)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .frame(height: Self.nodeHeight)
            .background(
                Palette.surface,
                in: RoundedRectangle(
                    cornerRadius: OneDayMetrics.radiusCard
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: OneDayMetrics.radiusCard
                )
                .stroke(Palette.hairline, lineWidth: 0.5)
            }
            .opacity(dimmed ? 0.4 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    private func targetNode(
        _ target: CronRelationGraph.Target
    ) -> some View {
        let isSelected = selectedTargetID == target.id
        return Button {
            selectedTargetID = isSelected ? nil : target.id
        } label: {
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingMicro
            ) {
                Text(target.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text("\(target.jobIDs.count) 个任务")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .frame(
                maxWidth: .infinity, alignment: .leading
            )
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .frame(height: Self.nodeHeight)
            .background(
                isSelected ? Palette.selectionFill : Palette.surface,
                in: RoundedRectangle(
                    cornerRadius: OneDayMetrics.radiusCard
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: OneDayMetrics.radiusCard
                )
                .stroke(
                    isSelected ? Palette.inkMuted : Palette.hairline,
                    lineWidth: isSelected ? 1 : 0.5
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(
            "投递目标 \(target.label)，\(target.jobIDs.count) 个任务"
        )
    }
}
