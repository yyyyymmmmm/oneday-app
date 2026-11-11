import CoreLocation
import Foundation
import MapKit
import MediaPlayer
import MessageUI
import Network
import OneDayCore
import QuickLook
import UIKit
import os

/// 日常面执行层（设备扩容批四，§115）：定位/媒体
/// 库/拨号与撰写/快捷指令/设备信息/文件预览打印。
/// 授权分档与前三批严格同规：定位/媒体库是真系统
/// 权限（过 OneDayCore.DevicePermissionGate、先同
/// 步读现态、只有未决定才发那一次请求）；撰写/快
/// 捷指令/设备信息没有可开关的系统权限，状态恒
/// notApplicable、调用开关即唯一的门。撰写与分享
/// 的定性是「把系统面交到用户手上」——发出动作永
/// 远由用户亲手点，引擎只报「面打开了/用户发了/
/// 用户取消了」的当场事实，不代发、不装发。

// MARK: - 在场面单飞门（批四）

/// 撰写/分享/预览/打印/快捷指令等待同一时间只许
/// 一件在场：系统面叠着开只会互相打架，第二件如
/// 实回错、请用户先处理完前一个。批三的拍照/扫
/// 描有各自的桥内协调者、不经此门（本包不回改批
/// 三，口径差登记在 §115）。
enum DevicePresenceGate {
    private static let box =
        OSAllocatedUnfairLock<Bool>(initialState: false)

    static func acquire() -> Bool {
        box.withLock { occupied in
            if occupied { return false }
            occupied = true
            return true
        }
    }

    static func release() {
        box.withLock { $0 = false }
    }

    static var busyError: DeviceToolError {
        DeviceToolError.failed(
            "现在有另一个界面正打开着（撰写/分享/预览/快捷指令之一），先把它处理完再试"
        )
    }
}

/// 当前最顶层 VC（DeviceCaptureBridge 同款走法：
/// 沿 presentedViewController 链走到顶）
enum DeviceTopmostPresenter {
    @MainActor
    static func topmost() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let keyWindow = windows.first { $0.isKeyWindow }
            ?? windows.first
        var controller = keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

// MARK: - 定位执行器（CoreLocation/MapKit，设备扩容批四）

/// 定位的 Sendable 快照：CLLocation 本体不跨并发
/// 边界，只把坐标/精度/时刻这几个值带出来（要地
/// 名时在引擎里按坐标现构造 CLLocation 去查）
struct LocationFix: Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timestamp: Date
}

/// 定位是真系统权限（只有「使用时」一档）：授权
/// 状态同步可读，先读现态过 Core 的
/// DevicePermissionGate，只有未决定才发那一次请
/// 求（系统授权铁律）。一次性定位走 delegate 回
/// 调——回调闭包不继承 actor 隔离（回调隔离铁
/// 律），协调者的状态只在主线程的回调与主 actor
/// 任务里触碰（与批三协调者同纪律）。
final class LocationEngine: @unchecked Sendable {

    static func systemState() -> DevicePermissionState {
        switch CLLocationManager().authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    /// 详情页权限开关共用的请求口：过门决策——只有
    /// requestOnce 才真发那一次请求，其余档只回读
    func requestAccess() async -> DevicePermissionState {
        let current = Self.systemState()
        guard OneDayCore.DevicePermissionGate.decision(
            for: current
        ) == .requestOnce else { return current }
        await LocationAuthorizationWaiter.requestOnce()
        return Self.systemState()
    }

    private func requireUsable() throws {
        let state = Self.systemState()
        guard state.isUsable else {
            throw DeviceToolError.permissionDenied(
                "定位的系统权限当前是「\(state.label)」，读不到位置"
            )
        }
    }

    /// 一次性定位（协调者由本函数持有到回执为止，
    /// 管理器经协调者强持有、delegate 弱引用链不断）
    private func fetchFix() async throws -> LocationFix {
        let coordinator = LocationFetchCoordinator()
        return try await coordinator.fetch(timeoutSeconds: 20)
    }

    /// 坐标 → 地名/地址（尽力而为：查不到不拖垮定
    /// 位本体，字段缺省如实不编）
    private func placemarkFields(
        latitude: Double, longitude: Double
    ) async -> [String: JSONValue] {
        let geocoder = CLGeocoder()
        let location = CLLocation(
            latitude: latitude, longitude: longitude
        )
        guard let placemarks = try? await geocoder
            .reverseGeocodeLocation(location),
              let mark = placemarks.first
        else { return [:] }
        var fields: [String: JSONValue] = [:]
        if let name = mark.name, !name.isEmpty {
            fields["placeName"] = .string(name)
        }
        let address = [
            mark.administrativeArea, mark.locality,
            mark.subLocality, mark.thoroughfare,
            mark.subThoroughfare,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined()
        if !address.isEmpty {
            fields["address"] = .string(address)
        }
        return fields
    }

    /// location_current：现读一次位置＋精度＋地名
    func currentResult(
        _ args: LocationCurrentArgs
    ) async throws -> JSONValue {
        try requireUsable()
        let fix = try await fetchFix()
        var result: [String: JSONValue] = [
            "readAt": .string(DeviceISO8601.format(Date())),
            "latitude": .number(fix.latitude),
            "longitude": .number(fix.longitude),
            "accuracyMeters": .number(fix.horizontalAccuracy),
            "locatedAt": .string(
                DeviceISO8601.format(fix.timestamp)
            ),
        ]
        for (key, value) in await placemarkFields(
            latitude: fix.latitude, longitude: fix.longitude
        ) {
            result[key] = value
        }
        result["humanSummary"] = .string(
            "当前位置已现读（精度约 "
                + "\(Int(fix.horizontalAccuracy.rounded())) 米）"
        )
        return .object(result)
    }

    /// location_search_places：先定位、再以当前位置
    /// 为中心检索附近地点（不知道用户在哪，「附近」
    /// 就无从谈起——定位失败如实失败，不拿无区域
    /// 的全局结果冒充附近）
    func searchPlacesResult(
        _ args: LocationSearchPlacesArgs
    ) async throws -> JSONValue {
        try requireUsable()
        let fix = try await fetchFix()
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = args.query
        request.resultTypes = [.pointOfInterest, .address]
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: fix.latitude, longitude: fix.longitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: 0.08, longitudeDelta: 0.08
            )
        )
        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(
                request: request
            ).start()
        } catch {
            throw DeviceToolError.failed(
                "附近地点没查成：\(error.localizedDescription)"
            )
        }
        let center = CLLocation(
            latitude: fix.latitude, longitude: fix.longitude
        )
        var places: [[String: JSONValue]] = []
        for item in response.mapItems.prefix(args.limit) {
            let coordinate = item.placemark.coordinate
            var place: [String: JSONValue] = [
                "name": .string(item.name ?? ""),
                "latitude": .number(coordinate.latitude),
                "longitude": .number(coordinate.longitude),
                "distanceMeters": .number(
                    CLLocation(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    ).distance(from: center)
                ),
            ]
            let address = [
                item.placemark.locality,
                item.placemark.subLocality,
                item.placemark.thoroughfare,
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined()
            if !address.isEmpty {
                place["address"] = .string(address)
            }
            places.append(place)
        }
        return .object([
            "readAt": .string(DeviceISO8601.format(Date())),
            "query": .string(args.query),
            "count": .number(Double(places.count)),
            "places": .array(places.map { .object($0) }),
            "humanSummary": .string(args.humanSummary),
        ])
    }

