import Foundation

/// 抽屉底条搜索状态政策（§155，抽屉呈现第二批）：
/// 搜索态的判定与收尾只此一处裁决，DrawerView 不
/// 再私算——此前 isSearching 的修剪规则只活在视图
/// 计算属性里、关抽屉后搜索词残留也无口径，两个
/// 状态各行其是。本政策两条：
/// ①搜索态＝搜索词修剪空白后非空（0.18.0 抽屉搜
/// 索沿革口径，判定自视图下沉至此、口径一字不变）；
/// ②抽屉由开转关即复位——重开恒呈默认态（全量导
/// 航名单＋空搜索框），不把上一次的过滤态带回入
/// 口（状态呈现收敛：入口状态只许一个）。
public enum DrawerSearchPolicy {

    /// 规范化搜索词：修剪首尾空白（过滤与判定共用
    /// 同一规范化，两处不许各修各的）
    public static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// 是否处于搜索态：规范化后非空
    public static func isSearching(query: String) -> Bool {
        !normalizedQuery(query).isEmpty
    }

    /// 开合迁移是否触发搜索复位：仅「开→关」一沿
    /// 触发（关→开不触发——重开时词已是空的，复位
    /// 无对象；同态保持不触发——避免每次状态回写
    /// 都清词）
    public static func shouldResetQuery(
        wasPresented: Bool, isPresented: Bool
    ) -> Bool {
        wasPresented && !isPresented
    }
}
