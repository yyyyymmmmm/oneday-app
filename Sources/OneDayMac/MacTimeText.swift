import Foundation

/// 时间呈现小件（棒 3）：epoch 秒 → 本地人话时间，
/// 各面共用，不逐面另写一套格式
enum MacTimeText {
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private static let fullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func short(_ epoch: Double) -> String {
        guard epoch > 0 else { return "" }
        return dateTimeFormatter.string(
            from: Date(timeIntervalSince1970: epoch)
        )
    }

    static func full(_ epoch: Double) -> String {
        guard epoch > 0 else { return "" }
        return fullFormatter.string(
            from: Date(timeIntervalSince1970: epoch)
        )
    }

    static func full(_ epoch: Double?) -> String {
        guard let epoch else { return "未记录" }
        return full(epoch)
    }
}
