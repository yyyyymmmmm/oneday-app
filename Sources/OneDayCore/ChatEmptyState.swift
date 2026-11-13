import Foundation

/// 聊天空状态呈现政策（基础止血包 P9）：旧口径空
/// 状态只挂「当前无线程」（落地态）一支——已建的
/// 零条目线程（新建旁聊首开等）打开是一整页白屏，
/// 与其他面的空状态口径不一致。本政策把两支并成
/// 一条：无线程、或有线程但零条目，且不在流式中，
/// 即出空状态（形象＋招呼语＋建议条，形态沿落地态
/// 既有件，不另起视觉）。
public enum ChatEmptyState {

    public static func shows(
        threadIsNil: Bool, entryCount: Int, isStreaming: Bool
    ) -> Bool {
        !isStreaming && (threadIsNil || entryCount == 0)
    }
}
