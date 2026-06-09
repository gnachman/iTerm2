//
//  PairingView.swift
//  iTerm2 Companion
//
//  Shown while the Bonjour rendezvous and Noise handshake run. On success the
//  model advances to the home screen; on failure it surfaces an error here with
//  a way back.
//

import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if let error = model.pairingError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.orange)
                Text("Couldn’t pair")
                    .font(.title2.bold())
                Text(error)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                ProgressView()
                    .controlSize(.large)
                Text("Pairing with iTerm2…")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.pairingError != nil {
                Button {
                    model.beginScanning()
                } label: {
                    PrimaryButtonLabel(title: "Try Again")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
    }
}
