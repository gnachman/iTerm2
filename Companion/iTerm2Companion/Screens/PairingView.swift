//
//  PairingView.swift
//  iTerm2 Companion
//
//  Shown while the rendezvous and Noise handshake run. Displays the current
//  step plus an elapsed-time counter so a slow Mac is visibly "still trying"
//  rather than hung, and offers Cancel. On failure it surfaces an error with
//  a way back.
//

import SwiftUI

struct PairingView: View {
    @Environment(AppModel.self) private var model

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
            } else if let sasCode = model.sasCode {
                // SAS confirmation: the user types this code on the Mac. Shown
                // big enough to read across the room.
                Image(systemName: "lock.shield")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tint)
                Text(sasCode)
                    .font(.system(size: 56, weight: .semibold, design: .monospaced))
                    .kerning(6)
                    .accessibilityLabel("Pairing code \(sasCode.map(String.init).joined(separator: " "))")
                Text("Enter this code on your Mac to finish pairing.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                if let relayHost = model.activePairingRelayHostToShow {
                    // Non-default relay: disclose the host (punycode) so a hostile
                    // or look-alike server, scanned or tapped, is visible before
                    // the user confirms. Also a plain "you're on relay X" cue for
                    // self-hosters.
                    VStack(spacing: 4) {
                        Label(relayHost, systemImage: "exclamationmark.shield")
                            .font(.footnote.weight(.medium))
                        Text("Pairing through a custom relay. Continue only if you recognize this server.")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                Text(model.activeIsReconnect ? "Connecting to iTerm2…" : "Pairing with iTerm2…")
                    .font(.headline)
                statusLine
            }

            Spacer()

            if model.pairingError != nil {
                Button {
                    model.retryPairing()
                } label: {
                    PrimaryButtonLabel(title: "Try Again")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)

                Button("Pair a Different Mac") {
                    model.beginScanning()
                }
                .font(.subheadline)
            }

            Button("Cancel") {
                model.cancelPairing()
            }
            .font(.headline)
            .padding(.bottom, 24)
        }
    }

    /// "Waiting on the Mac" feedback: the current step plus seconds elapsed,
    /// updating once per second.
    @ViewBuilder
    private var statusLine: some View {
        if let startedAt = model.pairingStartedAt {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                let elapsed = max(0, Int(context.date.timeIntervalSince(startedAt)))
                Text("\(model.pairingStatus) (\(elapsed)s)…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
