//
//  QRScannerView.swift
//  iTerm2 Companion
//
//  A SwiftUI wrapper around an AVCaptureSession configured to detect QR codes.
//  It reports each decoded string once via `onCode`; the caller decides whether
//  the string is a valid pairing code and when to stop.
//

import SwiftUI
import AVFoundation
import CompanionProtocol
import os

struct QRScannerView: UIViewControllerRepresentable {
    /// Called on the main queue with each decoded QR payload.
    let onCode: (String) -> Void
    /// Called on the main queue, while the scanner is on screen, if the camera
    /// cannot be started (no permission or no device) or stops with an
    /// unrecoverable runtime error. Not called once the scanner is dismissed.
    let onCameraError: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCode = onCode
        controller.onCameraError = onCameraError
        return controller
    }

    func updateUIViewController(_ controller: QRScannerViewController, context: Context) {}
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onCameraError: ((String) -> Void)?
    private let wantsRunning = OSAllocatedUnfairLock(initialState: false)
    private var sessionInitialized = false

    private let _session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "com.googlecode.iterm2.companion.capture")

    private func sessionAsync(_ closure: @escaping (AVCaptureSession) -> ()) {
        sessionQueue.async { [_session] in
            closure(_session)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: _session)
        CompanionLog.log("QRScanner: viewDidLoad; authorization=\(Self.describe(AVCaptureDevice.authorizationStatus(for: .video)))")
    }

    // Builds the session's input, metadata output, and preview layer. Must run on
    // sessionQueue and only after camera access is authorized: iOS 26 silently
    // delivers no frames from an input added while the app is unauthorized, which
    // manifests as a black preview with no error. Returns false (and reports an
    // error) if the camera can't be configured. Idempotent via sessionInitialized.
    private func configureSessionIfNeeded(_ session: AVCaptureSession) -> Bool {
        guard !sessionInitialized else {
            return true
        }
        guard let device = AVCaptureDevice.default(for: .video) else {
            reportError("This device has no usable camera.")
            return false
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            reportError("Couldn’t open the camera: \(error.localizedDescription)")
            return false
        }
        guard session.canAddInput(input) else {
            reportError("The camera cannot be used currently.")
            return false
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            reportError("Could not start the camera.")
            return false
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        sessionInitialized = true
        CompanionLog.log("QRScanner: session configured (camera input + qr metadata output)")

        // The preview layer is a CALayer; create and mutate it on the main
        // thread. Only the session I/O above belongs on sessionQueue.
        DispatchQueue.main.async { [weak self, _session] in
            guard let self else {
                return
            }
            let preview = AVCaptureVideoPreviewLayer(session: _session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            previewLayer = preview
            CompanionLog.log("QRScanner: preview layer attached; bounds=\(view.bounds.debugDescription)")
        }
        return true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startRunning()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopRunning()
    }

    private func stopRunning() {
        wantsRunning.withLock { $0 = false }
        sessionAsync { session in
            if session.isRunning, !self.wantsRunning.withLock({ $0 }) {
                session.stopRunning()
                CompanionLog.log("QRScanner: session stopped")
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func startRunning() {
        wantsRunning.withLock { $0 = true }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        CompanionLog.log("QRScanner: startRunning; authorization=\(Self.describe(status))")
        switch status {
        case .authorized:
            // Permission was granted on a previous launch; configure and start now.
            configureAndStart()
        case .notDetermined:
            // First run: we must not configure the session until access is granted.
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else {
                    return
                }
                CompanionLog.log("QRScanner: requestAccess returned granted=\(granted)")
                guard granted else {
                    reportError("Camera access is off. Enable it in Settings to scan the QR code.")
                    return
                }
                configureAndStart()
            }
        case .denied, .restricted:
            reportError("Camera access is off. Enable it in Settings to scan the QR code.")
        @unknown default:
            reportError("Camera access is off. Enable it in Settings to scan the QR code.")
        }
    }

    // Configures the session (once authorized) and starts it, unless the view has
    // gone away in the meantime. Runs the work on sessionQueue.
    private func configureAndStart() {
        sessionAsync { [weak self] session in
            guard let self else {
                return
            }
            guard wantsRunning.withLock({ $0 }) else {
                CompanionLog.log("QRScanner: configureAndStart aborted; view no longer wants to run")
                return
            }
            guard configureSessionIfNeeded(session) else {
                return
            }
            if !session.isRunning {
                session.startRunning()
                CompanionLog.log("QRScanner: session started; isRunning=\(session.isRunning)")
            }
        }
    }

    private func reportError(_ message: String) {
        CompanionLog.log("QRScanner: error: \(message)")
        // Only surface errors while the scanner is on screen. A session can emit
        // a runtime error during teardown (e.g. backgrounding right after a
        // successful pair), and we must not flash a banner on the screen the user
        // already moved to.
        guard wantsRunning.withLock({ $0 }) else {
            CompanionLog.log("QRScanner: suppressing error; scanner no longer active")
            return
        }
        DispatchQueue.main.async { [weak self, onCameraError] in
            // Re-check on the main thread: the scanner may have been dismissed
            // between the guard above and this block running.
            guard let self, wantsRunning.withLock({ $0 }) else {
                return
            }
            onCameraError?(message)
        }
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
        CompanionLog.log("QRScanner: runtime error: \(error?.localizedDescription ?? "unknown") (code \(error?.code.rawValue ?? 0))")

        // mediaServicesWereReset is the common recoverable case (mediaserverd
        // restarted, or another app briefly grabbed the camera). The session
        // stays configured, so per Apple we just start it running again rather
        // than tearing down and rebuilding. Only do so while still on screen.
        if error?.code == .mediaServicesWereReset, wantsRunning.withLock({ $0 }) {
            CompanionLog.log("QRScanner: attempting session restart after mediaServicesWereReset")
            sessionAsync { [weak self] session in
                guard let self, wantsRunning.withLock({ $0 }), !session.isRunning else {
                    return
                }
                session.startRunning()
                CompanionLog.log("QRScanner: session restarted; isRunning=\(session.isRunning)")
            }
            return
        }

        reportError("The camera stopped unexpectedly. Go back and tap Scan again.")
    }

    private static func describe(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else {
            return
        }
        CompanionLog.log("QRScanner: decoded QR payload (\(value.count) chars)")
        onCode?(value)
    }
}