    /// location_geocode：地址↔坐标互换（模式在 Core
    /// 解析层已钉成恰给其一）
    func geocodeResult(
        _ args: LocationGeocodeArgs
    ) async throws -> JSONValue {
        let geocoder = CLGeocoder()
        if let address = args.address {
            let placemarks: [CLPlacemark]
            do {
                placemarks = try await geocoder
                    .geocodeAddressString(address)
            } catch {
                throw DeviceToolError.failed(
                    "地址换算没成：\(error.localizedDescription)"
                )
            }
            guard let mark = placemarks.first,
                  let location = mark.location else {
                throw DeviceToolError.failed(
                    "这个地址没查到坐标：\(address)"
                )
            }
            var result: [String: JSONValue] = [
                "readAt": .string(
                    DeviceISO8601.format(Date())
                ),
                "mode": .string("forward"),
                "address": .string(address),
                "latitude": .number(location.coordinate.latitude),
                "longitude": .number(
                    location.coordinate.longitude
                ),
            ]
            if let name = mark.name, !name.isEmpty {
                result["placeName"] = .string(name)
            }
            result["humanSummary"] = .string(args.humanSummary)
            return .object(result)
        }
        guard let latitude = args.latitude,
              let longitude = args.longitude else {
            // 解析层已钉恰给其一，走到这里即编程错误，
            // 如实回参数错误不猜
            throw DeviceToolError.invalidArguments(
                "地址与坐标要恰给一个"
            )
        }
        var result: [String: JSONValue] = [
            "readAt": .string(DeviceISO8601.format(Date())),
            "mode": .string("reverse"),
            "latitude": .number(latitude),
            "longitude": .number(longitude),
        ]
        for (key, value) in await placemarkFields(
            latitude: latitude, longitude: longitude
        ) {
            result[key] = value
        }
        guard result["address"] != nil
            || result["placeName"] != nil else {
            throw DeviceToolError.failed(
                "这个坐标没查到对应的地名"
            )
        }
        result["humanSummary"] = .string(args.humanSummary)
        return .object(result)
    }
}

/// 授权等待者：只在未决定时用（调用方已过门）；
/// delegate 回调在管理器所在线程（主线程）投递、
/// 不继承 actor 隔离（回调隔离铁律），只 resume
/// 一次就放手
private final class LocationAuthorizationWaiter: NSObject,
    CLLocationManagerDelegate, @unchecked Sendable {
    private var manager: CLLocationManager?
    private var continuation: CheckedContinuation<Void, Never>?
    /// 自持：delegate 是弱引用、等待期间没有别处强
    /// 持有本对象，靠自持活到回调为止（回调里先放）
    private var selfRetain: LocationAuthorizationWaiter?

    static func requestOnce() async {
        let waiter = LocationAuthorizationWaiter()
        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                waiter.begin(continuation: continuation)
            }
        }
    }

    @MainActor
    private func begin(
        continuation: CheckedContinuation<Void, Never>
    ) {
        guard CLLocationManager().authorizationStatus
            == .notDetermined else {
            continuation.resume()
            return
        }
        self.continuation = continuation
        self.selfRetain = self
        let manager = CLLocationManager()
        manager.delegate = self
        self.manager = manager
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        guard manager.authorizationStatus != .notDetermined
        else { return }
        let continuation = self.continuation
        self.continuation = nil
        self.manager = nil
        self.selfRetain = nil
        continuation?.resume()
    }
}

