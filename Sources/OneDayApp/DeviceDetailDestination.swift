import OneDayCore
import SwiftUI

/// 设备详情分发（台账 198 收敛 S1）：DeviceSourceID
/// → 详情页的唯一映射——此前连接器页（sheet 呈现、
/// 五件传 inSheet）与设备与权限页（导航呈现）各持
/// 一份同构 switch，详情页增减时两处要同步改、漏
/// 一处即一面点不进。自此单源：呈现形态只差 inSheet
/// 一参（五件带标记的详情页在 sheet 里下拉手势归
/// 关闭、不被下拉刷新截走；导航呈现恒 false）。
/// .health/.home 待签名权益、无详情页，映射
/// EmptyView——调用方以 descriptor.isWired 守门、
/// 本就不给这两件入口。
struct DeviceDetailDestination: View {
    let source: DeviceSourceID
    var inSheet = false

    var body: some View {
        switch source {
        case .calendar: CalendarDetailView(inSheet: inSheet)
        case .reminders: RemindersDetailView(inSheet: inSheet)
        case .contacts: ContactsDetailView(inSheet: inSheet)
        case .photos: PhotosDetailView(inSheet: inSheet)
        case .motion: MotionDetailView(inSheet: inSheet)
        case .clipboard: ClipboardDetailView()
        case .files: FilesDetailView()
        case .alarm: AlarmDetailView()
        case .notifications: NotificationsDetailView()
        case .opener: OpenTargetDetailView()
        case .camera: CameraDetailView()
        case .vision: VisionDetailView()
        case .translate: TranslateDetailView()
        case .ondevice: OnDeviceDetailView()
        case .biometric: BiometricDetailView()
        case .location: LocationDetailView()
        case .media: MediaDetailView()
        case .compose: ComposeDetailView()
        case .shortcuts: ShortcutsDetailView()
        case .deviceinfo: DeviceInfoDetailView()
        case .health, .home: EmptyView()
        }
    }
}
