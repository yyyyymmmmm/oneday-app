import OneDayCore
import OneDayDesign
import SwiftUI

/// 服务器地址字段行（台账 198 收敛 S3）：连接页与
/// 服务器详情页共用——FieldRow（标签＋聚焦高亮）＋
/// URL 输入（关自动大写/自动更正、URL 键盘）。此前
/// 两页各写一份同构行、聚焦态管理各行其是（连接页
/// 一套 Field 枚举 FocusState、详情页无聚焦态），自
/// 此聚焦归本件自持、两页同口径。
struct ServerAddressFieldRow: View {
    @Binding var text: String
    var placeholder: String = "https://hermes.didichou.site"

    @FocusState private var isFocused: Bool

    var body: some View {
        FieldRow(label: "服务器地址", isActive: isFocused) {
            TextField(placeholder, text: $text)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
        }
    }
}

/// 服务器秘密字段行（台账 198 收敛 S3）：密码/网关
/// 密钥共用——FieldRow＋SecureField＋行尾显隐切换
/// （眼睛钮，minTapTarget 热区）。收编前两页各有一
/// 套：连接页 secretField（页级 revealSecret＋eye
/// 钮）与详情页密钥行（showAPIKey＋文字钮「显示/
/// 隐藏」），显隐状态与切换形态各行其是；自此显隐
/// 归本件自持、切换统一 eye 钮、两页同口径。
/// demoObscured：演示模式下秘密不落真值——切换钮
/// 隐藏、框内只显等长圆点占位（原连接页演示口径：
/// 程序化给 SecureField 赋的值在模拟器里不渲染圆
/// 点且行高异常，0.1.3 截图实证，收编保留）。
struct ServerSecretFieldRow: View {
    let label: String
    @Binding var text: String
    var placeholder: String
    var demoObscured = false

    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        FieldRow(label: label, isActive: isFocused) {
            if demoObscured {
                Text(String(repeating: "•", count: 12))
            } else {
                HStack(spacing: OneDayMetrics.spacingS) {
                    Group {
                        if isRevealed {
                            TextField(placeholder, text: $text)
                        } else {
                            SecureField(placeholder, text: $text)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .font(.system(size: FrameworkIcon.actionGlyphSize))
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(
                                width: OneDayMetrics.minTapTarget,
                                height: OneDayMetrics.minTapTarget
                            )
                    }
                    .accessibilityLabel(isRevealed ? "隐藏" : "显示")
                }
            }
        }
    }
}
