//
//  SessionBrowserView.swift
//  iTerm2 Companion
//
//  The Sessions tab's root: the Mac's sessions organized the way the user
//  sees them, window > tab > pane, with one more level under panes that host
//  a peer group (each peer labeled with its role, e.g. “Code Review”).
//  Session rows drill into the read-only session view.
//

import SwiftUI
import CompanionProtocol

struct SessionBrowserView: View {
    var body: some View {
        SessionTreeBrowser { session, title, level in
            NavigationLink(value: AppModel.Destination.session(guid: session.guid,
                                                               title: title,
                                                               originatingChatID: nil)) {
                SessionTreeRow(icon: "terminal",
                               title: title,
                               subtitle: session.subtitle.isEmpty ? nil : session.subtitle,
                               level: level)
            }
        }
        .navigationTitle("Sessions")
    }
}