/// 一次性定位协调者（与批三协调者同纪律：状态只在
/// 主线程的 delegate 回调与主 actor 任务里触碰，故
/// 显式 @unchecked Sendable；超时/取消都先跳回主
/// actor 再收尾，finish 只认第一次）
private final class LocationFetchCoordinator: NSObject,
    CLLocationManagerDelegate, @unchecked Sendable {
    private var manager: CLLocationManager?
    private var continuation:
        CheckedContinuation<LocationFix, Error>?

    func fetch(
        timeoutSeconds: TimeInterval
    ) async throws -> LocationFix {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                continuation in
                Task { @MainActor in
                    self.continuation = continuation
                    let manager = CLLocationManager()
                    manager.desiredAccuracy =
                        kCLLocationAccuracyHundredMeters
                    manager.delegate = self
                    self.manager = manager
                    manager.requestLocation()
                }
                Task { @MainActor in
                    try? await Task.sleep(
                        for: .seconds(timeoutSeconds)
                    )
                    self.finish {
                        throw DeviceToolError.failed(
                            "定位超时，暂时取不到当前位置"
                        )
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.finish { throw CancellationError() }
            }
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        let fix = LocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
        finish { fix }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        finish {
            throw DeviceToolError.failed(
                "定位没成功：\(error.localizedDescription)"
            )
        }
    }

    private func finish(
        _ body: () throws -> LocationFix
    ) {
        guard let continuation else { return }
        self.continuation = nil
        self.manager = nil
        continuation.resume(with: Result { try body() })
    }
}

// MARK: - 媒体库执行器（MediaPlayer，设备扩容批四）

/// MPMediaPlaylist 跨 continuation 边界的盒（与批
/// 二 ReminderBox 同款：取回后只在本引擎内读）
private struct PlaylistBox: @unchecked Sendable {
    let playlist: MPMediaPlaylist
}

/// MPMediaItem 跨主 actor 边界的盒（同上）
private struct MediaItemBox: @unchecked Sendable {
    let item: MPMediaItem
}

/// 播放状态快照（Sendable 值：状态原文＋正在播的
/// 条目标识与曲名，详情页与回读验证共用）
struct PlaybackSnapshot: Sendable {
    let stateText: String
    let isPlaying: Bool
    let nowPlayingID: UInt64?
    let nowPlayingTitle: String?
    let nowPlayingArtist: String?
}

/// 媒体库是真系统权限：authorizationStatus 同步可
/// 读，先读现态过 DevicePermissionGate，只有未决
/// 定才发那一次请求（系统授权铁律）。检索只回书
/// 目信息、音频本体不出手机；读不到其他 App 正在
/// 放什么（系统不给，名册文案已明说）。建歌单回
/// 读核对才报成功；播放控制作用于系统音乐播放
/// 器，动作后轮询回读状态、达不到预期如实失败。
final class MediaEngine: @unchecked Sendable {

    static func systemState() -> DevicePermissionState {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    /// 详情页权限开关共用的请求口（过门决策）
    func requestAccess() async -> DevicePermissionState {
        let current = Self.systemState()
        guard OneDayCore.DevicePermissionGate.decision(
            for: current
        ) == .requestOnce else { return current }
        _ = await withCheckedContinuation {
            (continuation:
                CheckedContinuation<
                    MPMediaLibraryAuthorizationStatus, Never
                >) in
            MPMediaLibrary.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        return Self.systemState()
    }

    private func requireUsable() throws {
        let state = Self.systemState()
        guard state.isUsable else {
            throw DeviceToolError.permissionDenied(
                "媒体库的系统权限当前是「\(state.label)」，用不了"
            )
        }
    }

    // MARK: 检索与歌单（只读）

    private func songsMatching(
        property: String, query: String
    ) -> [MPMediaItem] {
        let mediaQuery = MPMediaQuery.songs()
        mediaQuery.addFilterPredicate(
            MPMediaPropertyPredicate(
                value: query, forProperty: property,
                comparisonType: .contains
            )
        )
        return mediaQuery.items ?? []
    }

    private static func songObject(
        _ item: MPMediaItem
    ) -> [String: JSONValue] {
        var object: [String: JSONValue] = [
            "type": .string("song"),
            "id": .string(String(item.persistentID)),
            "title": .string(item.title ?? ""),
            "durationSeconds": .number(item.playbackDuration),
        ]
        if let artist = item.artist, !artist.isEmpty {
            object["artist"] = .string(artist)
        }
        if let album = item.albumTitle, !album.isEmpty {
            object["album"] = .string(album)
        }
        return object
    }

    /// media_library_search：按类别查书目（歌按标
    /// 题∪艺人合并去重、专辑/艺人/歌单按集合、播
    /// 客按条目）；总量超 limit 截断并标 truncated
    func searchResult(
        _ args: MediaLibrarySearchArgs
    ) throws -> JSONValue {
        try requireUsable()
        let query = args.query
        var results: [[String: JSONValue]] = []
        if args.kind == .song || args.kind == .any {
            var seen = Set<UInt64>()
            let byTitle = songsMatching(
                property: MPMediaItemPropertyTitle, query: query
            )
            let byArtist = songsMatching(
                property: MPMediaItemPropertyArtist, query: query
            )
            for item in byTitle + byArtist {
                guard seen.insert(item.persistentID).inserted
                else { continue }
                results.append(Self.songObject(item))
            }
        }
        if args.kind == .album || args.kind == .any {
            let albumQuery = MPMediaQuery.albums()
            albumQuery.addFilterPredicate(
                MPMediaPropertyPredicate(
                    value: query,
                    forProperty: MPMediaItemPropertyAlbumTitle,
                    comparisonType: .contains
                )
            )
            for collection in albumQuery.collections ?? [] {
                guard let representative =
                    collection.representativeItem else {
                    continue
                }
                var object: [String: JSONValue] = [
                    "type": .string("album"),
                    "title": .string(
                        representative.albumTitle ?? ""
                    ),
                    "itemCount": .number(
                        Double(collection.count)
                    ),
                ]
                let artist = representative.albumArtist
                    ?? representative.artist
                if let artist, !artist.isEmpty {
                    object["artist"] = .string(artist)
                }
                results.append(object)
            }
        }
        if args.kind == .artist || args.kind == .any {
            let artistQuery = MPMediaQuery.artists()
            artistQuery.addFilterPredicate(
                MPMediaPropertyPredicate(
                    value: query,
                    forProperty: MPMediaItemPropertyArtist,
                    comparisonType: .contains
                )
            )
            for collection in artistQuery.collections ?? [] {
                guard let representative =
                    collection.representativeItem else {
                    continue
                }
                results.append([
                    "type": .string("artist"),
                    "title": .string(representative.artist ?? ""),
                    "itemCount": .number(
                        Double(collection.count)
                    ),
                ])
            }
        }
        if args.kind == .playlist || args.kind == .any {
            for collection in
                MPMediaQuery.playlists().collections ?? [] {
                guard let playlist =
                    collection as? MPMediaPlaylist,
                      let name = playlist.name,
                      name.localizedCaseInsensitiveContains(query)
                else { continue }
                results.append(Self.playlistObject(playlist))
            }
        }
        if args.kind == .podcast || args.kind == .any {
            let podcastQuery = MPMediaQuery.podcasts()
            podcastQuery.addFilterPredicate(
                MPMediaPropertyPredicate(
                    value: query,
                    forProperty: MPMediaItemPropertyTitle,
                    comparisonType: .contains
                )
            )
            for item in podcastQuery.items ?? [] {
                var object: [String: JSONValue] = [
                    "type": .string("podcast"),
                    "id": .string(String(item.persistentID)),
                    "title": .string(item.title ?? ""),
                    "durationSeconds": .number(
                        item.playbackDuration
                    ),
                ]
                if let artist = item.artist, !artist.isEmpty {
                    object["artist"] = .string(artist)
                }
                results.append(object)
            }
        }
        let truncated = results.count > args.limit
        let capped = Array(results.prefix(args.limit))
        var result: [String: JSONValue] = [
            "readAt": .string(DeviceISO8601.format(Date())),
            "query": .string(query),
            "kind": .string(args.kind.rawValue),
            "count": .number(Double(capped.count)),
            "results": .array(capped.map { .object($0) }),
            "humanSummary": .string(args.humanSummary),
        ]
        if truncated {
            result["truncated"] = .bool(true)
        }
        return .object(result)
    }

    static func playlistObject(
        _ playlist: MPMediaPlaylist
    ) -> [String: JSONValue] {
        [
            "type": .string("playlist"),
            "id": .string(String(playlist.persistentID)),
            "name": .string(playlist.name ?? ""),
            "itemCount": .number(Double(playlist.count)),
        ]
    }

    /// media_playlists：全量列歌单（上限收敛、超了
    /// 截断标 truncated，与 files_list 同口径）
    func playlistsResult(
        _ args: MediaPlaylistsArgs
    ) throws -> JSONValue {
        try requireUsable()
        let collections =
            MPMediaQuery.playlists().collections ?? []
        var list: [[String: JSONValue]] = []
        for collection in collections.prefix(
            EverydayLimits.maxPlaylists
        ) {
            if let playlist = collection as? MPMediaPlaylist {
                list.append(Self.playlistObject(playlist))
            }
        }
        var result: [String: JSONValue] = [
            "readAt": .string(DeviceISO8601.format(Date())),
            "count": .number(Double(list.count)),
            "playlists": .array(list.map { .object($0) }),
        ]
        if collections.count > list.count {
            result["truncated"] = .bool(true)
        }
        return .object(result)
    }

    /// 详情页本地列歌单（与工具同一条路）
    func localPlaylists() throws -> [[String: JSONValue]] {
        try requireUsable()
        let collections =
            MPMediaQuery.playlists().collections ?? []
        return collections.compactMap { collection in
            (collection as? MPMediaPlaylist).map(
                Self.playlistObject
            )
        }
    }

    /// 按 persistentID 找回歌单（回放与建歌单回读共
    /// 用；不在回 nil、不编）
    func playlistObjectByID(
        _ id: String
    ) -> [String: JSONValue]? {
        let collections =
            MPMediaQuery.playlists().collections ?? []
        for collection in collections {
            if let playlist = collection as? MPMediaPlaylist,
               String(playlist.persistentID) == id {
                return Self.playlistObject(playlist)
            }
        }
        return nil
    }

    // MARK: 建歌单（写，回读验证）

    /// media_playlist_create：系统口建一份空歌单，
    /// 建完按 persistentID 在歌单列表里找回才报成
    /// 功；账本 objectID＝persistentID
    func createPlaylist(
        _ args: MediaPlaylistCreateArgs
    ) async throws -> (objectID: String, result: JSONValue) {
        try requireUsable()
        let box: PlaylistBox
        do {
            box = try await withCheckedThrowingContinuation {
                (continuation:
                    CheckedContinuation<PlaylistBox, Error>) in
                let metadata =
                    MPMediaPlaylistCreationMetadata()
                // Swift 导入把 name 标成只读，底层 ObjC
                // 属性可写，走 KVC 赋值（同名字段）
                metadata.setValue(
                    args.name, forKey: "name"
                )
                MPMediaLibrary.default().getPlaylist(
                    with: UUID(),
                    creationMetadata: metadata
                ) { created, error in
                    if let created {
                        continuation.resume(
                            returning: PlaylistBox(
                                playlist: created
                            )
                        )
                    } else {
                        continuation.resume(
                            throwing: error
                                ?? DeviceToolError.failed(
                                    "歌单没有建出来"
                                )
                        )
                    }
                }
            }
        } catch let error as DeviceToolError {
            throw error
        } catch {
            throw DeviceToolError.failed(
                "新建歌单失败：\(error.localizedDescription)"
            )
        }
        let id = String(box.playlist.persistentID)
        guard let object = playlistObjectByID(id) else {
            throw DeviceToolError.failed(
                "歌单建完后没能在资料库里确认它存在，不报成功"
            )
        }
        var result = object
        result["created"] = .bool(true)
        result["verified"] = .bool(true)
        result["humanSummary"] = .string(args.humanSummary)
        return (id, .object(result))
    }

    // MARK: 播放控制（写，回读验证）

    /// 播放状态快照（播放器触点只在主 actor 上取，
    /// 出来的全是 Sendable 值）
    @MainActor
    static func playbackSnapshot() -> PlaybackSnapshot {
        let player = MPMusicPlayerController.systemMusicPlayer
        let state = player.playbackState
        let stateText: String
        switch state {
        case .stopped: stateText = "已停止"
        case .playing: stateText = "正在播放"
        case .paused: stateText = "已暂停"
        case .interrupted: stateText = "被打断"
        case .seekingForward: stateText = "快进中"
        case .seekingBackward: stateText = "快退中"
        @unknown default: stateText = "未知"
        }
        let item = player.nowPlayingItem
        return PlaybackSnapshot(
            stateText: stateText,
            isPlaying: state == .playing,
            nowPlayingID: item?.persistentID,
            nowPlayingTitle: item?.title,
            nowPlayingArtist: item?.artist
        )
    }

    /// 详情页播放状态一行（本地现读）
    func localPlaybackLine() async -> String {
        let snapshot = await MainActor.run {
            Self.playbackSnapshot()
        }
        if let title = snapshot.nowPlayingTitle,
           !title.isEmpty {
            let artist = snapshot.nowPlayingArtist
                .map { " · \($0)" } ?? ""
            return "\(snapshot.stateText)：\(title)\(artist)"
        }
        return snapshot.stateText
    }

    private func firstSongBox(
        matching query: String
    ) -> MediaItemBox? {
        let byTitle = songsMatching(
            property: MPMediaItemPropertyTitle, query: query
        )
        if let first = byTitle.first {
            return MediaItemBox(item: first)
        }
        let byArtist = songsMatching(
            property: MPMediaItemPropertyArtist, query: query
        )
        return byArtist.first.map { MediaItemBox(item: $0) }
    }

    /// 动作达成判定（回读验证的口径，逐动作写明）：
    /// 播＝正在播放；停＝已停止；暂停＝不在播放（已
    /// 暂停或已停止都算「没在播」这一可验事实）；
    /// 切歌＝正在播的条目换了（队列到头切不动即不达）
    private static func isVerified(
        action: MediaPlaybackAction,
        snapshot: PlaybackSnapshot, beforeID: UInt64?
    ) -> Bool {
        switch action {
        case .play: return snapshot.isPlaying
        case .pause: return !snapshot.isPlaying
        case .stop: return snapshot.stateText == "已停止"
        case .next, .previous:
            return snapshot.nowPlayingID != nil
                && snapshot.nowPlayingID != beforeID
        }
    }

    /// media_playback_control：动作在主 actor 上发，
    /// 之后轮询回读至多约 1.5 秒；达不到预期如实
    /// 失败（把当下真实状态说清）、绝不装成功
    func playbackControl(
        _ args: MediaPlaybackControlArgs
    ) async throws -> (objectID: String, result: JSONValue) {
        try requireUsable()
        var targetBox: MediaItemBox?
        if args.action == .play, let query = args.query {
            targetBox = firstSongBox(matching: query)
            guard targetBox != nil else {
                throw DeviceToolError.failed(
                    "资料库里没找到「\(query)」这首歌"
                )
            }
        }
        let before = await MainActor.run {
            Self.playbackSnapshot()
        }
        await MainActor.run {
            let player =
                MPMusicPlayerController.systemMusicPlayer
            if let targetBox {
                player.setQueue(
                    with: MPMediaItemCollection(
                        items: [targetBox.item]
                    )
                )
            }
            switch args.action {
            case .play: player.play()
            case .pause: player.pause()
            case .stop: player.stop()
            case .next: player.skipToNextItem()
            case .previous: player.skipToPreviousItem()
            }
        }
        var snapshot = await MainActor.run {
            Self.playbackSnapshot()
        }
        let deadline = Date().addingTimeInterval(1.5)
        while !Self.isVerified(
            action: args.action, snapshot: snapshot,
            beforeID: before.nowPlayingID
        ), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(300))
            snapshot = await MainActor.run {
                Self.playbackSnapshot()
            }
        }
        guard Self.isVerified(
            action: args.action, snapshot: snapshot,
            beforeID: before.nowPlayingID
        ) else {
            throw DeviceToolError.failed(
                "指令发出去了，但播放器现在的状态是「\(snapshot.stateText)」，没达到预期，不报成功"
            )
        }
        var result: [String: JSONValue] = [
            "action": .string(args.action.rawValue),
            "verified": .bool(true),
            "state": .string(snapshot.stateText),
            "humanSummary": .string(args.humanSummary),
        ]
        if let title = snapshot.nowPlayingTitle,
           !title.isEmpty {
            var nowPlaying: [String: JSONValue] = [
                "title": .string(title),
            ]
            if let artist = snapshot.nowPlayingArtist,
               !artist.isEmpty {
                nowPlaying["artist"] = .string(artist)
            }
            result["nowPlaying"] = .object(nowPlaying)
        }
        return (args.action.rawValue, .object(result))
    }
}

// MARK: - 撰写与分享呈现桥（短信/邮件/分享，设备扩容批四）

/// 撰写结果（系统面当场给出的事实）：sent＝用户亲
/// 手点了发送；savedDraft＝邮件存了草稿（写了但没
/// 发，单独一档不许混进 sent）；cancelled＝用户在
/// 面上取消了——这是正常结局、不是错误
enum ComposeOutcome: String, Sendable {
    case sent
    case savedDraft
    case cancelled
}

/// 系统撰写/分享面的呈现桥（与 DeviceCaptureBridge
/// 同构）：自最顶层 VC 呈现、coordinator 静态强持
/// 有到回调、回调先 dismiss 再交回；等待被取消时
/// 经 cancelActive 收尾。在场面先过
/// DevicePresenceGate（同一时间只许一件）。
enum DeviceComposeBridge {

    private static let smsBox = OSAllocatedUnfairLock<
        MessageComposeCoordinator?
    >(initialState: nil)
    private static let mailBox = OSAllocatedUnfairLock<
        MailComposeCoordinator?
    >(initialState: nil)
    private static let shareBox = OSAllocatedUnfairLock<
        ShareCoordinator?
    >(initialState: nil)

    // MARK: 短信

    static func presentSMS(
        recipients: [String], body: String?
    ) async throws -> ComposeOutcome {
        let canSendText = await MainActor.run {
            MFMessageComposeViewController.canSendText()
        }
        guard canSendText else {
            throw DeviceToolError.failed(
                "这台手机现在发不了短信（没有可用的短信服务）"
            )
        }
        guard DevicePresenceGate.acquire() else {
            throw DevicePresenceGate.busyError
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                continuation in
                Task { @MainActor in
                    guard !Task.isCancelled else {
                        DevicePresenceGate.release()
                        continuation.resume(
                            throwing: CancellationError()
                        )
                        return
                    }
                    guard let presenter =
                        DeviceTopmostPresenter.topmost()
                    else {
                        DevicePresenceGate.release()
                        continuation.resume(
                            throwing: DeviceToolError.failed(
                                "现在没法打开短信撰写面"
                            )
                        )
                        return
                    }
                    let controller =
                        MFMessageComposeViewController()
                    controller.recipients = recipients
                    controller.body = body
                    let coordinator =
                        MessageComposeCoordinator(
                            continuation: continuation
                        )
                    controller.messageComposeDelegate =
                        coordinator
                    coordinator.controller = controller
                    smsBox.withLock { $0 = coordinator }
                    presenter.present(
                        controller, animated: true
                    )
                }
            }
        } onCancel: {
            Task { @MainActor in
                smsBox.withLock { $0 }?.cancelFromBridge()
            }
        }
    }

    private static func releaseSMS() {
        smsBox.withLock { $0 = nil }
    }

    // MARK: 邮件

    static func presentMail(
        recipients: [String], subject: String?, body: String?
    ) async throws -> ComposeOutcome {
        let canSendMail = await MainActor.run {
            MFMailComposeViewController.canSendMail()
        }
        guard canSendMail else {
            throw DeviceToolError.failed(
                "这台手机还没有配置邮件账户，发不了邮件"
            )
        }
        guard DevicePresenceGate.acquire() else {
            throw DevicePresenceGate.busyError
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                continuation in
                Task { @MainActor in
                    guard !Task.isCancelled else {
                        DevicePresenceGate.release()
                        continuation.resume(
                            throwing: CancellationError()
                        )
                        return
                    }
                    guard let presenter =
                        DeviceTopmostPresenter.topmost()
                    else {
                        DevicePresenceGate.release()
                        continuation.resume(
                            throwing: DeviceToolError.failed(
                                "现在没法打开邮件撰写面"
                            )
                        )
                        return
                    }
                    let controller =
                        MFMailComposeViewController()
                    controller.setToRecipients(recipients)
                    if let subject {
                        controller.setSubject(subject)
                    }
                    if let body {
                        controller.setMessageBody(
                            body, isHTML: false
                        )
                    }
                    let coordinator = MailComposeCoordinator(
                        continuation: continuation
                    )
                    controller.mailComposeDelegate = coordinator
                    coordinator.controller = controller
                    mailBox.withLock { $0 = coordinator }
                    presenter.present(
                        controller, animated: true
                    )
                }
            }
        } onCancel: {
            Task { @MainActor in
                mailBox.withLock { $0 }?.cancelFromBridge()
            }
        }
    }

    private static func releaseMail() {
        mailBox.withLock { $0 = nil }
    }

    // MARK: 分享

    /// 分享面：完成回调给 completed（用户真选了去
    /// 向）与否；取消分享不是错误、如实回 false
    static func presentShare(
        text: String?, fileURL: URL?
    ) async throws -> Bool {
        guard DevicePresenceGate.acquire() else {
            throw DevicePresenceGate.busyError
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                continuation in
                Task { @MainActor in
                    guard !Task.isCancelled else {
                        DevicePresenceGate.release()
                        continuation.resume(
                            throwing: CancellationError()
                        )
                        return
                    }
                    guard let presenter =
                        DeviceTopmostPresenter.topmost()
                    else {
                        DevicePresenceGate.release()
                        continuation.resume(
                            throwing: DeviceToolError.failed(
                                "现在没法打开分享面"
                            )
                        )
                        return
                    }
                    var items: [Any] = []
                    if let text { items.append(text) }
                    if let fileURL {
                        items.append(fileURL as NSURL)
                    }
                    let controller = UIActivityViewController(
                        activityItems: items,
                        applicationActivities: nil
                    )
                    let coordinator = ShareCoordinator(
                        continuation: continuation
                    )
                    coordinator.controller = controller
                    controller.completionWithItemsHandler = {
                        _, completed, _, error in
                        coordinator.finish(
                            completed: completed, error: error
                        )
                    }
                    shareBox.withLock { $0 = coordinator }
                    presenter.present(
                        controller, animated: true
                    )
                }
            }
        } onCancel: {
            Task { @MainActor in
                shareBox.withLock { $0 }?.cancelFromBridge()
            }
        }
    }

    private static func releaseShare() {
        shareBox.withLock { $0 = nil }
    }

    // MARK: 协调者（delegate 弱引用，靠静态盒强持有到回调）

    // 协调者的可变状态只在主 actor 的回调与静态盒
    // 存取里触碰，故显式 @unchecked Sendable（批三
    // 协调者同纪律）；finish 是唯一出口：释放盒与
    // 在场门、resume 一次
    private final class MessageComposeCoordinator: NSObject,
        MFMessageComposeViewControllerDelegate,
        @unchecked Sendable {
        private var continuation:
            CheckedContinuation<ComposeOutcome, Error>?
        weak var controller:
            MFMessageComposeViewController?

        init(
            continuation:
                CheckedContinuation<ComposeOutcome, Error>
        ) {
            self.continuation = continuation
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
            switch result {
            case .sent:
                finish { .sent }
            case .cancelled:
                finish { .cancelled }
            case .failed:
                finish {
                    throw DeviceToolError.failed(
                        "短信没有发出去（系统报告发送失败）"
                    )
                }
            @unknown default:
                finish { .cancelled }
            }
        }

        @MainActor
        func cancelFromBridge() {
            controller?.dismiss(animated: true)
            finish { throw CancellationError() }
        }

        private func finish(
            _ body: () throws -> ComposeOutcome
        ) {
            guard let continuation else { return }
            self.continuation = nil
            DeviceComposeBridge.releaseSMS()
            DevicePresenceGate.release()
            continuation.resume(with: Result { try body() })
        }
    }

    private final class MailComposeCoordinator: NSObject,
        MFMailComposeViewControllerDelegate,
        @unchecked Sendable {
        private var continuation:
            CheckedContinuation<ComposeOutcome, Error>?
        weak var controller: MFMailComposeViewController?

        init(
            continuation:
                CheckedContinuation<ComposeOutcome, Error>
        ) {
            self.continuation = continuation
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            if let error {
                finish {
                    throw DeviceToolError.failed(
                        "邮件撰写面出错了：\(error.localizedDescription)"
                    )
                }
                return
            }
            switch result {
            case .sent:
                finish { .sent }
            case .saved:
                finish { .savedDraft }
            case .cancelled:
                finish { .cancelled }
            case .failed:
                finish {
                    throw DeviceToolError.failed(
                        "邮件没有发出去（系统报告发送失败）"
                    )
                }
            @unknown default:
                finish { .cancelled }
            }
        }

        @MainActor
        func cancelFromBridge() {
            controller?.dismiss(animated: true)
            finish { throw CancellationError() }
        }

        private func finish(
            _ body: () throws -> ComposeOutcome
        ) {
            guard let continuation else { return }
            self.continuation = nil
            DeviceComposeBridge.releaseMail()
            DevicePresenceGate.release()
            continuation.resume(with: Result { try body() })
        }
    }

    private final class ShareCoordinator: NSObject,
        @unchecked Sendable {
        private var continuation:
            CheckedContinuation<Bool, Error>?
        weak var controller: UIActivityViewController?

        init(continuation: CheckedContinuation<Bool, Error>) {
            self.continuation = continuation
        }

        /// 完成回调由系统在主线程投递；分享面选完去
        /// 向后系统自关，这里只交回结果
        func finish(completed: Bool, error: Error?) {
            guard let continuation else { return }
            self.continuation = nil
            DeviceComposeBridge.releaseShare()
            DevicePresenceGate.release()
            if let error {
                continuation.resume(
                    throwing: DeviceToolError.failed(
                        "分享面出错了：\(error.localizedDescription)"
                    )
                )
            } else {
                continuation.resume(returning: completed)
            }
        }

        @MainActor
        func cancelFromBridge() {
            controller?.dismiss(animated: true)
            guard let continuation else { return }
            self.continuation = nil
            DeviceComposeBridge.releaseShare()
            DevicePresenceGate.release()
            continuation.resume(throwing: CancellationError())
        }
    }
}

