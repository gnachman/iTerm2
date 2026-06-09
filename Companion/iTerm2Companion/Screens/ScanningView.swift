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
    @EnvironmentObject private var model: AppModel

    @State private var errorMessage: String?
    // Guards against the metadata delegate firing repeatedly for the same code.
    @State private var handled = false

    var body: some View {
        ZStack {
            QRScannerView(onCode: handle, onCameraError: { errorMessage = $0 })
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

                Text("Select iTerm2 > Pair Companion Device on your Mac")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)

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

    private func handle(_ string: String) {
        guard !handled else { return }
        do {
            let code = try PairingCode.parse(string)
            handled = true
            model.pair(with: code)
        } catch let error as PairingCode.ParseError {
            // Non-pairing QR codes are common while aiming; stay silent for
            // those and only surface codes that are pairing codes we reject.
            switch error {
            case .malformedURL:
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
