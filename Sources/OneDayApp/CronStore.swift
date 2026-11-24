import Foundation
import OneDayCore

/// 定时任务共享店（台账 198 收敛·普查 R4/D2 追加
/// 条）：同一份服务端定时数据全 App 只许一处取数、
/// 一处缓存——此前枢纽定时段（AgentHubStore 私拉一
/// 份）、正主 CronJobsView（自拉自存）、状态页摘录
/// （自拉一份）三路并存，两份内存、口径各自为政。
/// 自此由 AppState 懒建单例（与 sharedHubStore 同形
/// 态，§259 三店合一先例），三面只消费本店：
/// - CronJobsView：管理面，读 jobs、动作后 refresh
/// - HubCronSection：只读概览，读 hubGroups（Core
///   CronHubClassifier 派生）与 lastRuns
/// - StatusView：摘录，读 jobs 自行排序取前三
/// 失效口径：拉取记住当时的服务器标识，配置变了
/// （换服务器/重连）下次 loadIfNeeded 自动重拉，不
/// 拿旧服务器的名单冒充；写动作（新建/编辑/启停/
/// 删除/触发）完成后由动作面调 refresh 全面同步，
/// 三面同帧新值、不再各拉各的。
@MainActor
@Observable
final class CronStore {
    private let appState: AppState

    /// 全量任务名单（服务端原序，排序归各呈现面）
    private(set) var jobs: [CronJob] = []
    /// 最近一次运行时刻（job id → 时刻）：枢纽概览
    /// 的间隔行「上次运行」补拉所得，懒加载、只补缺
    private(set) var lastRuns: [String: Date] = [:]
    private(set) var loadFailed = false
    /// 首拉失败的人话（管理页错误行用；后续刷新失败
    /// 不覆盖已加载名单、只立 loadFailed）
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    /// 已成功拉过至少一次（区分「空名单」与「未加载」）
    private(set) var hasLoaded = false
    /// 名单的来源服务器标识（配置变更失效判定）
    private var loadedForConfig: String?
    private var lastRunsLoadedForConfig: String?

    init(appState: AppState) {
        self.appState = appState
    }

    /// 枢纽概览分组（Core 分类器单源派生：分组/组内
    /// 序/间隔人话全在 CronHubClassifier，本店只喂数）
    var hubGroups: [(kind: HubCronKind, items: [HubCronItem])] {
        CronHubClassifier.grouped(jobs, lastRuns: lastRuns)
    }

    private var currentConfigKey: String? {
        appState.config?.baseString
    }

/// §416 新鲜度普查豁免：本店是范式源头——会话级单拉＋配置键失效＋写后 refresh 显式同步，严于 TTL 门，接门非等价（判定表见 DESIGN §416）
    /// 按需加载：已加载且服务器没变即跳过；在飞不重入
    func loadIfNeeded() async {
        guard !isLoading else { return }
        if hasLoaded, loadedForConfig == currentConfigKey { return }
        await refresh()
    }

    /// 强制重拉（下拉刷新/写动作后同步）：失败保留
    /// 上次名单、只立失败旗，不拿空数组冒充无任务
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await appState.performAdmin { client, config in
                try await client.cronJobs(config: config)
            }
            jobs = fetched
            loadFailed = false
            errorMessage = nil
            hasLoaded = true
            loadedForConfig = currentConfigKey
            // 名单换代后旧的最近运行缓存可能指向已删
            // 任务或旧值，随名单一并作废、下次概览懒
            // 补（补拉只针对间隔型缺值任务，量级有界）
            lastRuns = [:]
            lastRunsLoadedForConfig = nil
        } catch {
            loadFailed = true
            if !hasLoaded {
                errorMessage = (error as? HermesError)?.userMessage
                    ?? "定时任务没读出来，可能是网络或服务暂时没响应"
            }
        }
    }

    /// 最近运行懒补拉（枢纽概览专用）：只给间隔型且
    /// job 自带 lastRunAt 缺失的任务单拉 limit 1（原
    /// AgentHubStore.loadCronIfNeeded 口径，数据设计
    /// §3.5——不为每个 job 拉）；失败静默降级（概览
    /// 少一行上次运行，不整段报错）
    func loadLastRunsIfNeeded() async {
        if lastRunsLoadedForConfig == currentConfigKey,
           !jobs.isEmpty {
            return
        }
        for job in jobs {
            let item = CronHubClassifier.classify(job)
            guard item.kind == .interval,
                  item.lastRunAt == nil,
                  lastRuns[job.id] == nil else { continue }
            if let runs = try? await appState.performAdmin({ client, config in
                try await client.cronRuns(config: config, id: job.id, limit: 1)
            }), let latest = runs.compactMap(\.startedDate).max() {
                lastRuns[job.id] = latest
            }
        }
        lastRunsLoadedForConfig = currentConfigKey
    }
}
