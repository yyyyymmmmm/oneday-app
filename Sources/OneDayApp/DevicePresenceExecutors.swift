import AVFoundation
import Foundation
import FoundationModels
import ImageIO
import LocalAuthentication
import OneDayCore
import Translation
import UIKit
import Vision
import VisionKit
import os

/// 在场交互与端上智能的执行层（设备扩容批三，
/// §114）：相机/识别/翻译/端上模型/本人确认五件。
/// 这一批的共同点是「要么用户在场、要么纯端上计
/// 算」——取景与确认由系统界面当面完成（App 只能
/// 发起、不能代办），识别/翻译/端上回答全程不出
/// 手机。授权分档与前两批严格同规：相机是真系统
/// 权限（过 DevicePermissionGate、先同步读现态、
/// 只有未决定才发那一次请求）；其余四件没有可开
/// 关的系统权限，状态恒 notApplicable、调用开关即
/// 唯一的门（端上智能另有机型可用性门，见引擎注记）。

// MARK: - 在场呈现桥（拍照/文档扫描）

/// 系统取景界面的呈现桥：分发器跑在非 UI 上下文，
/// 呈现统一收在这里——自当前最顶层 VC 呈现
/// （DocumentPickerBridge 同款走法，绕开 SwiftUI
/// 呈现上下文）、coordinator 静态强持有到回调为
/// 止、回调先 dismiss 再交回。等待被取消（桥侧超
/// 时掐断）时经 cancelActive 收尾：关界面、以取消
/// 错误返回，不留悬空取景框。
enum DeviceCaptureBridge {

    private static let photoBox =
        OSAllocatedUnfairLock<PhotoCoordinator?>(initialState: nil)
    private static let scanBox =
        OSAllocatedUnfairLock<ScanCoordinator?>(initialState: nil)

    // MARK: 拍照

