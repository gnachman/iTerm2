//
//  ScanningView.swift
//  iTerm2 Companion
//
//  Shows the live camera with an overlay instruction and validates scanned QR
//  payloads. A valid pairing code advances to the pairing screen; an invalid or
//  too-new code is reported inline without leaving the scanner.
//

import SwiftUI
import CompanionProtocol

struct ScanningView: View {
    @Environment(AppModel.self) private var model

    @State private var errorMessage: String?
    // Guards against the metadata delegate firing repeatedly for the same code.
    @State private var handled = false
#if targetEnvironment(simulator)
    @State private var manualCode = ""
#endif

    var body: some View {
        ZStack {
            QRScannerView(onCode: { handle($0) }, onCameraError: { errorMessage = $0 })
                .ignoresSafeArea()

            ScannerOverlay()

            VStack {
                HStack {
                    Button {
                        model.cancelToLaunch()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                }
                .padding()

                Spacer()

                Text("Select iTerm2 > Companion Device Settings on your Mac")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)

#if targetEnvironment(simulator)
                // The simulator has no camera; allow pasting the pairing URL
                // so the full flow can be exercised end to end in development.
                HStack(spacing: 8) {
                    TextField("iterm2://pair?…", text: $manualCode)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Pair") {
                        handle(manualCode, quietOnMalformed: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manualCode.isEmpty)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
#endif

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                }
            }
        }
    }

    private func handle(_ string: String, quietOnMalformed: Bool = true) {
        guard !handled else { return }
        do {
            let code = try PairingCode.parse(string)
            if model.isUsedPairingCode(code) {
                errorMessage = "That code was already used. Choose iTerm2 > Companion Device Settings on your Mac to get a fresh one."
                return
            }
            handled = true
            model.pair(with: code)
        } catch let error as PairingCode.ParseError {
            // Non-pairing QR codes are common while aiming the camera; stay
            // silent for those. Manually entered codes always report.
            switch error {
            case .malformedURL where quietOnMalformed:
                break
            default:
                errorMessage = error.userMessage
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ScannerOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height) * 0.65
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                .frame(width: side, height: side)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .allowsHitTesting(false)
    }
}
