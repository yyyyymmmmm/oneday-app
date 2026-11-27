import AVFoundation
import SwiftUI
import UIKit
import Vision
import VisionKit

/// 相机授权门（授权铁律）：先同步读当前授权状态——已授权直达取景、
/// 已拒绝只走降级文案，只有未决定（.notDetermined）才发那一次请求。
enum CameraPermissionGate {
    /// 同步读当前授权状态（不触发任何请求）
    static func currentStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// 唯一一次授权请求（调用方须先确认状态是 .notDetermined 才许调）
    static func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

/// VisionKit 原生二维码扫描控制器（iOS 16+ / 26 `DataScannerViewController`）：
/// 取代手搓 `AVCaptureSession` + `AVCaptureMetadataOutput` 管线，
/// 自动具备系统级对焦、双指缩放、暗光优化与二维码框选高亮；命中一次即停扫防重复回调。
@MainActor
final class QRScannerViewController: UIViewController, DataScannerViewControllerDelegate {
    var onCode: ((String) -> Void)?
    var onUnavailable: (() -> Void)?

    private var scanner: DataScannerViewController?
    private var delivered = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard DataScannerViewController.isSupported,
              DataScannerViewController.isAvailable else {
            DispatchQueue.main.async { [weak self] in
                self?.onUnavailable?()
            }
            return
        }

        let dataScanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        dataScanner.delegate = self

        addChild(dataScanner)
        dataScanner.view.frame = view.bounds
        dataScanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(dataScanner.view)
        dataScanner.didMove(toParent: self)
        scanner = dataScanner
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        delivered = false
        guard let scanner else { return }
        do {
            try scanner.startScanning()
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onUnavailable?()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanner?.stopScanning()
    }

    func dataScanner(
        _ dataScanner: DataScannerViewController,
        didAdd addedItems: [RecognizedItem],
        allItems: [RecognizedItem]
    ) {
        deliverFirstQR(in: addedItems)
    }

    func dataScanner(
        _ dataScanner: DataScannerViewController,
        didUpdate updatedItems: [RecognizedItem],
        allItems: [RecognizedItem]
    ) {
        deliverFirstQR(in: updatedItems)
    }

    private func deliverFirstQR(in items: [RecognizedItem]) {
        guard !delivered else { return }
        for item in items {
            if case .barcode(let barcode) = item,
               let payload = barcode.payloadStringValue,
               !payload.isEmpty {
                delivered = true
                scanner?.stopScanning()
                onCode?(payload)
                return
            }
        }
    }
}

/// 扫码面（SwiftUI 壳）：连接页以 sheet 呈现，扫到码经 onCode 交回连接页走认领流程
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onUnavailable: () -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCode = onCode
        controller.onUnavailable = onUnavailable
        return controller
    }

    func updateUIViewController(
        _ controller: QRScannerViewController, context: Context
    ) {
        controller.onCode = onCode
        controller.onUnavailable = onUnavailable
    }
}
