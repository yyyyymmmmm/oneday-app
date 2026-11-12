import OneDayCore
import OneDayDesign
import SwiftUI

/// 症二 2b·呈现层级观察辅助视图（2026-11-12）
///
/// **用途**：在真机上触发模型 sheet／枢纽 cover，观察
/// 呈现层级与系统栏遮挡关系。
///
/// **使用方法**：
/// 1. 在真机运行此视图
/// 2. 点击按钮触发模型 sheet 或枢纽 cover
/// 3. 观察并记录：
///    - 呈现面是否完整盖住背景内容
///    - 状态栏是否可见/穿透
///    - 坞是否隐藏/穿透
///    - 输入栏是否被盖住
///    - 背景参照线是否可见（用于判断穿透）
/// 4. 截图记录异常现象
/// 5. 将观察结果填入 PresentationLayerScenarios.swift
struct PresentationLayerObservation: View {
    @State private var showModelPicker = false
    @State private var showHub = false
    @State private var observationLog: [String] = []

    var body: some View {
        ZStack {
            // 背景参照层（用于观察穿透）
            backgroundReferenceLayer

            VStack(spacing: 20) {
                Text("症二 2b·呈现层级观察")
                    .font(.title2.bold())
                    .padding(.top, 60)

                observationLogSection

                Spacer()

                // 触发按钮区
                triggerButtonsSection

                Spacer()

                // 边界参照标记
                boundaryMarkers
            }
            .padding(.horizontal, 20)
        }
        .sheet(isPresented: $showModelPicker) {
            modelPickerSheet
        }
        .fullScreenCover(isPresented: $showHub) {
            hubCoverMock
        }
    }

    // MARK: - 背景参照层

    /// 背景参照层：彩色网格，用于观察呈现面是否穿透
    private var backgroundReferenceLayer: some View {
        ZStack {
            // 底色
            LinearGradient(
                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // 网格线
            VStack(spacing: 40) {
                ForEach(0..<20, id: \.self) { _ in
                    Rectangle()
                        .fill(.white.opacity(0.3))
                        .frame(height: 2)
                }
            }
            .ignoresSafeArea()

            // 四角标记
            VStack {
                HStack {
                    cornerMarker(position: "左上", color: .red)
                    Spacer()
                    cornerMarker(position: "右上", color: .green)
                }
                Spacer()
                HStack {
                    cornerMarker(position: "左下", color: .blue)
                    Spacer()
                    cornerMarker(position: "右下", color: .orange)
                }
            }
            .padding(20)
            .ignoresSafeArea()
        }
    }

    private func cornerMarker(position: String, color: Color) -> some View {
        VStack {
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)
            Text(position)
                .font(.caption2)
                .foregroundStyle(color)
        }
    }

    // MARK: - 观察日志

    private var observationLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("观察记录")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if observationLog.isEmpty {
                        Text("点击下方按钮触发呈现面")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    } else {
                        ForEach(observationLog.indices, id: \.self) { index in
                            Text("\(index + 1). \(observationLog[index])")
                                .font(.caption)
                                .foregroundStyle(Palette.ink)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 120)

            Button("清空日志") {
                observationLog.removeAll()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(Palette.pageBG.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func logObservation(_ text: String) {
        observationLog.append(text)
    }

    // MARK: - 触发按钮区

    private var triggerButtonsSection: some View {
        VStack(spacing: 16) {
            Text("触发呈现面")
                .font(.headline)

            Button {
                logObservation("触发模型选择 sheet")
                showModelPicker = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.largeTitle)
                    Text("模型选择面 (sheet)")
                        .font(.callout)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button {
                logObservation("触发枢纽 fullScreenCover")
                showHub = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "cube.fill")
                        .font(.largeTitle)
                    Text("枢纽面 (fullScreenCover)")
                        .font(.callout)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Palette.pageBG.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 边界参照标记

    private var boundaryMarkers: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("边界参照")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                markerRow(icon: "antenna.radiowaves.left.and.right", label: "状态栏区域", color: .yellow)
                markerRow(icon: "square.grid.3x3.fill", label: "坞区域（底部 ~80pt）", color: .orange)
                markerRow(icon: "keyboard", label: "输入栏区域（若存在）", color: .cyan)
            }
            .font(.caption)

            Text("观察要点：呈现面是否盖住背景网格与四角标记")
                .font(.caption2)
                .foregroundStyle(Palette.inkTertiary)
                .padding(.top, 4)
        }
        .padding()
        .background(Palette.pageBG.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 20)
    }

    private func markerRow(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(label)
                .foregroundStyle(Palette.ink)
        }
    }

    // MARK: - 模拟呈现面

    private var modelPickerSheet: some View {
        NavigationStack {
            ZStack {
                // 半透明背景，用于观察是否穿透
                Color.white.opacity(0.95)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    Text("模型选择面 (sheet)")
                        .font(.title2.bold())

                    Text("观察项：")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("✓ 背景网格与四角标记是否完全被盖住")
                        Text("✓ 状态栏是否可见（正常）")
                        Text("✓ 坞是否隐藏或穿透")
                        Text("✓ sheet 边缘是否有异常间隙")
                    }
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Palette.pageBG)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    List {
                        Text("GPT-4o")
                        Text("Claude 3.5 Sonnet")
                        Text("Gemini 2.0 Flash")
                    }
                    .frame(height: 200)
                }
                .padding()
            }
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        logObservation("关闭模型 sheet")
                        showModelPicker = false
                    }
                }
            }
        }
    }

    private var hubCoverMock: some View {
        ZStack {
            // 全屏半透明背景
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("枢纽面 (fullScreenCover)")
                    .font(.title.bold())
                    .foregroundStyle(.white)

                Text("观察项：")
                    .font(.headline)
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 8) {
                    Text("✓ 背景网格与四角标记是否完全被盖住")
                    Text("✓ 坞是否完全隐藏")
                    Text("✓ 状态栏是否可见（正常）")
                    Text("✓ 内容是否触及屏幕边缘")
                }
                .font(.callout)
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    logObservation("关闭枢纽 cover")
                    showHub = false
                } label: {
                    Text("关闭")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 40)
            }
            .padding()
        }
    }
}

#if DEBUG
#Preview("呈现层级观察") {
    PresentationLayerObservation()
}
#endif
