import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 语音输入视图面（0.36.6，DESIGN-V4 §71）：录音条
/// （占住发送舱同一玻璃胶囊：文本行在上、控制行在
/// 下——与发送舱多行形态同构，不新造高度轴）与权限
/// 预备页。字幕直进既有 ComposerTextView、未定稿尾
/// 段染灰；波形由真实电平驱动

/// 录音条：✕ 取消（丢本次段）／波形＋计时／✓ 停录
/// 落稿。准备中相位中部换进度呈现
struct DictationBar: View {
    var controller: DictationController
    @Binding var text: String
    var focusHandle: ComposerFocusHandle
    var caretColor: UIColor
    var reduceMotion: Bool

    var body: some View {
        VStack(spacing: OneDayMetrics.spacingS) {
            ComposerTextView(
                text: $text,
                focusHandle: focusHandle,
                onFocusChange: { _ in },
                caretColor: caretColor,
                volatileTailLength: controller.volatileLength,
                placeholderText: "正在聆听…"
            )
            if controller.showSilenceHint,
               controller.phase == .recording {
                Text("还没听到声音，把手机拿近一点试试")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            HStack(alignment: .center) {
                cancelButton
                Spacer(minLength: OneDayMetrics.spacingM)
                centerCluster
                Spacer(minLength: OneDayMetrics.spacingM)
                doneButton
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var cancelButton: some View {
        Button {
            controller.cancel()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.ink)
                .frame(
                    width: ComposerLayout.buttonHeight,
                    height: ComposerLayout.buttonHeight
                )
                .background(Palette.fieldFill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel("取消语音输入")
    }

    private var doneButton: some View {
        Button {
            controller.stopAndCommit()
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.onPrimary)
                .frame(
                    width: ComposerLayout.buttonHeight,
                    height: ComposerLayout.buttonHeight
                )
                .background(Palette.primaryPale, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.odPressable)
        .disabled(controller.phase != .recording)
        .opacity(controller.phase == .recording ? 1 : 0.4)
        .accessibilityLabel("停止录音，把文字填入输入框")
    }

    @ViewBuilder
    private var centerCluster: some View {
        if controller.phase == .preparing {
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text(controller.assetProgress > 0
                    ? "正在准备语音模型 "
                        + "\(Int(controller.assetProgress * 100))%"
                    : "正在准备语音模型…")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        } else {
            HStack(spacing: OneDayMetrics.spacingSM) {
                if reduceMotion {
                    levelBar
                } else {
                    waveform
                }
                Text(DictationTiming.format(
                    elapsedSeconds: controller.elapsedSeconds))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(controller.isTimingWarning
                        ? Palette.warning : Palette.inkSecondary)
            }
        }
    }

    /// 9 根竖条：高度只由真实电平采样决定（Core 波
    /// 形环），无电平即平线——不许假动画
    private var waveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(
                Array(controller.waveformBars.enumerated()),
                id: \.offset
            ) { _, value in
                Capsule()
                    .fill(Palette.ink)
                    .frame(width: 3, height: 4 + value * 14)
            }
        }
        .frame(height: 18)
        .animation(.linear(duration: 0.12), value: controller.waveformBars)
        .accessibilityHidden(true)
    }

    /// Reduce Motion 降级：单条横向电平尺（规格 §3.2）
    private var levelBar: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Palette.fieldFill)
                .frame(width: 72, height: 4)
            Capsule()
                .fill(Palette.ink)
                .frame(width: 72 * controller.level, height: 4)
        }
        .accessibilityHidden(true)
    }
}

/// 权限预备页（续编 S1–S4：问前先讲用途、语言同页
/// 选）：点「开始使用」才触发系统弹窗；被拒后的降
/// 级路（键盘听写）同页明示。0.36.8：权限只剩麦克
/// 风一件——SpeechAnalyzer 路线官方口径不需要语音
/// 识别授权，原「语音识别」行整行删除
struct DictationPrepSheet: View {
    @Bindable var controller: DictationController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
                VStack(spacing: OneDayMetrics.spacingSM) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(Palette.onPrimary)
                        .frame(width: 64, height: 64)
                        .background(Palette.primaryPale, in: Circle())
                    Text("用说话来输入")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Text("点一下麦克风，说话就会变成文字填进输入框。"
                    + "填好后你可以改完再发，不会自动发送。")
                    .font(.body)
                    .foregroundStyle(Palette.ink)

                VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                    Label {
                        Text("识别在你的 iPhone 本机完成，录音不会上传服务器")
                    } icon: {
                        Image(systemName: "iphone")
                    }
                    Label {
                        Text("需要开麦克风：把你说的话录下来")
                    } icon: {
                        Image(systemName: "mic")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)

                VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                    Text("识别语言")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    ForEach(DictationLanguage.allCases, id: \.rawValue) {
                        language in
                        Button {
                            controller.language = language
                        } label: {
                            HStack {
                                Text(language.displayName)
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                if controller.language == language {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Palette.primary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.odPressable)
                    }
                }

                Button("开始使用") {
                    controller.prepConfirmStart()
                }
                .buttonStyle(.odPrimary)
                .padding(.top, OneDayMetrics.spacingS)

                Button("用键盘听写") {
                    controller.prepUseKeyboard()
                }
                .buttonStyle(.odPressable)
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundStyle(Palette.inkSecondary)

                Text("键盘听写：点输入框后，用键盘上的麦克风按钮也能说话输入，不需要这里的权限。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingM)
        }
        .presentationDragIndicator(.visible)
        .onDisappear { controller.prepDismissed() }
    }
}

/// 失败文案（三段式，续编 S10：发生了什么＋影响＋
/// 怎么办；零行话、零外文漏出）
func dictationFailureMessage(_ failure: DictationFailure) -> String {
    switch failure {
    case .permissionDenied:
        return "语音输入没开权限，暂时用不了。去设置里打开麦克风，或者直接打字、用键盘自带的听写。"
    case .nothingHeard:
        return "没有听清，请再试一次。靠近麦克风、说慢一点会更清楚。"
    case .interrupted:
        return "录音被打断了。识别到的内容已经保留在输入框里，可以接着说或直接改。"
    case .engineUnavailable:
        return "这台手机暂时用不了语音输入。用键盘自带的听写也能说话输入。"
    case .assetDownloadFailed:
        return "语音模型没下载成功，检查网络后再点麦克风重试。"
    case .engineError:
        return "识别中途出错了。已经识别出的内容保留在输入框里，可以再试一次。"
    }
}