// MARK: - 撰写执行器（拨号/短信/邮件/分享，设备扩容批四）

/// 撰写四件没有系统权限可开关（拨号确认面、撰写
/// 面都是系统当面把关），状态恒 notApplicable。
/// 定性钉死：这里只负责「把面交到用户手上」，回
/// 执只报当场事实（面打开了、用户发了/存了草稿/
/// 取消了），发出动作永远不在本层发生。
final class ComposeEngine: @unchecked Sendable {

    /// call_start：打开 tel: 地址（系统弹拨号确认
    /// 面）；号码里的 #/* 必须转义，不许把片段符
    /// 号漏进 URL
    func startCall(
        _ args: CallStartArgs
    ) async throws -> JSONValue {
        let allowed = CharacterSet(
            charactersIn: "0123456789+-()."
        )
        let encoded = args.number.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? ""
        guard let url = URL(string: "tel:" + encoded) else {
            throw DeviceToolError.invalidArguments(
                "电话号码不是合法的号码"
            )
        }
        let opened = await withCheckedContinuation {
            (continuation: CheckedContinuation<Bool, Never>) in
            Task { @MainActor in
                UIApplication.shared.open(
                    url, options: [:]
                ) { success in
                    continuation.resume(returning: success)
                }
            }
        }
        guard opened else {
            throw DeviceToolError.failed("系统没能打开拨号面")
        }
        return .object([
            "initiated": .bool(true),
            "number": .string(args.number),
            "note": .string(
                "已弹出拨号确认面，拨不拨由用户在确认面上决定"
            ),
            "humanSummary": .string(args.humanSummary),
        ])
    }

