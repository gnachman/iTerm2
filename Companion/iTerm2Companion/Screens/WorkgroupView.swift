//
//  WorkgroupView.swift
//  iTerm2 Companion
//
//  The member list of a workgroup, reached by tapping a workgroup @-mention.
//  Each member shows its role, session title, and machine-readable status
//  (OSC 21337 / cc-status) when the session reports one; launched members
//  drill down into the read-only session view.
//

import SwiftUI
import CompanionProtocol

struct WorkgroupView: View {
    @Environment(AppModel.self) private var model
    let workgroupID: String
    let title: String

    @State private var info: CompanionWorkgroupInfo?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let info {
                memberList(info)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Can’t Show Workgroup", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") {
                        Task { await load() }
                    }
                }
            } else {
                ProgressView("Loading workgroup…")
            }
        }
        .navigationTitle(info?.name ?? title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: workgroupID) {
            await load()
        }
    }

    private func memberList(_ info: CompanionWorkgroupInfo) -> some View {
        List {
            Section {
                ForEach(Array(info.members.enumerated()), id: \.offset) { _, member in
                    memberRow(member)
                }
            } footer: {
                if info.members.isEmpty {
                    Text("This workgroup has no members.")
                }
            }
        }
        .refreshable {
            await load()
        }
    }

    @ViewBuilder
    private func memberRow(_ member: CompanionWorkgroupMember) -> some View {
        if let guid = member.sessionGuid {
            NavigationLink(value: AppModel.Destination.session(guid: guid, title: member.roleName, originatingChatID: nil)) {
                memberLabel(member)
            }
        } else {
            memberLabel(member)
        }
    }

    private func memberLabel(_ member: CompanionWorkgroupMember) -> some View {
        HStack(alignment: .top, spacing: 10) {
            stateIcon(member)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.roleName)
                    .font(.body.weight(.medium))
                if let sessionName = member.sessionName, sessionName != member.roleName {
                    Text(sessionName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let status = statusLine(member) {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .opacity(member.sessionGuid == nil ? 0.6 : 1)
    }

    /// The status line under a member: its reported OSC 21337 status (with
    /// detail when present), or a placeholder for unlaunched members.
    private func statusLine(_ member: CompanionWorkgroupMember) -> String? {
        guard member.sessionGuid != nil else {
            return "Hasn’t started yet"
        }
        guard let status = member.statusText else {
            return member.detailText
        }
        guard let detail = member.detailText else {
            return status
        }
        return "\(status): \(detail)"
    }

    @ViewBuilder
    private func stateIcon(_ member: CompanionWorkgroupMember) -> some View {
        if member.sessionGuid == nil {
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
        } else {
            switch member.state {
            case .working:
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.green)
            case .waiting:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            case .idle:
                Image(systemName: "pause.circle")
                    .foregroundStyle(.secondary)
            case .unknown:
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        do {
            let info = try await model.workgroupInfo(id: workgroupID)
            companionLog("Workgroup \(workgroupID): \(info.members.count) member(s)")
            self.info = info
            loadError = nil
        } catch {
            companionLog("Workgroup info failed: \(String(describing: error))")
            loadError = model.userMessage(for: error)
        }
    }
}
