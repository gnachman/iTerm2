//
//  SettingsView.swift
//  iTerm2 Companion
//
//  Reached from the gear button on the chat list. Currently hosts the
//  disconnect action; destined to grow.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingDisconnect = false

    var body: some View {
        Form {
            Section {
                Button("Disconnect from This Mac", role: .destructive) {
                    confirmingDisconnect = true
                }
                // Attached to the button (not the Form) so the dialog anchors
                // to it; detached, it floats in the middle of nowhere.
                .confirmationDialog("Disconnect from your Mac?",
                                    isPresented: $confirmingDisconnect,
                                    titleVisibility: .visible) {
                    Button("Disconnect", role: .destructive) {
                        model.disconnectFromMac()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This deletes the pairing keys. You’ll need to scan a new QR code to pair again.")
                }
            } footer: {
                Text("Disconnecting deletes the pairing keys on this device and on your Mac. Pair again by scanning a new QR code.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