    /// compose_sms：预填收件人与正文打开系统短信
    /// 撰写面；结果以面上的当场事实为准
    func composeSMS(
        _ args: ComposeSMSArgs
    ) async throws -> JSONValue {
        let outcome = try await DeviceComposeBridge.presentSMS(
            recipients: args.recipients, body: args.body
        )
        return Self.receipt(outcome: outcome, args: args)
    }

    /// compose_email：同短信口径，另有「存了草稿」
    /// 一档如实单列
    func composeEmail(
        _ args: ComposeEmailArgs
    ) async throws -> JSONValue {
        let outcome = try await DeviceComposeBridge.presentMail(
            recipients: args.recipients,
            subject: args.subject, body: args.body
        )
        return Self.receipt(outcome: outcome, args: args)
    }

    private static func receipt(
        outcome: ComposeOutcome, args: ComposeSMSArgs
    ) -> JSONValue {
        receipt(
            outcome: outcome, summary: args.humanSummary
        )
    }

    private static func receipt(
        outcome: ComposeOutcome, args: ComposeEmailArgs
    ) -> JSONValue {
        receipt(
            outcome: outcome, summary: args.humanSummary
        )
    }

    private static func receipt(
        outcome: ComposeOutcome, summary: String
    ) -> JSONValue {
        var result: [String: JSONValue] = [
            "presented": .bool(true),
            "outcome": .string(outcome.rawValue),
            "humanSummary": .string(summary),
        ]
        switch outcome {
        case .sent:
            result["sent"] = .bool(true)
        case .savedDraft:
            result["sent"] = .bool(false)
            result["note"] = .string(
                "用户把这封邮件存成了草稿，没有发出去"
            )
        case .cancelled:
            result["sent"] = .bool(false)
            result["note"] = .string(
                "用户在撰写面里取消了，没有发出去"
            )
        }
        return .object(result)
    }

