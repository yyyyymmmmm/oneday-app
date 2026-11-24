import AVFoundation
import SwiftUI
import UIKit

/// 相机授权门（授权铁律，AGENTS.md 2026-11-10）：先
/// 同步读当前授权状态——已授权直达取景、已拒绝只走
/// 降级文案，只有未决定（.notDetermined）才发那一
/// 次请求，绝不在已决定状态上重走异步请求回调。承
/// 接请求的闭包活在本非隔离类型里、只把一个 Bool
/// 交回 continuation，不继承任何 actor 隔离（系统
/// 回调隔离铁律同款）
enum CameraPermissionGate {
    /// 同步读当前授权状态（不触发任何请求）
    static func currentStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// 唯一一次授权请求（调用方须先确认状态是
    /// .notDetermined 才许调）
    static func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

/// 扫码识别引擎（配对一期）：采集会话＋二维码识别。
/// 识别回调由 AVFoundation 投递到自备串行队列、本
/// 类是非隔离 NSObject——回调里只取字符串值、经主
/// 队列交回上层，不碰任何 actor 隔离状态（回调隔
/// 离铁律）；命中一次即停会话，防重复投递
/// @unchecked Sendable 依据＝状态按队列分仓：delivered
/// 与会话启停只在 callbackQueue 上读写；onCode/
/// onUnavailable 只在主队列上写（呈现前由表示层设
/// 入）与读（交付时），两仓不交叉
final class QRScannerEngine: NSObject,
    AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let callbackQueue = DispatchQueue(
        label: "site.didichou.oneday.qr-scanner"
    )
    /// 只在 callbackQueue 上读写（识别回调与启停同队列串行）
    private var delivered = false
    var onCode: ((String) -> Void)?
    var onUnavailable: (() -> Void)?

    /// 组装输入/输出；设备无相机或会话装不下时返回
    /// false，上层走「相机不可用」降级文案
    func configure() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return false
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: callbackQueue)
        output.metadataObjectTypes = [.qr]
        return true
    }

    func start() {
        callbackQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        callbackQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !delivered,
              let object = metadataObjects.first
                as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue,
              !value.isEmpty else {
            return
        }
        delivered = true
        session.stopRunning()
        // 交付走 [weak self] 主队列式（仓内 ChatList-
        // Carrier 同式）：只把字符串值送过队列，闭包
        // 本体不跨队列传（Swift 6 数据竞争检查口径）
        DispatchQueue.main.async { [weak self] in
            self?.onCode?(value)
        }
    }
}

/// 取景控制器：只管预览层与引擎启停，识别逻辑全在
/// QRScannerEngine
final class QRScannerViewController: UIViewController {
    private let engine = QRScannerEngine()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    var onCode: ((String) -> Void)? {
        get { engine.onCode }
        set { engine.onCode = newValue }
    }
    var onUnavailable: (() -> Void)? {
        get { engine.onUnavailable }
        set { engine.onUnavailable = newValue }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard engine.configure() else {
            DispatchQueue.main.async { [weak self] in
                self?.engine.onUnavailable?()
            }
            return
        }
        let preview = AVCaptureVideoPreviewLayer(session: engine.session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        engine.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        engine.stop()
    }
}

/// 扫码面（SwiftUI 壳）：连接页以 sheet 呈现，扫到
/// 码经 onCode 交回连接页走认领流程
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onUnavailable: () -> Void

    func makeUIViewController(
        context: Context
    ) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCode = onCode
        controller.onUnavailable = onUnavailable
        return controller
    }

    func updateUIViewController(
        _ controller: QRScannerViewController, context: Context
    ) {}
}
