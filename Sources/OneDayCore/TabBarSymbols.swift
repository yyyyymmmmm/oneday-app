import UIKit

/// 底栏字形（0.3.1 系统直渲路线，DESIGN-V4 §16）：
/// 0.2.9 的「确定性构造」（按 alpha 包围盒定标 pointSize
/// 生成 UIImage 再喂原生栏）真机仍不过——几何定标只管得
/// 住字形框高，管不住描边观感，且预渲染图进 TabView 后
/// 还要被二次缩放。本轮删尽预渲染：图直接由系统符号渲
/// 染器按定版 SymbolConfiguration 出（pointSize 22／
/// weight .regular／scale .medium），UITabBar 以符号图
/// 身份走系统管线渲染，最终度量归系统。本轮可钉的只有
/// 配置本身——单测（TabBarSymbolsTests）钉配置三值与
/// 符号清单，不再有任何 alpha 量高逻辑。
/// pointSize 22 的锚：0.2.9 口径对齐量得真机 Muse 字
/// 形 ≈21.7–22.3pt（取代早期 24 的粗量）。
public enum TabBarSymbols {
    /// 定版配置：字号（pt）。对齐 Muse 真机字形实测
    public static let pointSize: CGFloat = 22
    /// 定版配置：字重。Muse 为细线条 regular，不许加粗凑数
    public static let weight: UIImage.SymbolWeight = .regular
    /// 定版配置：符号缩放档
    public static let scale: UIImage.SymbolScale = .medium

    /// 四个底栏条目的系统符号名（与 ContentView 条目同序）。
    /// 四枚基础符号本身即目录中最轻的线条（outline）设
    /// 计：bubble 与 folder 另有 .fill 变体（§9 禁用在
    /// 案），无更细的 design variant 可换（§16 记档）。
    public static let names = [
        "bubble.left.and.bubble.right",
        "chart.line.uptrend.xyaxis",
        "folder",
        "slider.horizontal.3",
    ]

    /// 定版符号配置：全仓底栏符号只许从这一份出，
    /// 单测钉死其三值来源（pointSize／weight／scale）
    public static let configuration = UIImage.SymbolConfiguration(
        pointSize: pointSize, weight: weight, scale: scale
    )

    /// 按名取底栏图：系统符号渲染器按定版配置直出，
    /// 不做任何测量、定标或二次加工；模板渲染保证底栏
    /// .tint 墨色生效（0.2.7 教训）
    public static func image(named name: String) -> UIImage {
        (UIImage(systemName: name, withConfiguration: configuration)
            ?? UIImage()).withRenderingMode(.alwaysTemplate)
    }
}