    /// share_sheet：文字与/或 OneDay 文件夹里的文
    /// 件递到系统分享面；用户选了去向才算分享了，
    /// 取消如实回 shared=false、不作错误
    func share(
        _ args: ShareSheetArgs, files: SandboxFilesEngine
    ) async throws -> JSONValue {
        var fileURL: URL?
        if let path = args.path {
            fileURL = try files.urlForPreview(
                relativePath: path
            )
        }
        let completed = try await DeviceComposeBridge
            .presentShare(text: args.text, fileURL: fileURL)
        var result: [String: JSONValue] = [
            "presented": .bool(true),
            "shared": .bool(completed),
            "humanSummary": .string(args.humanSummary),
        ]
        if !completed {
            result["note"] = .string(
                "用户在分享面里取消了，没有分享出去"
            )
        }
        return .object(result)
    }

    // MARK: 详情页本地试一次（空预填，用户亲手填与发）

    func trialSMS() async throws -> ComposeOutcome {
        try await DeviceComposeBridge.presentSMS(
            recipients: [], body: nil
        )
    }

    func trialMail() async throws -> ComposeOutcome {
        try await DeviceComposeBridge.presentMail(
            recipients: [], subject: nil, body: nil
        )
    }
}

// MARK: - 快捷指令执行器（URL 方案＋x-callback，设备扩容批四）

/// x-callback 回执的事实档：success＝快捷指令跑完
/// 并回了成功（result 是它的文本输出、可缺）；can-
/// celled＝用户在那边取消；failed＝那边回了出错；
/// noCallback＝发起了、等满超时也没有回执（表面
/// 图 A22 口径：只报「已发起」、不许报成功）
enum ShortcutCallbackOutcome: Sendable {
    case success(result: String?)
    case cancelled
    case failed(message: String?)
    case noCallback
}

/// 回执中心：等回执的一方按 nonce 登记，App 收到
/// oneday://shortcut-callback/<nonce>/<档> 的打
/// 开请求时按 nonce 交回（RootView 的 onOpenURL 只
/// 转交到这里）。同一时间只等一件（在场门已在外
/// 层把关，这里再兜一层防重入）。
enum ShortcutCallbackCenter {
    private struct Pending: Sendable {
        let nonce: String
        let continuation:
            CheckedContinuation<ShortcutCallbackOutcome, Error>
    }

    private static let box =
        OSAllocatedUnfairLock<Pending?>(initialState: nil)

    static func register(
        nonce: String,
        continuation:
            CheckedContinuation<ShortcutCallbackOutcome, Error>
    ) -> Bool {
        box.withLock { pending in
            if pending != nil { return false }
            pending = Pending(
                nonce: nonce, continuation: continuation
            )
            return true
        }
    }

    static func take(
        nonce: String
    ) -> CheckedContinuation<ShortcutCallbackOutcome, Error>? {
        box.withLock { pending in
            guard let current = pending,
                  current.nonce == nonce else { return nil }
            pending = nil
            return current.continuation
        }
    }

    /// App 层 URL 入口（RootView.onOpenURL 转交）：
    /// 形态不对/无人等/ nonce 对不上，一律安静忽略
    /// （任意外部链接都能打到这个 scheme 上，不许
    /// 拿它当出错面）
    static func handle(url: URL) {
        guard url.scheme == "oneday",
              url.host == "shortcut-callback" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2,
              let continuation = take(nonce: parts[0])
        else { return }
        let items = URLComponents(
            url: url, resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        switch parts[1] {
        case "success":
            continuation.resume(
                returning: .success(result: value("result"))
            )
        case "cancel":
            continuation.resume(returning: .cancelled)
        case "error":
            continuation.resume(
                returning: .failed(message: value("error"))
            )
        default:
            continuation.resume(
                returning: .failed(message: nil)
            )
        }
    }
}

/// shortcut_run：按名运行（系统只能按名、不能枚
/// 举，见表面图 A22/C7）。走 x-callback 变体取回
/// 执：成功/取消/出错都以回调为准；100 秒等不到
/// 回执如实回「已发起、未确认结果」——不装跑完。
/// 运行会切到快捷指令上下文，回来才有回执，等待
/// 期间占在场门。
final class ShortcutEngine: @unchecked Sendable {

    /// 等回执的超时（秒）：给用户在那边跑完一条指
    /// 令留足时间，又不许无限挂住调用；桥侧在场类
    /// 超时口径见 §115 桥侧待办
    static let callbackTimeoutSeconds: TimeInterval = 100

