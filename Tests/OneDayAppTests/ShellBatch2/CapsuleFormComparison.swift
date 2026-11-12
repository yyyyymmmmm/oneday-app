import OneDayCore
import OneDayDesign
import SwiftUI

/// 症二 2a·胶囊形态对照实验辅助视图（2026-11-12）
///
/// **用途**：在真机/模拟器上并排展示两种胶囊形态，供手动
/// 点按扫描验证命中域行为。
///
/// **使用方法**：
/// 1. 在 OneDayApp 中临时添加此视图的 Preview 或创建测试入口
/// 2. 真机运行，对每种形态的胶囊全宽进行点按扫描
/// 3. 记录每个落点（相对胶囊左缘的 x 偏移）触发的动作
/// 4. 将结果填入 CapsuleHitTestScenarios 的测试用例
///
/// **扫描粒度**：每 8pt 一个采样点，覆盖头像、名字、状态、
/// 分隔线、模型短名、chevron 各区域
struct CapsuleFormComparison: View {
    @State private var hubTapCount = 0
    @State private var modelPickerTapCount = 0
    @State private var lastTappedForm: String = ""
    @State private var showModelPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Text("症二 2a·胶囊命中域对照实验")
                    .font(.title2.bold())
                    .padding(.top, 32)

                tapCounterDisplay

                Divider()

                // A 组：0.49.3 历史形态
                formSection(
                    title: "A 组：0.49.3 历史形态",
                    description: "原生 Menu + Picker，玻璃挂行本体",
                    capsuleView: { historicalCapsule_0_49_3 }
                )

                Divider()

                // B 组：0.50.22 现行形态
                formSection(
                    title: "B 组：0.50.22 现行形态",
                    description: "IdentityCapsuleView，两个独立 Button，玻璃在背景层",
                    capsuleView: { currentCapsule_0_50_22 }
                )

                instructionsSection
            }
            .padding(.horizontal, 20)
        }
        .background(Palette.chatSurface.ignoresSafeArea())
        .sheet(isPresented: $showModelPicker) {
            modelPickerSheet
        }
    }

    // MARK: - 计数器显示

    private var tapCounterDisplay: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                counterBadge(
                    label: "枢纽",
                    count: hubTapCount,
                    color: .blue
                )
                counterBadge(
                    label: "模型",
                    count: modelPickerTapCount,
                    color: .green
                )
            }
            if !lastTappedForm.isEmpty {
                Text("上次点按：\(lastTappedForm)")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Button("重置计数") {
                hubTapCount = 0
                modelPickerTapCount = 0
                lastTappedForm = ""
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(Palette.pageBG)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func counterBadge(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
        }
        .frame(width: 80)
    }

    // MARK: - 形态展示区

    private func formSection<Content: View>(
        title: String,
        description: String,
        @ViewBuilder capsuleView: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)

            HStack {
                Spacer()
                capsuleView()
                Spacer()
            }
            .padding(.vertical, 20)
        }
        .padding()
        .background(Palette.pageBG)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - A 组：0.49.3 历史形态（复刻）

    /// 0.49.3 capsuleRow 复刻（git show 9be8818）
    /// - 身份域：Button { showHub = true }
    /// - 模型域：原生 Menu { Picker(...) }
    /// - 玻璃：.glassEffect(.regular) 直接挂行本体
    private var historicalCapsule_0_49_3: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            // 身份域 Button
            Button {
                recordTap(form: "A 组（0.49.3）", action: "枢纽")
            } label: {
                HStack(spacing: OneDayMetrics.spacingS) {
                    Circle()
                        .fill(.blue.gradient)
                        .frame(width: 28, height: 28)
                    Text("Hermes")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    HStack(spacing: OneDayMetrics.iconTextGap) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("空闲")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)

            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 0.5, height: 18)

            // 模型域：原生 Menu（0.49.3 形态）
            Menu {
                Picker("模型", selection: .constant("gpt-4o")) {
                    Text("GPT-4o").tag("gpt-4o")
                    Text("Claude 3.5 Sonnet").tag("claude-3.5-sonnet")
                    Text("Gemini 2.0 Flash").tag("gemini-2.0-flash")
                }
            } label: {
                HStack(spacing: OneDayMetrics.stackGap) {
                    Text("4o")
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.inkSecondary)
                }
                .contentShape(Rectangle())
            }
            // 注：Menu 的点按会触发系统菜单，不会触发我们的计数器
            // 这是 0.49.3 的真实行为
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, 7)
        // 0.49.3 形态：玻璃直接挂行本体
        .glassEffect(.regular, in: Capsule())
    }

    // MARK: - B 组：0.50.22 现行形态

    /// 0.50.22 IdentityCapsuleView 形态
    /// - 身份域：Button { onOpenHub() }
    /// - 模型域：Button { onOpenModelPicker() }
    /// - 玻璃：.background { Capsule()...glassEffect }（§179 降背景层）
    private var currentCapsule_0_50_22: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            // 身份域 Button
            Button {
                recordTap(form: "B 组（0.50.22）", action: "枢纽")
            } label: {
                HStack(spacing: OneDayMetrics.spacingS) {
                    Circle()
                        .fill(.blue.gradient)
                        .frame(width: 28, height: 28)
                    Text("Hermes")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    HStack(spacing: OneDayMetrics.iconTextGap) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("空闲")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)

            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 0.5, height: 18)

            // 模型域：Button（§153 后的形态）
            Button {
                recordTap(form: "B 组（0.50.22）", action: "模型")
            } label: {
                HStack(spacing: OneDayMetrics.stackGap) {
                    Text("4o")
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.inkSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, 7)
        // §179 形态：玻璃降背景层
        .background {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: Capsule())
        }
    }

    // MARK: - 辅助

    private func recordTap(form: String, action: String) {
        lastTappedForm = "\(form) - \(action)"
        if action == "枢纽" {
            hubTapCount += 1
        } else if action == "模型" {
            modelPickerTapCount += 1
            showModelPicker = true
        }
    }

    private var modelPickerSheet: some View {
        NavigationStack {
            List {
                Text("GPT-4o")
                Text("Claude 3.5 Sonnet")
                Text("Gemini 2.0 Flash")
            }
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        showModelPicker = false
                    }
                }
            }
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("扫描指引")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("1. 对每种形态的胶囊，从左缘到右缘每隔 8pt 点按一次")
                Text("2. 观察上方计数器，记录每个落点触发的动作")
                Text("3. 特别关注：")
                    .fontWeight(.semibold)
                Text("   • 身份域（头像/名字/状态）是否都触发枢纽")
                Text("   • 模型域（分隔线右侧）是否都触发模型选择")
                Text("   • 0.5pt 分隔线附近的行为")
                Text("   • 胶囊上缘（靠近状态栏）的点按是否异常")
                    .foregroundStyle(.red)
            }
            .font(.caption)
            .foregroundStyle(Palette.inkSecondary)

            Text("4. 将实测结果填入 CapsuleHitTestScenarios.swift")
                .font(.caption)
                .foregroundStyle(Palette.inkMuted)
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 32)
    }
}

#if DEBUG
#Preview("胶囊形态对照") {
    CapsuleFormComparison()
}
#endif
