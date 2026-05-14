//
//  WorkgroupChildSpawning.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/26.
//

import AppKit

extension iTermWorkgroupInstance {
    // Add a split-pane child of `parent` from the workgroup config.
    //
    // Order matters: install in the window via splitVertically before
    // launching, so the SessionView's scrollview/terminal content is
    // wired up first (otherwise the new pane shows up transparent).
    // The spawner handles the AppKit/factory side; we register the
    // resulting session in the workgroup tree and recurse.
    func spawnSplit(config: iTermWorkgroupSessionConfig, parent: PTYSession) {
        guard case .split(let settings) = config.kind else { return }
        // .diff sessions resolve gitBase at fire time, not at spawn
        // time, so a gitBase change while the deferred launch is
        // pending propagates without rebuilding the closure. Pass
        // the unsubstituted config through to the spawner for .diff.
        let resolved = config.mode == .diff
            ? config
            : config.substitutingGitBase(currentGitBase)
        guard let newSession = spawner.spawnSplit(parent: parent,
                                                  config: resolved,
                                                  settings: settings,
                                                  workgroupInstanceID: instanceUniqueIdentifier) else {
            return
        }
        registerNonPeerOrPeerGroupHost(session: newSession,
                                       config: config,
                                       parent: parent)
        spawnNonPeerChildren(of: newSession,
                             parentConfigID: config.uniqueIdentifier)
    }

    // Add a new-tab child from the workgroup config.
    func spawnTab(config: iTermWorkgroupSessionConfig, parent: PTYSession) {
        // Same .diff rationale as spawnSplit above.
        let resolved = config.mode == .diff
            ? config
            : config.substitutingGitBase(currentGitBase)
        guard let newSession = spawner.spawnTab(parent: parent,
                                                config: resolved,
                                                workgroupInstanceID: instanceUniqueIdentifier) else {
            return
        }
        registerNonPeerOrPeerGroupHost(session: newSession,
                                       config: config,
                                       parent: parent)
        spawnNonPeerChildren(of: newSession,
                             parentConfigID: config.uniqueIdentifier)
    }

    // If the spawned non-peer config has peer children of its own
    // (e.g. a split that hosts its own peer group), build a peer
    // port for it and register the peers. Otherwise treat the
    // session as a leaf non-peer.
    private func registerNonPeerOrPeerGroupHost(session: PTYSession,
                                                config: iTermWorkgroupSessionConfig,
                                                parent: PTYSession) {
        let peerChildren = workgroup.sessions.filter { s in
            guard s.parentID == config.uniqueIdentifier else { return false }
            if case .peer = s.kind { return true }
            return false
        }
        if peerChildren.isEmpty {
            registerNonPeer(session: session, config: config)
            return
        }
        // Nested peer group: this non-peer session hosts peers. Build
        // a separate peer port for it; its toolbar comes from the
        // port (not the non-peer items dict).
        let peerConfigs = [config] + peerChildren
        var peers: [String: iTermPromise<PTYSession>] = [:]
        peers[config.uniqueIdentifier] = iTermPromise<PTYSession>(value: session)
        for peer in peerChildren {
            // .diff peers resolve gitBase at fire time; see the
            // matching spawnSplit/spawnTab/enter branches.
            let configToSpawn = peer.mode == .diff
                ? peer
                : peer.substitutingGitBase(currentGitBase)
            peers[peer.uniqueIdentifier] =
                spawner.spawnPeer(parent: parent,
                                  config: configToSpawn,
                                  workgroupInstanceID: instanceUniqueIdentifier)
        }
        let port = iTermWorkgroupPeerPort(
            peers: peers,
            peerConfigs: peerConfigs,
            activeSessionIdentifier: config.uniqueIdentifier,
            leaderIdentifier: config.uniqueIdentifier,
            leaderScope: session.genericScope,
            gitPoller: gitPoller)
        session.peerPort = port
        let childPromises = peerChildren.compactMap {
            peers[$0.uniqueIdentifier]
        }
        registerNestedPeerPort(port,
                               hostSession: session,
                               hostConfig: config,
                               peerChildrenPromises: childPromises)
        for (_, promise) in peers {
            promise.then { [weak self] s in
                guard let self else { return }
                s.workgroupInstance = self
            }
        }
    }
}