    func run(
        _ args: ShortcutRunArgs
    ) async throws -> JSONValue {
        guard DevicePresenceGate.acquire() else {
            throw DevicePresenceGate.busyError
        }
        let nonce = UUID().uuidString
        let outcome: ShortcutCallbackOutcome
        do {
            outcome = try await awaitCallback(
                args: args, nonce: nonce
            )
        } catch {
            DevicePresenceGate.release()
            throw error
        }
        DevicePresenceGate.release()
        switch outcome {
        case .success(let result):
            var receipt: [String: JSONValue] = [
                "ran": .bool(true),
                "callbackReceived": .bool(true),
                "name": .string(args.name),
                "humanSummary": .string(args.humanSummary),
            ]
            if let result, !result.isEmpty {
                receipt["result"] = .string(result)
            }
            return .object(receipt)
        case .cancelled:
            return .object([
                "ran": .bool(false),
                "callbackReceived": .bool(true),
                "outcome": .string("cancelled"),
                "note": .string(
                    "用户在快捷指令那边取消了运行"
                ),
                "humanSummary": .string(args.humanSummary),
            ])
        case .failed(let message):
            throw DeviceToolError.failed(
                message.map {
                    "快捷指令那边回了出错：\($0)"
                } ?? "快捷指令那边回了出错"
            )
        case .noCallback:
            return .object([
                "initiated": .bool(true),
                "callbackReceived": .bool(false),
                "name": .string(args.name),
                "note": .string(
                    "已发起运行，但等了一段时间没有等到回执，不确认它跑没跑完"
                ),
                "humanSummary": .string(args.humanSummary),
            ])
        }
    }

    private func awaitCallback(
        args: ShortcutRunArgs, nonce: String
    ) async throws -> ShortcutCallbackOutcome {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                continuation in
                guard ShortcutCallbackCenter.register(
                    nonce: nonce, continuation: continuation
                ) else {
                    continuation.resume(
                        throwing: DeviceToolError.failed(
                            "上一个快捷指令还在等回执，先等它结束"
                        )
                    )
                    return
                }
                Task { @MainActor in
                    var components = URLComponents(
                        string: "shortcuts://x-callback-url/run-shortcut"
                    )
                    var items = [
                        URLQueryItem(
                            name: "name", value: args.name
                        ),
                    ]
                    if let input = args.input {
                        items.append(
                            URLQueryItem(
                                name: "input", value: input
                            )
                        )
                    }
                    let callbackBase =
                        "oneday://shortcut-callback/\(nonce)"
                    items.append(URLQueryItem(
                        name: "x-success",
                        value: callbackBase + "/success"
                    ))
                    items.append(URLQueryItem(
                        name: "x-error",
                        value: callbackBase + "/error"
                    ))
                    items.append(URLQueryItem(
                        name: "x-cancel",
                        value: callbackBase + "/cancel"
                    ))
                    components?.queryItems = items
                    guard let url = components?.url else {
                        if let pending = ShortcutCallbackCenter
                            .take(nonce: nonce) {
                            pending.resume(
                                throwing: DeviceToolError
                                    .invalidArguments(
                                        "快捷指令名打不开"
                                    )
                            )
                        }
                        return
                    }
                    UIApplication.shared.open(
                        url, options: [:]
                    ) { opened in
                        if !opened,
                           let pending = ShortcutCallbackCenter
                            .take(nonce: nonce) {
                            pending.resume(
                                throwing: DeviceToolError
                                    .failed(
                                        "没能打开快捷指令（可能没有装，或名字不对）"
                                    )
                            )
                        }
                    }
                }
                Task {
                    try? await Task.sleep(
                        for: .seconds(
                            Self.callbackTimeoutSeconds
                        )
                    )
                    if let pending = ShortcutCallbackCenter
                        .take(nonce: nonce) {
                        pending.resume(returning: .noCallback)
                    }
                }
            }
        } onCancel: {
            if let pending = ShortcutCallbackCenter.take(
                nonce: nonce
            ) {
                pending.resume(throwing: CancellationError())
            }
        }
    }

    /// 详情页本地运行（用户亲手填名运行，与工具同
    /// 一条路——回执口径一致）
    func runLocal(
        name: String
    ) async throws -> ShortcutCallbackOutcome {
        let args = ShortcutRunArgs(name: name, input: nil)
        // 本地运行不回 JSONValue，直接复用等待逻辑；
        // 在场门口径与工具一致
        guard DevicePresenceGate.acquire() else {
            throw DevicePresenceGate.busyError
        }
        let nonce = UUID().uuidString
        do {
            let outcome = try await awaitCallback(
                args: args, nonce: nonce
            )
            DevicePresenceGate.release()
            return outcome
        } catch {
            DevicePresenceGate.release()
            throw error
        }
    }
}

// MARK: - 设备信息执行器（免权限现读，设备扩容批四）

/// 设备信息快照（全 Sendable 值，详情页与工具共
/// 用）：机型标识是系统原文（如 iPhone17,2）——营
/// 销名映射表不在本层编，标识原文就是可验事实
struct DeviceInfoSnapshot: Sendable {
    let modelIdentifier: String
    let systemName: String
    let systemVersion: String
    let batteryPercent: Int?
    let batteryStateText: String
    let lowPowerMode: Bool
    let storageTotalBytes: Int64
    let storageFreeBytes: Int64
    let networkText: String
}

/// device_info：全部免权限、现读现回、不存副本。
/// 电量须开监测才读得到（开在主 actor 上、读完即
/// 是）；网络走 NWPathMonitor 一次性快照（5 秒兜
/// 底回「未知」，不编）。手机的名字与当前 Wi-Fi
/// 名称要签名权益（表面图 B7/B8），不在此列。
final class DeviceInfoEngine: @unchecked Sendable {

    func snapshot() async -> DeviceInfoSnapshot {
        let deviceFacts = await MainActor.run {
            () -> (version: String, name: String,
                   percent: Int?, stateText: String) in
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true
            let percent = device.batteryLevel >= 0
                ? Int((device.batteryLevel * 100).rounded())
                : nil
            let stateText: String
            switch device.batteryState {
            case .full: stateText = "已充满"
            case .charging: stateText = "充电中"
            case .unplugged: stateText = "未充电"
            case .unknown: stateText = "未知"
            @unknown default: stateText = "未知"
            }
            return (
                device.systemVersion, device.systemName,
                percent, stateText
            )
        }
        let storage = Self.storageFacts()
        let network = await Self.networkText()
        return DeviceInfoSnapshot(
            modelIdentifier: Self.machineIdentifier(),
            systemName: deviceFacts.name,
            systemVersion: deviceFacts.version,
            batteryPercent: deviceFacts.percent,
            batteryStateText: deviceFacts.stateText,
            lowPowerMode: ProcessInfo.processInfo
                .isLowPowerModeEnabled,
            storageTotalBytes: storage.total,
            storageFreeBytes: storage.free,
            networkText: network
        )
    }

    func infoResult(
        _ args: DeviceInfoArgs
    ) async -> JSONValue {
        let snapshot = await snapshot()
        var result: [String: JSONValue] = [
            "readAt": .string(DeviceISO8601.format(Date())),
            "model": .string("iPhone"),
            "modelIdentifier": .string(
                snapshot.modelIdentifier
            ),
            "systemName": .string(snapshot.systemName),
            "systemVersion": .string(snapshot.systemVersion),
            "batteryState": .string(snapshot.batteryStateText),
            "lowPowerMode": .bool(snapshot.lowPowerMode),
            "storageTotalBytes": .number(
                Double(snapshot.storageTotalBytes)
            ),
            "storageFreeBytes": .number(
                Double(snapshot.storageFreeBytes)
            ),
            "network": .string(snapshot.networkText),
            "humanSummary": .string("设备信息已现读"),
        ]
        if let percent = snapshot.batteryPercent {
            result["batteryPercent"] = .number(Double(percent))
        } else {
            result["batteryKnown"] = .bool(false)
        }
        return .object(result)
    }

