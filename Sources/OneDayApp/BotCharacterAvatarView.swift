import SwiftUI

/// OpenBot 风格灵动角色头像渲染器：
/// 柔和渐变毛毡底色 + 可辨识几何轮廓（团子/猫耳/小熊/智械/嫩芽/星灵）+ 灵动双眸与微表情，
/// 供 `AgentAvatarEditorView` 实时预览与 `AgentProfileStore` 离屏渲染共用，保证全端视觉统一。
struct BotCharacterAvatarView: View {
    let presetID: String
    let diameter: CGFloat

    var body: some View {
        let spec = BotCharacterSpec.resolve(presetID)
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [spec.topColor, spec.bottomColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // 顶部高光晕，营造轻 3D 毛毡质感
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.32), .clear],
                        center: UnitPoint(x: 0.32, y: 0.24),
                        startRadius: 0,
                        endRadius: diameter * 0.55
                    )
                )

            // 轮廓装饰（耳朵 / 天线 / 嫩芽 / 光环）
            silhouetteAccent(spec)

            // 灵动五官（双眸 + 高光 + 微表情）
            faceFeatures(spec)
                .offset(y: diameter * 0.04)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }

    @ViewBuilder
    private func silhouetteAccent(_ spec: BotCharacterSpec) -> some View {
        switch spec.shape {
        case .blob:
            EmptyView()
        case .cat:
            HStack(spacing: diameter * 0.28) {
                catEar(color: spec.accentColor)
                    .rotationEffect(.degrees(-16))
                catEar(color: spec.accentColor)
                    .rotationEffect(.degrees(16))
            }
            .offset(y: -diameter * 0.29)
        case .bear:
            HStack(spacing: diameter * 0.34) {
                Circle()
                    .fill(spec.accentColor)
                    .frame(width: diameter * 0.22, height: diameter * 0.22)
                Circle()
                    .fill(spec.accentColor)
                    .frame(width: diameter * 0.22, height: diameter * 0.22)
            }
            .offset(y: -diameter * 0.27)
        case .bot:
            VStack(spacing: 0) {
                Circle()
                    .fill(.white.opacity(0.92))
                    .frame(width: diameter * 0.11, height: diameter * 0.11)
                RoundedRectangle(cornerRadius: diameter * 0.02)
                    .fill(.white.opacity(0.75))
                    .frame(width: diameter * 0.04, height: diameter * 0.10)
            }
            .offset(y: -diameter * 0.31)
        case .sprout:
            HStack(spacing: diameter * 0.02) {
                Capsule()
                    .fill(.white.opacity(0.88))
                    .frame(width: diameter * 0.16, height: diameter * 0.09)
                    .rotationEffect(.degrees(-28))
                Capsule()
                    .fill(.white.opacity(0.88))
                    .frame(width: diameter * 0.16, height: diameter * 0.09)
                    .rotationEffect(.degrees(28))
            }
            .offset(y: -diameter * 0.29)
        case .star:
            Image(systemName: "sparkle")
                .font(.system(size: diameter * 0.16, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .offset(x: diameter * 0.24, y: -diameter * 0.24)
        }
    }

    private func catEar(color: Color) -> some View {
        TriangleShape()
            .fill(color)
            .frame(width: diameter * 0.22, height: diameter * 0.18)
    }

    @ViewBuilder
    private func faceFeatures(_ spec: BotCharacterSpec) -> some View {
        VStack(spacing: diameter * 0.06) {
            HStack(spacing: diameter * 0.18) {
                eyeView(spec)
                eyeView(spec)
            }
            if spec.expression == .wink {
                Capsule()
                    .fill(.white.opacity(0.92))
                    .frame(width: diameter * 0.14, height: diameter * 0.045)
            } else {
                SmileArc()
                    .stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: max(1.5, diameter * 0.042), lineCap: .round))
                    .frame(width: diameter * 0.18, height: diameter * 0.08)
            }
        }
    }

    @ViewBuilder
    private func eyeView(_ spec: BotCharacterSpec) -> some View {
        ZStack(alignment: .topTrailing) {
            Capsule()
                .fill(Color(red: 0.09, green: 0.11, blue: 0.16))
                .frame(width: diameter * 0.10, height: diameter * 0.14)
            Circle()
                .fill(.white.opacity(0.95))
                .frame(width: diameter * 0.036, height: diameter * 0.036)
                .offset(x: -diameter * 0.018, y: diameter * 0.02)
        }
    }
}