    static func capturePhoto() async throws -> Data {
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Task { @MainActor in
                    // 可用性类方法是主 actor 隔离的，只能在
                    // 主 actor 上问（同理见下方文档扫描）
                    guard UIImagePickerController
                        .isSourceTypeAvailable(.camera)
                    else {
                        continuation.resume(throwing: DeviceToolError
                            .failed("这台手机现在用不了相机"))
                        return
                    }
                    guard !Task.isCancelled else {
                        continuation.resume(
                            throwing: CancellationError()
                        )
                        return
                    }
                    guard let presenter = topmostViewController()
                    else {
                        continuation.resume(throwing: DeviceToolError
                            .failed("现在没法打开相机界面"))
                        return
                    }
                    let picker = UIImagePickerController()
                    picker.sourceType = .camera
                    let coordinator = PhotoCoordinator(
                        continuation: continuation
                    )
                    picker.delegate = coordinator
                    coordinator.picker = picker
                    photoBox.withLock { $0 = coordinator }
                    presenter.present(picker, animated: true)
                }
            }
        } onCancel: {
            Task { @MainActor in
                photoBox.withLock { $0 }?.cancelFromBridge()
            }
        }
    }

    private static func releasePhoto() {
        photoBox.withLock { $0 = nil }
    }

    // MARK: 文档扫描

    static func scanDocument() async throws -> [Data] {
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Task { @MainActor in
                    guard VNDocumentCameraViewController.isSupported
                    else {
                        continuation.resume(throwing: DeviceToolError
                            .failed("这台手机不支持文档扫描"))
                        return
                    }
                    guard !Task.isCancelled else {
                        continuation.resume(
                            throwing: CancellationError()
                        )
                        return
                    }
                    guard let presenter = topmostViewController()
                    else {
                        continuation.resume(throwing: DeviceToolError
                            .failed("现在没法打开扫描界面"))
                        return
                    }
                    let controller =
                        VNDocumentCameraViewController()
                    let coordinator = ScanCoordinator(
                        continuation: continuation
                    )
                    controller.delegate = coordinator
                    coordinator.controller = controller
                    scanBox.withLock { $0 = coordinator }
                    presenter.present(controller, animated: true)
                }
            }
        } onCancel: {
            Task { @MainActor in
                scanBox.withLock { $0 }?.cancelFromBridge()
            }
        }
    }

    private static func releaseScan() {
        scanBox.withLock { $0 = nil }
    }

    /// 沿 presentedViewController 链走到当前最顶层
    /// VC（DocumentPickerBridge 同款走法）
    @MainActor
    private static func topmostViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let keyWindow = windows.first { $0.isKeyWindow } ?? windows.first
        var controller = keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    // MARK: 协调者（delegate 弱引用，靠上面的静态盒强持有到回调）

    // 协调者的可变状态只在主 actor 的回调与锁盒存取里
    // 触碰（delegate 回调恒主线程、取消路径也走主
    // actor 任务），故显式 @unchecked Sendable 入锁盒
    private final class PhotoCoordinator: NSObject,
        UIImagePickerControllerDelegate,
        UINavigationControllerDelegate, @unchecked Sendable {
        private var continuation:
            CheckedContinuation<Data, Error>?
        weak var picker: UIImagePickerController?

        init(continuation: CheckedContinuation<Data, Error>) {
            self.continuation = continuation
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info:
                [UIImagePickerController.InfoKey: Any]
        ) {
            let data = (info[.originalImage] as? UIImage)?
                .jpegData(compressionQuality: 0.85)
            picker.dismiss(animated: true)
            DeviceCaptureBridge.releasePhoto()
            finish {
                guard let data else {
                    throw DeviceToolError.failed("照片没有取到数据")
                }
                return data
            }
        }

        func imagePickerControllerDidCancel(
            _ picker: UIImagePickerController
        ) {
            picker.dismiss(animated: true)
            DeviceCaptureBridge.releasePhoto()
            finish {
                throw DeviceToolError.failed(
                    "拍照取消了，没有拍下照片"
                )
            }
        }

        /// 等待方被取消时收尾：关界面、以取消错误返回
        @MainActor
        func cancelFromBridge() {
            picker?.dismiss(animated: true)
            DeviceCaptureBridge.releasePhoto()
            finish { throw CancellationError() }
        }

        private func finish(_ body: () throws -> Data) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(with: Result { try body() })
        }
    }

    private final class ScanCoordinator: NSObject,
        VNDocumentCameraViewControllerDelegate,
        @unchecked Sendable {
        private var continuation:
            CheckedContinuation<[Data], Error>?
        weak var controller: VNDocumentCameraViewController?

        init(continuation: CheckedContinuation<[Data], Error>) {
            self.continuation = continuation
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let pages = (0..<scan.pageCount).compactMap {
                scan.imageOfPage(at: $0)
                    .jpegData(compressionQuality: 0.85)
            }
            controller.dismiss(animated: true)
            DeviceCaptureBridge.releaseScan()
            finish {
                guard !pages.isEmpty else {
                    throw DeviceToolError.failed(
                        "扫描没有得到任何一页"
                    )
                }
                return pages
            }
        }

        func documentCameraViewControllerDidCancel(
            _ controller: VNDocumentCameraViewController
        ) {
            controller.dismiss(animated: true)
            DeviceCaptureBridge.releaseScan()
            finish {
                throw DeviceToolError.failed(
                    "扫描取消了，没有保存任何一页"
                )
            }
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            controller.dismiss(animated: true)
            DeviceCaptureBridge.releaseScan()
            finish {
                throw DeviceToolError.failed(
                    "扫描没成功：\(error.localizedDescription)"
                )
            }
        }

        @MainActor
        func cancelFromBridge() {
            controller?.dismiss(animated: true)
            DeviceCaptureBridge.releaseScan()
            finish { throw CancellationError() }
        }

        private func finish(_ body: () throws -> [Data]) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(with: Result { try body() })
        }
    }
}

// MARK: - 相机执行器（拍照/文档扫描，设备扩容批三）

/// 相机是真系统权限：authorizationStatus 同步可读，
/// 先读现态过 Core 的 DevicePermissionGate，只有未
/// 决定才发那一次请求（系统授权铁律）；请求回调只
/// resume continuation，不碰引擎其他状态（回调隔离
/// 铁律）。拍照/扫描的产物统一落 OneDay 文件夹的
/// captures/ 子目录、写后回读核对才报成功；智能体
/// 只能发起，取景与快门永远在用户手里。
final class CameraEngine: @unchecked Sendable {
    private let files: SandboxFilesEngine

    init(files: SandboxFilesEngine) {
        self.files = files
    }

