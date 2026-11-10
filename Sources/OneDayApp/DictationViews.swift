import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 语音输入视图面（0.36.6，DESIGN-V4 §71）：录音条
/// （占住发送舱同一玻璃胶囊）与权限预备页。
/// 0.36.17 改判（DESIGN-V4 §82，用户 23:48 照 Muse
/// 听写条定版）：录音条只剩一行控制行——左废弃／
/// 中音波＋计时／右停与发送两钮；录时零文字（文本
/// 行与实时诊断行整组撤下），波形由真实电平驱动

/// 录音条（0.36.17 形态）：垃圾桶废弃（丢本次段与
/// 已得文本）／波形＋计时／■ 停（落稿进输入框）／
/// ↑ 发送（落定直发）。准备中中部换模型进度、整理
/// 中换「正在整理…」；三钮可用性走 Core 的
/// DictationBarPolicy 单点表，视图不自判
struct DictationBar: View {
    var controller: DictationController
    var reduceMotion: Bool

    private var controls: DictationBarPolicy.Controls {
        DictationBarPolicy.controls(for: controller.phase)
    }

    var body: some View {
        VStack(spacing: OneDayMetrics.spacingS) {
            HStack(alignment: .center) {
                discardButton
                Spacer(minLength: OneDayMetrics.spacingM)
                centerCluster
                Spacer(minLength: OneDayMetrics.spacingM)
                stopButton
                sendButton
            }
            if controller.showSilenceHint,
               controller.phase == .recording {
                Text("还没听到声音，把手机拿近一点试试")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var discardButton: some View {
        Button {
            controller.cancel()
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(
                    width: ComposerLayout.buttonHeight,
                    height: ComposerLayout.buttonHeight
                )
                .background(Palette.fieldFill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.odPressable)
        .disabled(!controls.discardEnabled)
        .opacity(controls.discardEnabled ? 1 : 0.4)
        .accessibilityLabel("丢弃本次录音")
    }

    private var stopButton: some View {
        Button {
            controller.stopAndCommit()
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(
                    width: ComposerLayout.buttonHeight,
                    height: ComposerLayout.buttonHeight
                )
                .background(Palette.fieldFill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.odPressable)
        .disabled(!controls.stopEnabled)
        .opacity(controls.stopEnabled ? 1 : 0.4)
        .accessibilityLabel("停止录音，把文字填入输入框")
    }

    private var sendButton: some View {
        Button {
            controller.stopAndSend()
        } label: {
            Image(systemName: "arrow.up")
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
        .disabled(!controls.sendEnabled)
        .opacity(controls.sendEnabled ? 1 : 0.4)
        .accessibilityLabel("停止录音并发送")
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
        } else if controller.phase == .finishing {
            // 整理中（0.36.17）：停/发送已按下、终稿
            // 未落定——final 交付可达数秒，条上必须
            // 有明确在办的信号，不许假死无反馈
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text("正在整理…")
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

                Text("点一下麦克风，说完点「停」，文字会填进输入框，"
                    + "改完再发；点「发送」则停录后直接发出去。")
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

                DictationStageDiagnosticLine()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, OneDayMetrics.spacingS)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingM)
        }
        .presentationDragIndicator(.visible)
        .onDisappear { controller.prepDismissed() }
    }
}

/// 诊断行（0.36.9，礼记同案后手）：末阶段面包屑
/// 上屏——闪退后用户重开截一张图即知上次死在哪一
/// 步，不再靠猜。阶段码是内部记号、非用户文案，
/// 故整行明标「诊断信息」以别于正文口径
/// 0.36.12 扩串：同行附诊断串（引擎种类＋规范化
/// locale＋草稿/定稿计数）——「实时不出字」下次录
/// 屏截一张图即可读出：实际跑的哪个引擎、草稿到
/// 底到没到（vol＞0）还是全程只有定稿（vol＝0）
/// 0.36.13：串内加四格（预设/sup/inst/avail，见
/// DictationController 仪表四格注）；同批曾在录音
/// 条上加实时版一行（录音成功时本行不在场、用户
/// 看不见——22:26 录屏实证后补）。0.36.17 改判：
/// 实时版整组撤下（录音条零文字），本行回归唯一
/// 诊断面载体（预备页页脚＋失败行），串内另加
/// 「落字+…ms」（停后落字，fastResults 记账位）
struct DictationStageDiagnosticLine: View {
    var body: some View {
        Text("诊断信息 · 上次语音停在："
            + (DictationController.lastStageSnapshot ?? "暂无记录")
            + diagSuffix)
            .font(.caption2)
            .foregroundStyle(Palette.inkSecondary)
    }

    private var diagSuffix: String {
        guard let diag = DictationController.lastDiagSnapshot
        else { return "" }
        return "｜" + diag
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
