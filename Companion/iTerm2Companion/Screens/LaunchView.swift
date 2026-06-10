//
//  LaunchView.swift
//  iTerm2 Companion
//
//  The first screen: explains how to pair and offers a Scan button.
//

import SwiftUI

struct LaunchView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.tint)
                .padding(.bottom, 24)

            Text("Pair with iTerm2")
                .font(.largeTitle.bold())
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 18) {
                InstructionRow(number: 1,
                               text: "On your Mac, choose the menu item iTerm2 > Pair Companion Device. A QR code appears.")
                InstructionRow(number: 2, text: "Tap the Scan button below.")
                InstructionRow(number: 3, text: "Point the camera at the QR code.")
            }
            .padding(.horizontal, 32)

            Spacer()

            // A full-width primary button built from a plain button plus our own
            // background. .borderedProminent with a maxWidth: .infinity label
            // renders a ghost copy of the label at the top of the screen, so we
            // avoid that style for full-width buttons (see PrimaryButtonLabel).
            Button {
                model.beginScanning()
            } label: {
                PrimaryButtonLabel(title: "Scan", systemImage: "camera.viewfinder")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.bottom, 8)

            if let stored = model.storedPairingCode {
                Button("Reconnect to Your Mac") {
                    model.pair(with: stored, isReconnect: true)
                }
                .font(.headline)
                .padding(.bottom, 4)

                Button("Forget Saved Mac") {
                    model.forgetStoredPairing()
                }
                .font(.subheadline)
            }
        }
        .padding(.bottom, 16)
    }
}

private struct InstructionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.tint))
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
