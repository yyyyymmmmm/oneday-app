#!/usr/bin/env swift
// §405.5 底栏模板图资产 —— 官方导出流程记录＋装配校验
//
// 【资产正道（2026-11-23 改判，DESIGN §405.5）】
// 五枚底栏资产一律取自苹果官方 SF Symbols 应用的导出，
// 朝向由官方工具按构造保证，不经任何自研坐标变换：
//   1. 安装 SF Symbols（本机已装 7.2：~/build 下
//      sf-symbols-7.dmg 内的 SF Symbols.pkg 解包，
//      Payload 的 SF Symbols.app 入 /Applications）；
//   2. 应用内切「列表视图」，工具栏粗细设「细体」
//      （Light）；
//   3. 逐符号搜索精确名、选中行，菜单 编辑 →
//      「将图像拷贝为…」：格式 SVG、点大小 24、符号
//      缩放 中，拷贝后把剪贴板 SVG 存入
//      ~/build/tab-assets-svg/<key>.svg；
//      注：feed 的官名是 text.document（doc.text 是
//      其别名，App 侧引用名不变）；文件菜单的「导出
//      模板／导出符号」只对自定义符号启用，系统库符
//      号的官方导出即此「拷贝为」路径；
//   4. 在仓库根跑本脚本：把 staging 的 SVG 装入各
//      imageset 并校验来源标记与 viewBox 几何。
//
// 【退役路线】v1–v4 的 CoreUI .car 私有接口提取生成器
// 已按 §405.5 退役（其一：CoreGlyphs 的 CGPath 处翻
// 转坐标系，PDF 直存即竖直翻转——0.50.100 真机实证；
// 其二：用户 2026-11-23 亲点改走官方导出、自研量测
// 路线作废）。旧生成器全文在 git 历史（rel-05100 与
// 本分支首笔提交）。本脚本不再做任何像素对账：朝向
// 验收＝结构特征钉（测试套）＋用户真机冷启 verdict。
import Foundation

let staging = ProcessInfo.processInfo.environment["TAB_ASSET_SVG_DIR"]
    ?? NSString(string: "~/build/tab-assets-svg").expandingTildeInPath
let catalog = "App/Resources/Assets.xcassets"

/// key、符号官名、官方导出 viewBox（pt）
let specs: [(key: String, symbol: String, w: Double, h: Double)] = [
    ("chat", "message", 22.61, 19.9504),
    ("feed", "text.document", 16.5086, 20.8188),
    ("ideas", "lightbulb", 13.1644, 23.1),
    ("goals", "checklist", 21.935, 19.6953),
    ("files", "tray", 27.7955, 19.5188),
]

var failures = 0
for spec in specs {
    let src = "\(staging)/\(spec.key).svg"
    let dst = "\(catalog)/tab.\(spec.key).imageset/tab.\(spec.key).svg"
    guard let svg = try? String(contentsOfFile: src, encoding: .utf8) else {
        print("FAIL \(spec.key): staging 缺 \(src)（先按头部流程导出）")
        failures += 1
        continue
    }
    guard svg.contains("Apple Native CoreSVG") else {
        print("FAIL \(spec.key): 无官方 CoreSVG 生成标记，来源不合")
        failures += 1
        continue
    }
    // viewBox="0 0 W H" 解析对账（导出几何＝设计几何）
    var ok = false
    if let r = svg.range(of: "viewBox=\"0 0 ") {
        let tail = svg[r.upperBound...]
        let nums = tail.prefix(while: { $0 != "\"" })
            .split(separator: " ")
            .compactMap { Double($0) }
        if nums.count == 2 {
            ok = abs(nums[0] - spec.w) < 0.01
                && abs(nums[1] - spec.h) < 0.01
        }
    }
    guard ok else {
        print("FAIL \(spec.key): viewBox 与官方导出几何不符")
        failures += 1
        continue
    }
    do {
        try svg.write(toFile: dst, atomically: true, encoding: .utf8)
        print("OK \(spec.key) (\(spec.symbol)) viewBox "
            + "\(spec.w)x\(spec.h) -> \(dst)")
    } catch {
        print("FAIL \(spec.key): 写入 \(dst) 失败 \(error)")
        failures += 1
    }
}
if failures > 0 {
    print("DONE WITH \(failures) FAILURES")
    exit(1)
}
print("DONE all 5 official-export assets installed")
