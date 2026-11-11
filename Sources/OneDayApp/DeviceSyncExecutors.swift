import CoreMotion
import Foundation
import OneDayCore
import Photos

/// 照片/步数的权限翻译与引擎（0.36.14 同步制）：
/// 照片走 PhotoKit（只读清单元数据）、步数走
/// CoreMotion 计步（只读按日合计）。授权铁律在本
/// 文件的请求口落死：先同步读当前状态；状态已决
/// 定（已授权/已拒绝）时绝不重走异步请求；只有真
/// 未决定才发那一次请求——计步没有单独的请求口，
/// 那一次请求就是一次查询本身。

extension DevicePermissions {
    static func photosState() -> DevicePermissionState {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: return .granted
        case .limited: return .limited
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    static func motionState() -> DevicePermissionState {
        switch CMPedometer.authorizationStatus() {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    /// 照片授权请求：仅未决定时发那一次
    static func requestPhotosAccess() async -> DevicePermissionState {
        guard photosState() == .notDetermined else {
            return photosState()
        }
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return photosState()
    }

    /// 计步授权请求：仅未决定时用一次今日查询触发
    /// 系统询问，查完同步重读状态
    static func requestMotionAccess() async -> DevicePermissionState {
        guard motionState() == .notDetermined else {
            return motionState()
        }
        let engine = MotionEngine()
        let today = SyncMotionPlan.dayRanges(now: Date()).last
        if let today {
            _ = try? await engine.queryDay(
                start: today.start, end: Date()
            )
        }
        return motionState()
    }

    /// 同步引擎用的统一请求口（按件分发；已决定直
    /// 接回读现态，不发请求）
    static func requestAccess(
        for source: DeviceSourceID
    ) async -> DevicePermissionState {
        switch source {
        case .photos: return await requestPhotosAccess()
        case .motion: return await requestMotionAccess()
        case .calendar:
            let engine = EventKitEngine()
            return await engine.requestCalendarAccess()
        case .reminders:
            let engine = EventKitEngine()
            return await engine.requestRemindersAccess()
        case .contacts:
            let engine = ContactsEngine()
            return await engine.requestAccess()
        case .clipboard, .files, .opener:
            // 无系统权限概念：没有可发的系统请求，
            // 现态即 notApplicable
            return .notApplicable
        case .alarm:
            // AlarmKit 授权走引擎的过门落法（同步读
            // 现态、只有未决定才发那一次请求）
            let engine = AlarmEngine()
            return await engine.requestAccess()
        case .notifications:
            let engine = NotificationEngine()
            return await engine.requestAccess()
        case .health, .home:
            return .notDetermined
        }
    }
}

// MARK: - 照片引擎（只读清单元数据）

/// 照片引擎：整本资产的元数据索引读取。原图、缩
/// 略图、经纬度一律不碰——hasLocation 只取「有没
/// 有位置」这个布尔。相册名靠相册成员关系反查（资
/// 产本体不带相册信息），只查用户相册、首个命中
/// 为准
final class PhotosEngine: @unchecked Sendable {
    /// 本地计数（详情页内容区）：照片/视频各多少
    func localSummary() -> (total: Int, photos: Int, videos: Int) {
        let images = PHAsset.fetchAssets(
            with: .image, options: nil
        ).count
        let videos = PHAsset.fetchAssets(
            with: .video, options: nil
        ).count
        return (images + videos, images, videos)
    }

    /// 整本索引记录（按创建时间升序；受限授权下
    /// 系统只给勾选子集，枚举天然收敛）
    func collectRecords() -> [SyncPhotoRecord] {
        let albumByAsset = albumNamesByAssetID()
        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: true),
        ]
        let all = PHAsset.fetchAssets(with: options)
        var records: [SyncPhotoRecord] = []
        records.reserveCapacity(all.count)
        all.enumerateObjects { asset, _, _ in
            records.append(Self.record(
                asset,
                albumName: albumByAsset[asset.localIdentifier]
            ))
        }
        return records
    }

    private static func record(
        _ asset: PHAsset, albumName: String?
    ) -> SyncPhotoRecord {
        let mediaType = asset.mediaType == .video ? "video" : "photo"
        let subtypes = asset.mediaSubtypes
        let subtype: String?
        if subtypes.contains(.photoScreenshot) {
            subtype = "screenshot"
        } else if subtypes.contains(.photoLive) {
            subtype = "livePhoto"
        } else if subtypes.contains(.photoPanorama) {
            subtype = "panorama"
        } else if subtypes.contains(.videoTimelapse) {
            subtype = "timelapse"
        } else if subtypes.contains(.videoHighFrameRate) {
            // 高帧率即慢动作素材（PhotoKit 的口径）
            subtype = "slowMotion"
        } else {
            subtype = nil
        }
        return SyncPhotoRecord(
            assetId: asset.localIdentifier,
            // 极少数资产没有创建时间：以零点占位保
            // 全量（索引缺一项比时间不准更伤，规格
            // 「授权了就给全量」）
            createdAt: asset.creationDate
                ?? Date(timeIntervalSince1970: 0),
            mediaType: mediaType,
            subtype: subtype,
            width: asset.pixelWidth,
            height: asset.pixelHeight,
            durationSec: asset.mediaType == .video
                ? asset.duration : nil,
            isFavorite: asset.isFavorite,
            albumName: albumName,
            hasLocation: asset.location != nil
        )
    }

    /// 相册名反查：逐个用户相册取成员标识建映射
    /// （首个命中为准）；取不到相册就回空表（相册
    /// 名只是记录的一个字段，缺了不拦整本同步）
    private func albumNamesByAssetID() -> [String: String] {
        var map: [String: String] = [:]
        let albums = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: nil
        )
        albums.enumerateObjects { collection, _, _ in
            guard let title = collection.localizedTitle,
                  !title.isEmpty else { return }
            let assets = PHAsset.fetchAssets(
                in: collection, options: nil
            )
            assets.enumerateObjects { asset, _, _ in
                if map[asset.localIdentifier] == nil {
                    map[asset.localIdentifier] = title
                }
            }
        }
        return map
    }
}

