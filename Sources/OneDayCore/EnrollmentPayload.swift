import Foundation

/// 连接二维码载荷（配对一期，台账 153/160）：已登录
/// 设备在「设置 → 添加设备」生成、新设备在连接页扫
/// 码认领。载荷只带三件事——去哪领（服务器地址，归
/// 一化走 ServerConfig 单源）、领什么（一次性认领
/// 码）、对谁领（服务器实例指纹，认领回执须对上、
/// 防码被搬去另一台服务器兑现）。版本 v 备载荷演
/// 进，非当前版本一律拒。
public struct EnrollmentPayload: Equatable, Sendable {
    public static let currentVersion = 1
    /// 认领码形态（与服务端认领存储同口径：20 字符）
    public static let codeLength = 20
    /// 实例指纹形态（sha256 前 16 位十六进制）
    public static let fingerprintLength = 16

    public let config: ServerConfig
    public let code: String
    public let fingerprint: String

    public init(config: ServerConfig, code: String, fingerprint: String) {
        self.config = config
        self.code = code
        self.fingerprint = fingerprint
    }

    /// 出码侧组装（设置「添加设备」面）：紧凑 JSON，
    /// 键序固定便于人眼对码
    public func qrString() -> String {
        let object: [String: Any] = [
            "v": Self.currentVersion,
            "url": config.baseString,
            "code": code,
            "fp": fingerprint,
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys]
        ), let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    /// 扫码侧解析：不是本载荷形态（非 JSON／版本不
    /// 对／字段缺失／地址归一化失败／码与指纹形态不
    /// 对）一律返回 nil，呈现层给「不是 OneDay 连接
    /// 二维码」的人话提示
    public static func parse(_ raw: String) -> EnrollmentPayload? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              let version = dict["v"] as? Int,
              version == currentVersion,
              let urlText = dict["url"] as? String,
              let config = ServerConfig(rawInput: urlText),
              let code = dict["code"] as? String,
              code.count == codeLength,
              code.allSatisfy({ $0.isLetter || $0.isNumber }),
              let fingerprint = dict["fp"] as? String,
              fingerprint.count == fingerprintLength,
              fingerprint.allSatisfy({ $0.isHexDigit })
        else { return nil }
        return EnrollmentPayload(
            config: config, code: code, fingerprint: fingerprint
        )
    }
}
