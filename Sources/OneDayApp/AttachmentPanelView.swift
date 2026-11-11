import OneDayCore
import OneDayDesign
import Photos
import SwiftUI
import UIKit

/// 附件面板（§147 立、§152 修订二）：「+」点开自底部
/// 升起的 sheet，照 Muse 形态——顶部「资源库」区
/// （左标题、右「查看全部」蓝链）＋横滑缩略图条
/// （首格相机、其后最近照片）；下半动作行「添加文
/// 件／添加视频」。§152 修订（用户 19:47 对照截图点
/// 名）：定高贴内容（宿主 detent 量本视图内容高、
/// 见 AttachmentPanelLayout）、照片格放大近方形、
/// 照片条改多选——点照片切换选中态（右上角勾选标
/// 记），选了至少一张时动作行上方出「添加 N 张」
/// 确认行，点之批量入待发附件条；未选时无确认行
/// （与 Core addSelectedTitle 的 nil 同源）。单张快
/// 选不回退：选 1 张点添加即走，与旧直达同效。
///
/// 授权纪律：照片条只同步读 PHPhotoLibrary 现态
/// （系统授权铁律：已决定绝不重走请求、未决定也不
/// 在此发请求——本面板不是授权流）；未授权时资源
/// 库区整段不显，动作行照常（选图器由系统代管、
/// 不需本 App 相册授权）。有限授权下 PHAsset 取数
/// 天然只回已授权子集，不另过滤。缩略图与原图数
/// 据都走 PHImageManager 既有系统通道。
struct AttachmentPanelView: View {
    /// 相机格点选（宿主收面板后开相机）
    let onCamera: () -> Void
    /// 确认批量入条（入参资产 localIdentifier 数组，
    /// 按照片条呈现序——Core orderedSelection 收口）
    let onConfirmPhotos: ([String]) -> Void
    /// 「查看全部」（宿主收面板后开全量选图器）
    let onViewAll: () -> Void
    /// 「添加文件」（宿主走 DocumentPickerBridge）
    let onAddFile: () -> Void
    /// 「添加视频」（宿主收面板后开视频选图器）
    let onAddVideo: () -> Void

    @State private var photoIDs: [String] = []
    @State private var thumbnails: [String: UIImage] = [:]
    /// 照片条多选选中集（§152）：面板本地态，关面
    /// 板即弃——入条只认确认动作，不留半截选择
    @State private var selectedIDs: Set<String> = []

    /// 照片条格边长（形态值，§152 修订：照 Muse 截
    /// 图近方形大格口径自 §147 的 76 放大；对屏宽约
    /// 390 的实测占比约 30%，一屏约 3 格＋露边引导横
    /// 滑；间距仍走 OneDayMetrics 梯队）
    private static let cellSize: CGFloat = 118

    /// 同步读现态（不在此发任何授权请求）
    private var photoAccess: AttachmentPanel.PhotoAccess {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: return .authorized
        case .limited: return .limited
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    private var showsLibrary: Bool {
        AttachmentPanel.showsLibrary(access: photoAccess)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
            if showsLibrary {
                librarySection
            }
            if let confirmTitle = AttachmentPanel.addSelectedTitle(
                count: selectedIDs.count
            ) {
                confirmRow(title: confirmTitle)
            }
            actionRows
        }
        .padding(OneDayMetrics.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { proxy in
            Color.clear.preference(
                key: AttachmentPanelHeightKey.self,
                value: proxy.size.height
            )
        })
        .task {
            loadStrip()
        }
    }

    // MARK: - 资源库区

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
            HStack {
                Text("资源库")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button("查看全部") { onViewAll() }
                    .font(.body)
                    .foregroundStyle(Palette.primary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ForEach(
                        AttachmentPanel.stripCells(photoIDs: photoIDs),
                        id: \.self
                    ) { cell in
                        switch cell {
                        case .camera:
                            cameraCell
                        case .photo(let id):
                            photoCell(id: id)
                        }
                    }
                }
            }
        }
    }

    private var cameraCell: some View {
        Button {
            onCamera()
        } label: {
            Image(systemName: "camera")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Palette.ink)
                .frame(width: Self.cellSize, height: Self.cellSize)
                .background(
                    Palette.bubbleFill,
                    in: RoundedRectangle(
                        cornerRadius: OneDayMetrics.radiusCard
                    )
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: OneDayMetrics.radiusCard
                    )
                )
        }
        .buttonStyle(.odPressable)
        .disabled(
            !UIImagePickerController.isSourceTypeAvailable(.camera)
        )
        .accessibilityLabel("拍照")
    }

    private func photoCell(id: String) -> some View {
        let selected = selectedIDs.contains(id)
        return Button {
            selectedIDs = AttachmentPanel.toggledSelection(
                selectedIDs, id: id
            )
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = thumbnails[id] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Palette.bubbleFill
                    }
                }
                .frame(width: Self.cellSize, height: Self.cellSize)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: OneDayMetrics.radiusCard
                    )
                )
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Palette.primary)
                        .padding(OneDayMetrics.spacingXS)
                        .shadow(radius: 2)
                }
            }
            .contentShape(
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard)
            )
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel("照片")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - 确认行（§152 多选）

    /// 「添加 N 张」确认行：照动作行形态（图标＋标
    /// 题行、minHeight 同档），标题带实时已选计数；
    /// 点之按条内呈现序批量入条（Core 收口）
    private func confirmRow(title: String) -> some View {
        Button {
            onConfirmPhotos(
                AttachmentPanel.orderedSelection(
                    selected: selectedIDs, stripOrder: photoIDs
                )
            )
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Palette.primary)
                    .frame(width: 28)
                Text(title)
                    .font(.body)
                    .foregroundStyle(Palette.primary)
                Spacer()
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    // MARK: - 动作行

    private var actionRows: some View {
        VStack(spacing: 0) {
            actionRow(icon: "paperclip", title: "添加文件") {
                onAddFile()
            }
            Divider()
                .overlay(Palette.separator)
            actionRow(icon: "play.circle", title: "添加视频") {
                onAddVideo()
            }
        }
    }

    private func actionRow(
        icon: String, title: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 28)
                Text(title)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    // MARK: - 照片条取数

    /// 取最近照片 id（创建时间倒序、上限 Core 定版）
    /// ＋逐格缩略图：fetch 在有限授权下只回已授权子
    /// 集（系统收敛）；缩略图走 PHImageManager 机
    /// 会式交付、先低清后高清同格替换
    private func loadStrip() {
        guard showsLibrary else { return }
        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]
        options.fetchLimit = AttachmentPanel.stripPhotoLimit
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var ids: [String] = []
        var assets: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in
            ids.append(asset.localIdentifier)
            assets[asset.localIdentifier] = asset
        }
        photoIDs = ids
        let manager = PHImageManager.default()
        let thumbOptions = PHImageRequestOptions()
        thumbOptions.deliveryMode = .opportunistic
        thumbOptions.resizeMode = .fast
        let side = Self.cellSize * 2
        for id in ids {
            guard let asset = assets[id] else { continue }
            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill,
                options: thumbOptions
            ) { image, _ in
                guard let image else { return }
                Task { @MainActor in
                    thumbnails[id] = image
                }
            }
        }
    }
}