// MARK: - 步数引擎（手机计步按日合计）

/// 步数引擎：CMPedometer 逐日查询。数据只保留最
/// 近约 7 天（系统口径），同步按日送出、伴生按日
/// 合并攒长历史。逐日值在本引擎内拆成 Sendable
/// 值再过异步边界（CMPedometerData 本身不跨线）
final class MotionEngine: @unchecked Sendable {
    private let pedometer = CMPedometer()

    var isStepCountingAvailable: Bool {
        CMPedometer.isStepCountingAvailable()
    }

    struct DaySample: Sendable {
        let steps: Int
        let distanceM: Double?
        let flights: Int?
    }

    func queryDay(start: Date, end: Date) async throws -> DaySample {
        try await withCheckedThrowingContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) {
                data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: DaySample(
                        steps: data.numberOfSteps.intValue,
                        distanceM: data.distance?.doubleValue,
                        flights: data.floorsAscended?.intValue
                    ))
                } else {
                    continuation.resume(throwing: DeviceToolError.failed(
                        "计步没有返回数据"
                    ))
                }
            }
        }
    }

    /// 最近 7 天的逐日记录（今天收在当前时刻：查
    /// 未来时段计步会报错）；单日查询失败不拖垮
    /// 整批——跳过该日、余日照送（副本靠合并攒，
    /// 缺一天下次补得回来）
    func recentDays() async -> [SyncMotionDayRecord] {
        var records: [SyncMotionDayRecord] = []
        for range in SyncMotionPlan.dayRanges(now: Date()) {
            let end = min(range.end, Date())
            guard end > range.start else { continue }
            guard let sample = try? await queryDay(
                start: range.start, end: end
            ) else { continue }
            records.append(SyncMotionDayRecord(
                date: range.day,
                steps: sample.steps,
                distanceM: sample.distanceM,
                flights: sample.flights
            ))
        }
        return records
    }
}