    /// 机型标识（uname 的 machine 字段原文）
    private static func machineIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(
                to: CChar.self, capacity: 1
            ) {
                String(cString: $0)
            }
        }
    }

    private static func storageFacts()
        -> (total: Int64, free: Int64) {
        let attributes = try? FileManager.default
            .attributesOfFileSystem(forPath: NSHomeDirectory())
        let total = (attributes?[.systemSize] as? NSNumber)?
            .int64Value ?? 0
        let free = (attributes?[.systemFreeSize] as? NSNumber)?
            .int64Value ?? 0
        return (total, free)
    }

    /// 网络一次性快照：等到第一份路径状态就收（监
    /// 视随即停）；5 秒等不到如实回「未知」
    private static func networkText() async -> String {
        await withCheckedContinuation {
            (continuation: CheckedContinuation<String, Never>) in
            let box = NetworkSnapshotBox(
                continuation: continuation
            )
            let monitor = NWPathMonitor()
            box.attach(monitor)
            monitor.pathUpdateHandler = { path in
                box.finish(text: Self.networkLabel(path))
            }
            monitor.start(
                queue: DispatchQueue(
                    label: "site.didichou.oneday.deviceinfo.network"
                )
            )
            Task {
                try? await Task.sleep(for: .seconds(5))
                box.finish(text: "未知")
            }
        }
    }

    private static func networkLabel(_ path: NWPath) -> String {
        guard path.status == .satisfied else { return "离线" }
        if path.usesInterfaceType(.wifi) { return "Wi-Fi" }
        if path.usesInterfaceType(.cellular) { return "蜂窝" }
        if path.usesInterfaceType(.wiredEthernet) {
            return "有线"
        }
        return "其他网络"
    }

    /// 网络快照盒：路径回调在监视队列、超时在任务
    /// 线，两路只认第一次 finish（锁保）
    private final class NetworkSnapshotBox:
        @unchecked Sendable {
        private let lock = NSLock()
        private var continuation:
            CheckedContinuation<String, Never>?
        private var monitor: NWPathMonitor?

        init(
            continuation: CheckedContinuation<String, Never>
        ) {
            self.continuation = continuation
        }

        func attach(_ monitor: NWPathMonitor) {
            lock.lock()
            self.monitor = monitor
            lock.unlock()
        }

        func finish(text: String) {
            lock.lock()
            let continuation = self.continuation
            let monitor = self.monitor
            self.continuation = nil
            self.monitor = nil
            lock.unlock()
            guard let continuation else { return }
            monitor?.cancel()
            continuation.resume(returning: text)
        }
    }
}

// MARK: - 文件呈现桥（预览/打印，设备扩容批四）

/// QuickLook 预览与系统打印面的呈现桥（同构）：预
/// 览以用户关掉预览面为完成（DidDismiss）；打印以
/// 系统完成回调为准（completed 才是真打了，取消
/// 如实回 false、不作错误）。两件先过在场门。
enum DeviceFilePresenceBridge {

    private static let previewBox = OSAllocatedUnfairLock<
        PreviewCoordinator?
    >(initialState: nil)

    static func presentPreview(
        url: URL
    ) async throws {
        guard DevicePresenceGate.acquire() else {
            throw DevicePresenceGate.busyError
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                Task { @MainActor in
                    guard !Task.isCancelled else {
                        DevicePresenceGate.release()
                        continuation.resume(
                            throwing: CancellationError()
                        )
                        return
                    }
                    guard let presenter =
                        DeviceTopmostPresenter.topmost()
                    else {
                        DevicePresenceGate.release()
                        continuation.resume(
                            throwing: DeviceToolError.failed(
                                "现在没法打开文件预览"
                            )
                        )
                        return
                    }
                    let controller = QLPreviewController()
                    let coordinator = PreviewCoordinator(
                        continuation: continuation, url: url
                    )
                    coordinator.controller = controller
                    controller.dataSource = coordinator
                    controller.delegate = coordinator
                    previewBox.withLock { $0 = coordinator }
                    presenter.present(
                        controller, animated: true
                    )
                }
            }
        } onCancel: {
            Task { @MainActor in
                previewBox.withLock { $0 }?.cancelFromBridge()
            }
        }
    }

    private static func releasePreview() {
        previewBox.withLock { $0 = nil }
    }

    /// 打印面由系统控制器自管呈现/关闭，完成回调
    /// 就是终局；等待被取消时尽力关掉它
    static func presentPrint(
        url: URL
    ) async throws -> Bool {
        guard DevicePresenceGate.acquire() else {
            throw DevicePresenceGate.busyError
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Bool, Error>) in
                Task { @MainActor in
                    guard !Task.isCancelled else {
                        DevicePresenceGate.release()
                        continuation.resume(
                            throwing: CancellationError()
                        )
                        return
                    }
                    let controller =
                        UIPrintInteractionController.shared
                    controller.printingItem = url as NSURL
                    controller.present(animated: true) {
                        _, completed, error in
                        DevicePresenceGate.release()
                        if let error {
                            continuation.resume(
                                throwing: DeviceToolError
                                    .failed(
                                        "打印面出错了：\(error.localizedDescription)"
                                    )
                            )
                        } else {
                            continuation.resume(
                                returning: completed
                            )
                        }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                UIPrintInteractionController.shared
                    .dismiss(animated: true)
            }
        }
    }

    /// 预览协调者：数据源就是这一份文件；用户关掉
    /// 预览面（DidDismiss）即完成。QuickLook 委托要
    /// 求是非隔离的，协调者照批三协调者正形：非隔离
    /// ＋@unchecked Sendable，状态只在主线程回调与
    /// 锁盒内触碰（url 是 let、continuation 只由回
    /// 调与 finish 动）
    private final class PreviewCoordinator: NSObject,
        QLPreviewControllerDataSource,
        QLPreviewControllerDelegate, @unchecked Sendable {
        private var continuation:
            CheckedContinuation<Void, Error>?
        private let url: URL
        weak var controller: QLPreviewController?

        init(
            continuation: CheckedContinuation<Void, Error>,
            url: URL
        ) {
            self.continuation = continuation
            self.url = url
        }

        func numberOfPreviewItems(
            in controller: QLPreviewController
        ) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }

        func previewControllerDidDismiss(
            _ controller: QLPreviewController
        ) {
            finish { }
        }

        @MainActor
        func cancelFromBridge() {
            controller?.dismiss(animated: true)
            finish { throw CancellationError() }
        }

        private func finish(_ body: () throws -> Void) {
            guard let continuation else { return }
            self.continuation = nil
            DeviceFilePresenceBridge.releasePreview()
            DevicePresenceGate.release()
            continuation.resume(with: Result { try body() })
        }
    }
}

/// 文件呈现执行器：file_preview/file_print 挂既有
/// files 源（权限与开关随文件走，本层只管呈现与
/// 当场事实回执）
final class FilePresenceEngine: @unchecked Sendable {

    func preview(
        _ args: FilePreviewArgs, files: SandboxFilesEngine
    ) async throws -> JSONValue {
        let url = try files.urlForPreview(
            relativePath: args.path
        )
        try await DeviceFilePresenceBridge.presentPreview(
            url: url
        )
        return .object([
            "viewed": .bool(true),
            "path": .string(args.path),
            "humanSummary": .string(
                args.humanSummary + "，已在手机上打开给你看"
            ),
        ])
    }

    func print(
        _ args: FilePrintArgs, files: SandboxFilesEngine
    ) async throws -> JSONValue {
        let url = try files.urlForPreview(
            relativePath: args.path
        )
        let printable = await MainActor.run {
            UIPrintInteractionController.canPrint(url)
        }
        guard printable else {
            throw DeviceToolError.failed(
                "这个文件系统打印不了：\(args.path)"
            )
        }
        let printed = try await DeviceFilePresenceBridge
            .presentPrint(url: url)
        var result: [String: JSONValue] = [
            "presented": .bool(true),
            "printed": .bool(printed),
            "path": .string(args.path),
            "humanSummary": .string(args.humanSummary),
        ]
        if !printed {
            result["note"] = .string(
                "用户在打印面里取消了，没有打出来"
            )
        }
        return .object(result)
    }
}
