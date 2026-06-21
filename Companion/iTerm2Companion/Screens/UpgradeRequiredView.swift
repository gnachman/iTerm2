//
//  UpgradeRequiredView.swift
//  iTerm2 Companion
//
//  Full-screen blocking panel shown when the companion apps are
//  version-incompatible (the post-connect version handshake failed). It names
//  which app to upgrade and offers a Retry that re-runs the handshake after the
//  user updates. There is no way past it until the apps are in sync.
//

import SwiftUI

struct UpgradeRequiredView: View {
    @Environment(AppModel.self) private var model
    let side: AppModel.UpgradeSide

    private var title: String {
        switch side {
        case .phone: "Update This App"
        case .mac: "Update iTerm2 on Your Mac"
        }
    }

    private var detail: String {
        switch side {
        case .phone:
            "This version of iTerm2 Buddy is too old to connect to the iTerm2 on your "
                + "Mac. Update this app from the App Store to continue."
        case .mac:
            "The iTerm2 on your Mac is too old to connect to this version of iTerm2 "
                + "Buddy. Update iTerm2 on your Mac to continue."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.tint)
                .padding(.bottom, 24)

            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                model.retryAfterUpgrade()
            } label: {
                Text("Retry")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }
}