    static func systemState() -> DevicePermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    /// 详情页权限开关/同步口共用的请求口：过门决策
    /// ——只有 requestOnce 才真发请求，其余档只回读
    func requestAccess() async -> DevicePermissionState {
        let current = Self.systemState()
        guard OneDayCore.DevicePermissionGate.decision(for: current)
            == .requestOnce else { return current }
        _ = await withCheckedContinuation {
            (continuation: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
        return Self.systemState()
    }

    /// 文件名印记：时刻＋四位随机后缀（同秒连拍不撞名）
    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
            + "-" + String(UUID().uuidString.prefix(4)).lowercased()
    }

    private func requireUsable() throws {
        let state = Self.systemState()
        guard state.isUsable else {
            throw DeviceToolError.permissionDenied(
                "相机的系统权限当前是「\(state.label)」，无法拍照"
            )
        }
    }

    /// 拍一张并存进 captures/（工具与详情页本地按钮
    /// 共用同一条路：取景→JPEG→落盘回读核对）
    func captureAndSave() async throws -> DeviceFileItem {
        let data = try await DeviceCaptureBridge.capturePhoto()
        return try files.saveCapture(
            data: data, fileName: "photo-\(Self.stamp()).jpg"
        )
    }

    /// camera_capture：发起拍照，用户拍完的图片存进
    /// OneDay 文件夹，回执带文件回读元数据（路径/大
    /// 小/时刻）——图片本体不塞进回执（体积口径与
    /// files_read 的 256 KB 上限同理），要「看」这张
    /// 图接着调 vision_ocr 识别即可（§114 组合口径）
    func capturePhoto(
        _ args: CameraCaptureArgs
    ) async throws -> (objectID: String, result: JSONValue) {
        try requireUsable()
        let item = try await captureAndSave()
        var result = SandboxFilesEngine.fileObject(item)
        result["saved"] = .bool(true)
        result["verified"] = .bool(true)
        result["capturedAt"] = .string(
            DeviceISO8601.format(item.modifiedAt)
        )
        result["humanSummary"] = .string(
            args.humanSummary + "，已存进 OneDay 文件夹：\(item.path)"
        )
        return (item.path, .object(result))
    }

    /// vision_document_scan：系统扫描界面当面扫多页，
    /// 逐页存 captures/scan-<印记>-p<页>.jpg；账本
    /// objectID＝这批页的共同前缀，回放时按前缀找回
    func scanDocument(
        _ args: VisionDocumentScanArgs
    ) async throws -> (objectID: String, result: JSONValue) {
        try requireUsable()
        let pagesData = try await DeviceCaptureBridge.scanDocument()
        guard !pagesData.isEmpty else {
            throw DeviceToolError.failed("扫描没有得到任何一页")
        }
        let stamp = Self.stamp()
        var pages: [[String: JSONValue]] = []
        for (index, data) in pagesData.enumerated() {
            let item = try files.saveCapture(
                data: data,
                fileName: "scan-\(stamp)-p\(index + 1).jpg"
            )
            pages.append(SandboxFilesEngine.fileObject(item))
        }
        let prefix = "captures/scan-\(stamp)"
        return (prefix, .object([
            "saved": .bool(true),
            "verified": .bool(true),
            "pageCount": .number(Double(pages.count)),
            "pages": .array(pages.map { .object($0) }),
            "humanSummary": .string(
                args.humanSummary
                    + "，共 \(pages.count) 页，已存进 OneDay 文件夹"
            ),
        ]))
    }

    /// 幂等回放/详情页共用：按前缀找回某次扫描的页
    /// （还在的才列，不在不编）
    func scanPages(prefix: String) -> [DeviceFileItem] {
        files.captureItems()
            .filter { $0.path.hasPrefix(prefix) }
            .sorted { $0.path < $1.path }
    }
}

// MARK: - 识别执行器（文字/条码，设备扩容批三）

/// Vision 端上识别：输入只认 OneDay 文件夹里的图片
/// （与 files_read 同一条沙盒边界，路径在 Core 解析
/// 层已规范化）；识别在本地完成、图片不出手机。走
/// iOS 18+ 的 Swift 原生请求 API（RecognizeText-
/// Request/DetectBarcodesRequest，苹果现行推荐形）；
/// EXIF 方向随图带入，竖拍照片不横着认。
final class VisionEngine: @unchecked Sendable {
    private let files: SandboxFilesEngine

    init(files: SandboxFilesEngine) {
        self.files = files
    }

    struct RecognizedText: Sendable {
        let text: String
        let lineCount: Int
        let truncated: Bool
    }