struct BotCharacterSpec {
    enum ShapeKind {
        case blob, cat, bear, bot, sprout, star
    }
    enum ExpressionKind {
        case smile, wink
    }

    let shape: ShapeKind
    let expression: ExpressionKind
    let topColor: Color
    let bottomColor: Color
    let accentColor: Color
    let glowColor: Color

    static func resolve(_ presetID: String) -> BotCharacterSpec {
        switch presetID {
        case "blob-blue":
            return BotCharacterSpec(
                shape: .blob,
                expression: .smile,
                topColor: Color(red: 0.34, green: 0.65, blue: 1.0),
                bottomColor: Color(red: 0.18, green: 0.42, blue: 0.92),
                accentColor: Color.white.opacity(0.28),
                glowColor: Color(red: 0.25, green: 0.55, blue: 1.0)
            )
        case "cat-violet":
            return BotCharacterSpec(
                shape: .cat,
                expression: .smile,
                topColor: Color(red: 0.65, green: 0.44, blue: 0.99),
                bottomColor: Color(red: 0.45, green: 0.24, blue: 0.85),
                accentColor: Color.white.opacity(0.32),
                glowColor: Color(red: 0.56, green: 0.34, blue: 0.95)
            )
        case "bear-amber":
            return BotCharacterSpec(
                shape: .bear,
                expression: .smile,
                topColor: Color(red: 0.99, green: 0.72, blue: 0.25),
                bottomColor: Color(red: 0.90, green: 0.48, blue: 0.12),
                accentColor: Color.white.opacity(0.30),
                glowColor: Color(red: 0.96, green: 0.60, blue: 0.18)
            )
        case "bot-cyan":
            return BotCharacterSpec(
                shape: .bot,
                expression: .wink,
                topColor: Color(red: 0.16, green: 0.80, blue: 0.88),
                bottomColor: Color(red: 0.05, green: 0.56, blue: 0.72),
                accentColor: Color.white.opacity(0.32),
                glowColor: Color(red: 0.10, green: 0.72, blue: 0.84)
            )
        case "sprout-green":
            return BotCharacterSpec(
                shape: .sprout,
                expression: .smile,
                topColor: Color(red: 0.22, green: 0.84, blue: 0.55),
                bottomColor: Color(red: 0.07, green: 0.62, blue: 0.38),
                accentColor: Color.white.opacity(0.32),
                glowColor: Color(red: 0.14, green: 0.75, blue: 0.46)
            )
        case "star-pink":
            return BotCharacterSpec(
                shape: .star,
                expression: .smile,
                topColor: Color(red: 0.98, green: 0.45, blue: 0.68),
                bottomColor: Color(red: 0.84, green: 0.22, blue: 0.50),
                accentColor: Color.white.opacity(0.32),
                glowColor: Color(red: 0.94, green: 0.34, blue: 0.60)
            )
        case "blob-coral":
            return BotCharacterSpec(
                shape: .blob,
                expression: .wink,
                topColor: Color(red: 1.0, green: 0.49, blue: 0.35),
                bottomColor: Color(red: 0.88, green: 0.28, blue: 0.18),
                accentColor: Color.white.opacity(0.30),
                glowColor: Color(red: 0.96, green: 0.38, blue: 0.26)
            )
        case "bot-slate":
            return BotCharacterSpec(
                shape: .bot,
                expression: .smile,
                topColor: Color(red: 0.38, green: 0.45, blue: 0.56),
                bottomColor: Color(red: 0.18, green: 0.23, blue: 0.32),
                accentColor: Color.white.opacity(0.28),
                glowColor: Color(red: 0.30, green: 0.37, blue: 0.48)
            )
        default:
            return BotCharacterSpec(
                shape: .blob,
                expression: .smile,
                topColor: Color(red: 0.34, green: 0.65, blue: 1.0),
                bottomColor: Color(red: 0.18, green: 0.42, blue: 0.92),
                accentColor: Color.white.opacity(0.28),
                glowColor: Color(red: 0.25, green: 0.55, blue: 1.0)
            )
        }
    }
}

private struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SmileArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}
