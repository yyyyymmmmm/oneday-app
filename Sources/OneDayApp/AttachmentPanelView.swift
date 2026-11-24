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
/// 名）：定高贴内容、照片格放大近方形、照片条改
/// 多选——点照片切换选中态（右上角勾选标记），选
/// 了至少一张时动作行上方出「添加 N 张」确认行，
/// 点之批量入待发附件条；未选时无确认行（与 Core
/// addSelectedTitle 的 nil 同源）。单张快选不回
/// 退：选 1 张点添加即走，与旧直达同效。
/// §303（A-08 定高收口）：定高机制自 §152/§154 的
/// 自造量测回路（本视图经 PreferenceKey 回报内容
/// 高→宿主状态→Core 决策→.height detent）改走
/// UIKit custom detent resolver 在呈现控制器内定
/// 高（本文件 AttachmentSheetDetentBridge）——高
/// 度由系统布局按内容理想尺寸单源求解，量测回
/// 路整套退役。SwiftUI .presentationSizing
/// (.fitted) 先行试过、经装配实测在 iPhone 底部
/// sheet 上不改变高度（§303.1），不取。
/// §327（小修批①，用户 2026-11-17 拍板）：精确贴
/// 合整套退役——custom detent resolver＋安全区反
/// 向补偿＋指纹 invalidate＋§317 过渡守卫（桥本
/// 体）全删，定高改系统 detent 档位 [.medium,
/// .large]（呈现口径见 attachmentPanelPresentat-
/// ion）；面板内容不再决定 sheet 高，确认行增减
/// 只改内容不改高。代价如实记：无库态内容约
/// 137pt、sheet 恒半高，内容顶锚、下方留白——
/// 换来的是定高零自造、与系统 sheet 行为全同构。
/// D5（台账 11）修订：定高条改系统 .height() 档
/// 位＋Core 常量纯算贴合高（三态 137/305/373＋
/// safeArea）——确认行增减时仅当用户停在贴合档
/// 才跟随 ±68pt，手动拉到 .large 后保持不拽回；
/// AX 大字体回落 [.medium, .large]。代价条（下方
/// 留白）就此注销。§327 退役四件（custom detent
/// resolver 桥、安全区反向补偿、指纹、§317 过渡
/// 守卫）仍不得复活。
/// §461（2026-11-24 用户对照 Muse 形态点定）：
/// 确认动作换位——§152 的「添加 N 张」确认行退
/// 役，同一动作（orderedSelection 批量入条）挪到
/// 面板底部、改整宽大按钮「添加 N 个附件」，饱和
/// 蓝底（Palette.primarySaturated）＋白字；呈现条
/// 件与旧行同源（未选不呈现），高度跟随差由行高
/// 52 改按钮高 56（D5 贴合档有库已选态 373→377）。
/// 照片条、勾选标记、文件/视频动作行、标题行一
/// 律不动。
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
    /// 「添加文件」（宿主收面板后开文件选择器，
    /// §317 起走 DocumentPickerView 状态旗呈现）
    let onAddFile: () -> Void
    /// 「添加视频」（宿主收面板后开视频选图器）
    let onAddVideo: () -> Void

    @State private var photoIDs: [String] = []
    @State private var thumbnails: [String: UIImage] = [:]
    /// 照片条多选选中集（§152）：面板本地态，关面
    /// 板即弃——入条只认确认动作，不留半截选择
    @State private var selectedIDs: Set<String> = []
    /// 照片条取数代次（§303／A-24 顺带）：每次
    /// loadStrip 自增；PHImageManager 回调无取消
    /// 句柄，迟到回写按代次丢弃——面板快速开关/
    /// 重载后旧代的低清图不许覆写新代结果
    @State private var stripLoadGeneration = 0
    
    /// D5：选档状态——初值回贴合档，内容态变化时
    /// 仅当停在贴合档才跟随（确认行 ±68pt），手动
    /// 拉到 .large 后保持、不拽回
    @State private var selectedDetent: PresentationDetent = .medium
    /// D5：用户是否已手动拉到 .large（开局重置、
    /// 手动拉大后置真，用于判断内容变化时是否跟随）
    @State private var userSelectedLarge = false
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
    
    /// D5：贴合档位（按当前内容态算高）
    private var fittedDetent: PresentationDetent {
        let height = AttachmentPanel.fittedSheetHeight(
            showsLibrary: showsLibrary,
            hasSelection: !selectedIDs.isEmpty
        )
        return .height(height)
    }
    
    /// D5：档位集（AX 大字体回落 [.medium, .large]、
    /// 标准字阶用 [fitted, .large]）
    private var detents: Set<PresentationDetent> {
        if dynamicTypeSize.isAccessibilitySize {
            return [.medium, .large]
        } else {
            return [fittedDetent, .large]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
            if showsLibrary {
                librarySection
            }
            actionRows
            if let confirmTitle = AttachmentPanel.addSelectedTitle(
                count: selectedIDs.count
            ) {
                confirmButton(title: confirmTitle)
            }
        }
        .padding(OneDayMetrics.spacingM)
        // D5：系统 detent 贴合档下内容恰满（不再留大
        // 片空白），仍需顶锚防内容漂浮（.large 档下
        // sheet 高仍大于内容）
        .frame(
            maxWidth: .infinity, maxHeight: .infinity,
            alignment: .topLeading
        )
        .presentationDetents(
            detents,
            selection: Binding(
                get: { selectedDetent },
                set: { newValue in
                    selectedDetent = newValue
                    // D5：追踪用户是否手动拉到 .large
                    userSelectedLarge = (newValue == .large)
                }
            )
        )
        .presentationDragIndicator(.visible)
        .task {
            loadStrip()
            // D5：开局回贴合档
            userSelectedLarge = false
            selectedDetent = fittedDetent
        }
        .onChange(of: selectedIDs.isEmpty) { _, _ in
            // D5：确认按钮增减时，仅当用户停在贴合档才
            // 跟随新高度（±72pt 系统动画过渡）；已拉到 .large
            // 不拽回；AX 档不自动跟随（回落 .medium 固定高）
            if !userSelectedLarge && !dynamicTypeSize.isAccessibilitySize {
                selectedDetent = fittedDetent
            }
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
                .frame(
                    width: AttachmentPanel.Layout.cellSize,
                    height: AttachmentPanel.Layout.cellSize
                )
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
                .frame(
                    width: AttachmentPanel.Layout.cellSize,
                    height: AttachmentPanel.Layout.cellSize
                )
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

    // MARK: - 确认按钮（§152 多选、§461 底部大按钮）

    /// 「添加 N 个附件」确认按钮（§461）：§152 确认
    /// 行的同一动作挪到面板底部、改整宽大按钮——
    /// 饱和蓝底（Palette.primarySaturated）＋白字，
    /// 标题带实时已选计数；点之按条内呈现序批量入
    /// 条（Core 收口，与旧行接线逐字相同）
    private func confirmButton(title: String) -> some View {
        Button {
            onConfirmPhotos(
                AttachmentPanel.orderedSelection(
                    selected: selectedIDs, stripOrder: photoIDs
                )
            )
        } label: {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(
                    height: AttachmentPanel.Layout.confirmButtonHeight
                )
                .background(
                    Palette.primarySaturated,
                    in: RoundedRectangle(
                        cornerRadius: OneDayMetrics.radiusPreview
                    )
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: OneDayMetrics.radiusPreview
                    )
                )
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
            .frame(minHeight: AttachmentPanel.Layout.rowHeight)
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
        stripLoadGeneration += 1
        let generation = stripLoadGeneration
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
        let side = AttachmentPanel.Layout.cellSize * 2
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
                    // A-24：代次已过（重载/快速开关后
                    // 旧请求迟到）一律丢弃，不覆写新代
                    guard generation == stripLoadGeneration
                    else { return }
                    thumbnails[id] = image
                }
            }
        }
    }
}

extension View {
    /// 附件面板呈现口径单源（D5 起弃用）——D5 起
    /// presentation modifiers 在 AttachmentPanelView
    /// 本体内施加（需访问视图状态算 fitted 档），
    /// ChatView 呈现点只需 .sheet() 本体、不再调本
    /// 方法。本方法保留供装配测试引用旧口径
    func attachmentPanelPresentation() -> some View {
        self
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }
}