    /// 图片解码（ImageIO）：CGImage＋EXIF 方向；读
    /// 不出图如实报错，不猜
    private func loadImage(
        path: String
    ) throws -> (image: CGImage, orientation: CGImagePropertyOrientation) {
        let data = try files.readData(
            relativePath: path,
            maxBytes: PresenceLimits.maxImageBytes
        )
        guard let source = CGImageSourceCreateWithData(
                data as CFData, nil
              ),
              let image = CGImageSourceCreateImageAtIndex(
                source, 0, nil
              )
        else {
            throw DeviceToolError.failed("这张图片读不出来：\(path)")
        }
        var orientation: CGImagePropertyOrientation = .up
        if let properties = CGImageSourceCopyPropertiesAtIndex(
                source, 0, nil
            ) as? [CFString: Any],
           let raw = properties[kCGImagePropertyOrientation]
                as? UInt32,
           let parsed = CGImagePropertyOrientation(rawValue: raw) {
            orientation = parsed
        }
        return (image, orientation)
    }

    /// 认文字（工具与识别详情页本地试认共用）：简体
    /// 中文＋英文双语种、精确级；结果按行拼全文，行
    /// 数/字数超限截断并如实标 truncated
    func recognizeText(path: String) async throws -> RecognizedText {
        let (image, orientation) = try loadImage(path: path)
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [
            Locale.Language(identifier: "zh-Hans"),
            Locale.Language(identifier: "en-US"),
        ]
        let observations: [RecognizedTextObservation]
        do {
            observations = try await request.perform(
                on: image, orientation: orientation
            )
        } catch {
            throw DeviceToolError.failed(
                "识别没能完成：\(error.localizedDescription)"
            )
        }
        var lines: [String] = []
        for observation in observations {
            if let candidate = observation.topCandidates(1).first {
                lines.append(candidate.string)
            }
        }
        var truncated = false
        if lines.count > PresenceLimits.maxRecognizedLines {
            lines = Array(
                lines.prefix(PresenceLimits.maxRecognizedLines)
            )
            truncated = true
        }
        var text = lines.joined(separator: "\n")
        if text.count > PresenceLimits.maxRecognizedTextChars {
            text = String(
                text.prefix(PresenceLimits.maxRecognizedTextChars)
            )
            truncated = true
        }
        return RecognizedText(
            text: text, lineCount: lines.count,
            truncated: truncated
        )
    }

    func ocrResult(_ args: VisionOCRArgs) async throws -> JSONValue {
        let recognized = try await recognizeText(path: args.path)
        var result: [String: JSONValue] = [
            "path": .string(args.path),
            "readAt": .string(DeviceISO8601.format(Date())),
            "text": .string(recognized.text),
            "lines": .number(Double(recognized.lineCount)),
        ]
        if recognized.truncated {
            result["truncated"] = .bool(true)
        }
        return .object(result)
    }

    func scanCodeResult(
        _ args: VisionScanCodeArgs
    ) async throws -> JSONValue {
        let (image, orientation) = try loadImage(path: args.path)
        let request = DetectBarcodesRequest()
        let observations: [BarcodeObservation]
        do {
            observations = try await request.perform(
                on: image, orientation: orientation
            )
        } catch {
            throw DeviceToolError.failed(
                "扫码没能完成：\(error.localizedDescription)"
            )
        }
        var codes: [[String: JSONValue]] = []
        for barcode in observations {
            // payloadString 的可选性随载荷内容变（非
            // 文本载荷读不出串）：空串一律跳过、不编
            let payload = barcode.payloadString ?? ""
            guard !payload.isEmpty else { continue }
            codes.append([
                "symbology": .string(
                    Self.symbologyText(barcode.symbology)
                ),
                "payload": .string(payload),
            ])
        }
        return .object([
            "path": .string(args.path),
            "readAt": .string(DeviceISO8601.format(Date())),
            "count": .number(Double(codes.count)),
            "codes": .array(codes.map { .object($0) }),
        ])
    }

    /// 码制人话：常见码制逐个给名，其余归「其他码
    /// 制」——BarcodeSymbology 是可扩展结构体、没有
    /// 可依赖的出串口径，宁可归类不编名
    static func symbologyText(
        _ symbology: BarcodeSymbology
    ) -> String {
        switch symbology {
        case .qr: return "二维码"
        case .ean13: return "EAN-13 条形码"
        case .ean8: return "EAN-8 条形码"
        case .code128: return "Code 128 条形码"
        case .code39: return "Code 39 条形码"
        case .code93: return "Code 93 条形码"
        case .pdf417: return "PDF417 码"
        case .aztec: return "Aztec 码"
        case .dataMatrix: return "DataMatrix 码"
        case .upce: return "UPC-E 条形码"
        case .itf14: return "ITF-14 条形码"
        default: return "其他码制"
        }
    }
}

// MARK: - 翻译执行器（系统翻译，设备扩容批三）

/// 系统翻译走 iOS 26 的无头会话构造式
/// （TranslationSession(installedSource:target:)，
/// 苹果文档明示「for contexts where there's no
/// UI」）：不需要任何界面在场，前提是语言对已下载
/// 到本机——先用 LanguageAvailability 查状态：不支
/// 持/未下载都如实报错（未下载时不许假装能翻、也
/// 不在工具调用里替用户弹下载面，下载由用户在详
/// 情页/系统翻译设置里亲手完成），已下载才开会话。
final class TranslateEngine: @unchecked Sendable {

