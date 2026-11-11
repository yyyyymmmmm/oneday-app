import OneDayCore
import OneDayDesign
import Photos
import SwiftUI
import UIKit

/// 附件面板（§147，用户 2026-11-11 19:01 点题改版）：
/// 「+」点开自底部升起的 sheet，照 Muse 形态——
/// 顶部「资源库」区（左标题、右「查看全部」蓝链）＋
/// 横滑缩略图条（首格相机、其后最近照片，点任意一
/// 张直接进待发附件条）；下半动作行「添加文件／添
/// 加视频」。取代旧浮窗小卡 Menu（三行）整套。
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
    /// 照片条点选一张（入参资产 localIdentifier）
    let onPickPhoto: (String) -> Void
    /// 「查看全部」（宿主收面板后开全量选图器）
    let onViewAll: () -> Void
    /// 「添加文件」（宿主走 DocumentPickerBridge）
    let onAddFile: () -> Void
    /// 「添加视频」（宿主收面板后开视频选图器）
    let onAddVideo: () -> Void

    @State private var photoIDs: [String] = []
    @State private var thumbnails: [String: UIImage] = [:]

    /// 照片条格边长（形态值，照 Muse 截图方格口径；
    /// 间距仍走 OneDayMetrics 梯队）
    private static let cellSize: CGFloat = 76

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
            actionRows
        }
        .padding(OneDayMetrics.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .font(.system(size: 26, weight: .regular))
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
        Button {
            onPickPhoto(id)
        } label: {
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
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard)
            )
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel("照片")
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
