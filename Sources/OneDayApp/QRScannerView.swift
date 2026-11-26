import AVFoundation
import SwiftUI
import UIKit
import VisionKit

/// 相机授权门：先同步读当前授权状态——已授权直达取景、
/// 已拒绝只走降级文案，只有未决定（.notDetermined）才发
/// 请求，避免在已决定状态上重复触发异步授权回调。
enum CameraPermissionGate {
    /// 同步读当前授权状态（不触发任何请求）
    static func currentStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// 唯一一次授权请求（调用方须先确认状态是 .notDetermined）
    static func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

/// 扫码面（SwiftUI 壳）：基于系统原生 VisionKit DataScannerViewController，
/// 自带二维码高亮框、双指缩放与原生取景引导；命中一次即停扫并经 onCode 交回连接页。
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onUnavailable: () -> Void

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCode: (String) -> Void
        private var delivered = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        @MainActor
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !delivered else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let value = barcode.payloadStringValue,
                   !value.isEmpty {
                    delivered = true
                    dataScanner.stopScanning()
                    onCode(value)
                    return
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard DataScannerViewController.isSupported,
              DataScannerViewController.isAvailable else {
            let fallback = UIViewController()
            fallback.view.backgroundColor = .black
            DispatchQueue.main.async {
                onUnavailable()
            }
            return fallback
        }

        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        do {
            try scanner.startScanning()
        } catch {
            DispatchQueue.main.async {
                onUnavailable()
            }
        }
        return scanner
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        if let scanner = uiViewController as? DataScannerViewController, scanner.isScanning {
            scanner.stopScanning()
        }
    }
}
