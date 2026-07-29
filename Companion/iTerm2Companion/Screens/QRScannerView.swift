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
import os

struct QRScannerView: UIViewControllerRepresentable {
    /// Called on the main queue with each decoded QR payload.
    let onCode: (String) -> Void
    /// Called if the camera cannot be started (no permission or no device).
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
        sessionAsync { [weak self] session in
            guard let self else {
                return
            }
            guard !sessionInitialized else {
                return
            }
            guard let device = AVCaptureDevice.default(for: .video) else {
                DispatchQueue.main.async { [onCameraError] in
                    onCameraError?("This device has no usable camera.")
                }
                return
            }
            let input: AVCaptureDeviceInput
            do {
                input = try AVCaptureDeviceInput(device: device)
            } catch {
                DispatchQueue.main.async { [onCameraError] in
                    onCameraError?("Couldn’t open the camera: \(error.localizedDescription)")
                }
                return
            }
            guard session.canAddInput(input) else {
                DispatchQueue.main.async { [onCameraError] in
                    onCameraError?("The camera cannot be used currently.")
                }
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                DispatchQueue.main.async { [onCameraError] in
                    onCameraError?("Could not start the camera.")
                }
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            sessionInitialized = true

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                preview.frame = view.bounds
                view.layer.addSublayer(preview)
                previewLayer = preview
            }
        }
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
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func startRunning() {
        wantsRunning.withLock { $0 = true }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async {
                    self.onCameraError?("Camera access is off. Enable it in Settings to scan the QR code.")
                }
                return
            }
            sessionAsync { session in
                if !session.isRunning, self.wantsRunning.withLock({ $0 }) {
                    session.startRunning()
                }
            }
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
        onCode?(value)
    }
}