    /// 语言对状态（执行判门与详情页呈现共用一处查法）
    func status(
        from source: Locale.Language, to target: Locale.Language
    ) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: source, to: target)
    }

    static func statusText(
        _ status: LanguageAvailability.Status
    ) -> String {
        switch status {
        case .installed: return "已下载，可直接翻"
        case .supported: return "还没下载语言包"
        case .unsupported: return "系统不支持这个组合"
        @unknown default: return "未知状态"
        }
    }

    /// 缺省目标语言（契约明示）：源是中文→英文，
    /// 其余→简体中文；回执回明实际目标，不让调用方猜
    static func defaultTargetCode(forSource source: String) -> String {
        source.lowercased().hasPrefix("zh") ? "en" : "zh-Hans"
    }

    func translate(
        _ args: TranslateTextArgs
    ) async throws -> JSONValue {
        let source = Locale.Language(identifier: args.source)
        let targetCode = args.target
            ?? Self.defaultTargetCode(forSource: args.source)
        let target = Locale.Language(identifier: targetCode)
        switch await status(from: source, to: target) {
        case .unsupported:
            throw DeviceToolError.failed(
                "系统不支持从 \(args.source) 翻译到 \(targetCode)"
            )
        case .supported:
            throw DeviceToolError.failed(
                "从 \(args.source) 到 \(targetCode) 的语言包还没下载到这台手机上，下载好之后才能翻"
            )
        case .installed:
            break
        @unknown default:
            break
        }
        let session = TranslationSession(
            installedSource: source, target: target
        )
        do {
            let response = try await session.translate(args.text)
            return .object([
                "text": .string(response.targetText),
                "sourceLanguage": .string(
                    response.sourceLanguage.minimalIdentifier
                ),
                "targetLanguage": .string(
                    response.targetLanguage.minimalIdentifier
                ),
                "readAt": .string(DeviceISO8601.format(Date())),
                "humanSummary": .string(args.humanSummary),
            ])
        } catch {
            throw DeviceToolError.failed(
                "翻译没能完成：\(error.localizedDescription)"
            )
        }
    }
}

// MARK: - 端上模型执行器（Foundation Models，设备扩容批三）

/// 端上大模型（系统自带、离线）：可用性门先行——
/// SystemLanguageModel.availability 不是 .available
/// 时整件不可用：注册载荷由 DeviceStore 组装时摘
/// 掉 ondevice_model_run（机型不支持就不列，表面
/// 图 A19 原口径），执行时引擎再复查一次（状态可
/// 能在注册后变化，如模型刚下载完）。每次调用开新
/// 会话、单次问答、不带上文（契约明示）；上下文约
/// 4096 token，超限由框架的 exceededContextWindow-
/// Size 兜底如实报错。
final class OnDeviceModelEngine: @unchecked Sendable {

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    /// 不可用原因人话（详情页与执行错误共用一处口径）
    static func availabilityLine() -> String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "可用"
        case .unavailable(.deviceNotEligible):
            return "这台手机不支持 Apple 智能，端上模型用不了"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple 智能还没打开，在系统设置里打开后可用"
        case .unavailable(.modelNotReady):
            return "端上模型还在准备中（下载或整理未完成），稍后再试"
        case .unavailable:
            return "端上模型现在不可用"
        @unknown default:
            return "端上模型现在不可用"
        }
    }

    func run(_ args: OnDeviceModelArgs) async throws -> JSONValue {
        guard Self.isAvailable else {
            throw DeviceToolError.failed(Self.availabilityLine())
        }
        let session: LanguageModelSession
        if let instructions = args.instructions {
            session = LanguageModelSession(instructions: instructions)
        } else {
            session = LanguageModelSession()
        }
        do {
            let response = try await session.respond(to: args.prompt)
            return .object([
                "text": .string(response.content),
                "model": .string("on-device"),
                "readAt": .string(DeviceISO8601.format(Date())),
            ])
        } catch let error as LanguageModelSession.GenerationError {
            throw DeviceToolError.failed(
                Self.generationErrorText(error)
            )
        } catch {
            throw DeviceToolError.failed(
                "端上模型没能回答：\(error.localizedDescription)"
            )
        }
    }

    /// 框架错误的人话映射：超上下文/被安全规则拦/语
    /// 言不支持三类逐个说清，其余归框架原文
    static func generationErrorText(
        _ error: LanguageModelSession.GenerationError
    ) -> String {
        switch error {
        case .exceededContextWindowSize:
            return "这段文字太长，端上模型一次装不下，缩短后再试"
        case .guardrailViolation:
            return "这段内容被端上模型的安全规则拦下了"
        case .unsupportedLanguageOrLocale:
            return "端上模型不支持这个语言"
        default:
            return "端上模型没能回答：\(error.localizedDescription)"
        }
    }
}

