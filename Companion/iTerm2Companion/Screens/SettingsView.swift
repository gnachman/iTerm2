//
//  SettingsView.swift
//  iTerm2 Companion
//
//  Reached from the gear button on the chat list. Hosts the disconnect action
//  and the diagnostic-log controls (toggle + email).
//

import SwiftUI
import MessageUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingDisconnect = false
    @State private var loggingEnabled = CompanionFileLog.shared.isEnabled
    @State private var confirmingDisableLogs = false
    @State private var showingMail = false
    @State private var mailUnavailable = false

    var body: some View {
        @Bindable var manager = model.whisperManager
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

            Section {
                // A custom binding so a turn-OFF does not flip the switch until
                // the user confirms (disabling deletes the files); turning ON
                // applies immediately.
                Toggle("Save Diagnostic Logs", isOn: Binding(
                    get: { loggingEnabled },
                    set: { on in
                        if on {
                            loggingEnabled = true
                            CompanionFileLog.shared.isEnabled = true
                        } else {
                            confirmingDisableLogs = true
                        }
                    }))
                    .alert("Turn off logging?", isPresented: $confirmingDisableLogs) {
                        Button("Turn Off and Delete Logs", role: .destructive) {
                            loggingEnabled = false
                            CompanionFileLog.shared.isEnabled = false
                        }
                        Button("Cancel", role: .cancel) {} // switch never moved
                    } message: {
                        Text("This deletes the saved log files on this device.")
                    }
                Button("Email Logs") {
                    guard MFMailComposeViewController.canSendMail() else {
                        mailUnavailable = true
                        return
                    }
                    CompanionFileLog.shared.flushNow()
                    showingMail = true
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Logs help diagnose problems and stay on this device. Email them if asked, then they are deleted automatically after 14 days.")
            }

            Section {
                Toggle("Dictate messages", isOn: $manager.isEnabled)
                if manager.isEnabled {
                    Picker("Model", selection: Binding(
                        get: { manager.selectedModelName },
                        set: { manager.selectModel($0) })) {
                        ForEach(manager.availableModels, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    voiceStatusRow(manager)
                    if manager.isDownloaded {
                        Button("Remove Model", role: .destructive) {
                            manager.deleteModel()
                        }
                    }
                }
            } header: {
                Text("Voice Input")
            } footer: {
                Text("Dictation runs entirely on this device using Whisper, with no cloud and no cost. The model is downloaded once and stored here. Only models that run well on this device are listed; larger ones are more accurate but more demanding.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Upgrade the conservative offline default to the current,
            // device-tiered remote recommendation (best effort; offline keeps
            // the fallback).
            await model.whisperManager.refreshRecommendation()
        }
        .sheet(isPresented: $showingMail) {
            MailComposeView(to: ["gnachman@gmail.com"],
                            subject: "iTerm2 Buddy logs",
                            body: "Diagnostic logs attached.",
                            attachments: CompanionFileLog.shared.logFileURLs()) {
                showingMail = false
            }
            .ignoresSafeArea()
        }
        .alert("Mail Not Set Up", isPresented: $mailUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Set up the Mail app on this device to email your logs.")
        }
    }

    @ViewBuilder
    private func voiceStatusRow(_ manager: WhisperModelManager) -> some View {
        switch manager.status {
        case .idle:
            Button(manager.isDownloaded ? "Load Model" : "Download Model") {
                Task { await manager.prepare() }
            }
        case .downloading(let fraction):
            ProgressView(value: fraction) {
                Text("Downloading… \(Int(fraction * 100))%")
            }
        case .preparing:
            HStack {
                ProgressView()
                Text("Preparing…")
                    .foregroundStyle(.secondary)
            }
        case .ready:
            Text("Ready")
                .foregroundStyle(.green)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text("Could not load the model.")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await manager.prepare() }
                }
            }
        }
    }
}
