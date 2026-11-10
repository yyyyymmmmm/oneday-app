import Contacts
import EventKit
import Foundation
import OneDayCore
import Photos

/// 系统变更观察（0.36.18，自动同步触发②）：日历/
/// 提醒的 EKEventStoreChanged、通讯录的 CNContact-
/// StoreDidChange、照片的 PHPhotoLibraryChange-
/// Observer——数据在 App 活着时变了，落一个记号给
/// 同步控制器防抖对账。步数没有系统变更通知，不
/// 在此列（靠回前台＋节流）。
///
/// 回调隔离铁律的落点：本类 nonisolated、不继承
/// 任何 actor 隔离。EK/CN 的块观察注册时指定主队
/// 列投递；照片回调的投递队列不固定，回调里只做
/// 一件事——把信号转手到主队列，不碰任何状态。
/// onChange 因此只在主队列被调用；赋值只在控制
/// 器初始化时发生一次、之后不再改
final class DeviceChangeWatcher: NSObject,
    PHPhotoLibraryChangeObserver, @unchecked Sendable
{
    var onChange: ((DeviceSyncDataset) -> Void)?
    private var tokens: [NSObjectProtocol] = []

    override init() {
        super.init()
        let center = NotificationCenter.default
        tokens.append(center.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            // 日历与提醒同属一个 EventStore：一次变
            // 更两个数据集都落记，对账时各自判节流
            self?.onChange?(.calendar)
            self?.onChange?(.reminders)
        })
        tokens.append(center.addObserver(
            forName: .CNContactStoreDidChange, object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onChange?(.contacts)
        })
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(.photos)
        }
    }
}