// MARK: - 本人确认执行器（LocalAuthentication，设备扩容批三）

/// 本人确认（面容/指纹）：只能验「操作时在场的
/// 是不是机主本人」——系统只回过没过，生物数据永
/// 远不出系统、App 碰不到。定位是高敏操作的前置
/// 门：结果如实回 confirmed 真假，验证被拒/被取消
/// 不是工具故障、是这次确认的答案（以结果回、不
/// 以错误回）；只有「根本问不出口」（没录面容/
/// 指纹、没设锁屏密码等）才走错误。每次调用必真
/// 问一次——不走幂等账本（见 DeviceToolSpec 注记）。
final class BiometricEngine: @unchecked Sendable {

    /// 识别方式（canEvaluate 后才读得到 biometryType）
    static func biometryKind() -> String {
        let context = LAContext()
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: nil
        ) else { return "none" }
        switch context.biometryType {
        case .faceID: return "faceID"
        case .touchID: return "touchID"
        case .opticID: return "opticID"
        default: return "none"
        }
    }

    static func biometryKindText() -> String {
        switch biometryKind() {
        case "faceID": return "面容 ID"
        case "touchID": return "指纹（Touch ID）"
        case "opticID": return "虹膜（Optic ID）"
        default: return "未设置或不可用"
        }
    }

    func confirm(
        _ args: BiometricAuthArgs
    ) async throws -> JSONValue {
        let context = LAContext()
        var evaluateError: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &evaluateError
        ) else {
            throw DeviceToolError.failed(
                Self.unavailableText(evaluateError)
            )
        }
        let kind = Self.biometryKind()
        let outcome: String
        do {
            let passed = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: args.reason
            )
            outcome = passed ? "confirmed" : "rejected"
        } catch {
            // evaluatePolicy 抛的是 LAError：经 NSError
            // 的 domain/code 对照（不依赖错误类型的桥
            // 接形态）——取消与验不过是「这次确认的答
            // 案」、以结果回；其余才是工具故障
            let nsError = error as NSError
            let code = nsError.domain == LAErrorDomain
                ? LAError.Code(rawValue: nsError.code)
                : nil
            switch code {
            case .userCancel, .systemCancel, .appCancel:
                outcome = "cancelled"
            case .authenticationFailed:
                outcome = "rejected"
            default:
                throw DeviceToolError.failed(
                    "本人确认没能完成：\(error.localizedDescription)"
                )
            }
        }
        return .object([
            "confirmed": .bool(outcome == "confirmed"),
            "outcome": .string(outcome),
            "biometry": .string(kind),
            "verifiedAt": .string(DeviceISO8601.format(Date())),
            "humanSummary": .string(
                args.humanSummary
                    + (outcome == "confirmed"
                        ? "——已确认是本人" : "——没有确认通过")
            ),
        ])
    }

    /// 问不出口的原因人话：没录入/不可用/没设密码逐
    /// 个说清下一步，其余归系统原文
    static func unavailableText(_ error: NSError?) -> String {
        guard let error else {
            return "这台手机现在用不了生物识别确认"
        }
        let code = error.domain == LAErrorDomain
            ? LAError.Code(rawValue: error.code)
            : nil
        switch code {
        case .biometryNotEnrolled:
            return "这台手机还没录入面容或指纹，先在系统设置里录好才能用本人确认"
        case .biometryNotAvailable:
            return "这台手机现在用不了生物识别"
        case .passcodeNotSet:
            return "这台手机还没设锁屏密码，生物识别用不了"
        default:
            return "本人确认现在用不了：\(error.localizedDescription)"
        }
    }
}
