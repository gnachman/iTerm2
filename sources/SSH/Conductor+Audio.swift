//
//  Conductor+Audio.swift
//  iTerm2SharedARC
//
//  Conductor integration for first-class SSH audio (`PULSE_SERVER=unix:<socket>`),
//  wiring `ConductorAudioDemux`, `SSHAudioEngine`, cryptographic `AudioHostGrant`s,
//  in-session microphone consent announcements, and session mute/status controls.
//

import Foundation

final class AudioHostGrantUserDefaultsBacking: AudioHostGrantBacking {
    static let key = "NoSyncAudioHostGrants"

    func loadGrantData() -> Data? {
        return iTermUserDefaults.userDefaults().data(forKey: Self.key)
    }

    func saveGrantData(_ data: Data?) {
        iTermUserDefaults.userDefaults().set(data, forKey: Self.key)
    }
}

extension Conductor {
    static var audioHostGrantStoreForTesting: AudioHostGrantStore?
    static var audioHostGrantVerifierForTesting: ((AudioHostGrant, String) async -> Bool)?
    static var audioBackendFactoryForTesting: ((@escaping (@escaping (Bool) -> Void) -> Void) -> PulseAudioBackend)?

    private static let defaultAudioHostGrantStore = AudioHostGrantStore(
        backing: AudioHostGrantUserDefaultsBacking(),
        onRevokeHost: { host in
            Task { @MainActor in
                for conductor in ConductorRegistry.instance.conductors(forStringIdentifier: host)
                where conductor.audioMicAuthorized == true {
                    conductor.audioMicAuthorized = nil
                    conductor.audioDemux?.closeCaptureConnections()
                    conductor.delegate?.conductorStateDidChange()
                }
            }
        })

    static var audioHostGrantStore: AudioHostGrantStore {
        return audioHostGrantStoreForTesting ?? defaultAudioHostGrantStore
    }

    @objc(adoptAudioRecoveryStateFrom:)
    func adoptAudioRecoveryState(from other: Conductor?) {
        guard let other else {
            return
        }
        audioProxy = other.audioProxy
        other.audioDemux?.closeAll()
        other.audioEngine?.shutdownAll()
    }

    func audioBackendForHandling() -> PulseAudioBackend {
        if let factory = Conductor.audioBackendFactoryForTesting {
            if let existing = audioTestBackend {
                return existing
            }
            let backend = factory { [weak self] completion in
                guard let self else {
                    completion(false)
                    return
                }
                self.authorizeAudioMicrophone(then: completion)
            }
            audioTestBackend = backend
            return backend
        }
        if let existing = audioEngine {
            return existing
        }
        let engine = SSHAudioEngine { [weak self] completion in
            MainActor.assumeIsolated {
                guard let self else {
                    completion(false)
                    return
                }
                self.authorizeAudioMicrophone(then: completion)
            }
        }
        engine.isMuted = audioProxy.muted
        audioEngine = engine
        return engine
    }

    func audioDemuxForHandling() -> ConductorAudioDemux {
        if let existing = audioDemux {
            return existing
        }
        let backend = audioBackendForHandling()
        let demux = ConductorAudioDemux(
            backend: backend,
            send: { [weak self] connid, data in
                self?.pulseSend(connid: connid, data: data)
            },
            close: { [weak self] connid in
                self?.pulseClose(connid: connid)
            },
            onActivityChanged: { [weak self] in
                self?.delegate?.conductorStateDidChange()
            },
            logger: { [weak self] message in
                self?.DLog(message)
            })
        audioDemux = demux
        return demux
    }

    // MARK: - Microphone Authorization (In-Session Announcement + Host Grants)

    func authorizeAudioMicrophone(then completion: @escaping (Bool) -> Void) {
        if let decided = audioMicAuthorized {
            completion(decided)
            return
        }
        let promise = audioAuthPromise ?? makeAudioAuthorizationPromise()
        promise.then { value in
            completion(value.boolValue)
        }
    }

    private func makeAudioAuthorizationPromise() -> iTermPromise<NSNumber> {
        let promise = iTermPromise<NSNumber> { [weak self] seal in
            guard let self else {
                seal.fulfill(NSNumber(value: false))
                return
            }
            guard let delegate = self.delegate else {
                self.audioAuthSeal = seal
                self.resolveAudioAuthorization(false, persist: false)
                return
            }
            if let grant = Conductor.audioHostGrantStore.grant(forHost: self.sshIdentity.stringIdentifier),
               let home = self.homeDirectory {
                self.audioAuthSeal = seal
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    let verified: Bool
                    if let verifier = Conductor.audioHostGrantVerifierForTesting {
                        verified = await verifier(grant, home)
                    } else {
                        verified = await self.audioHostGrantVerifies(grant, home: home)
                    }
                    guard self.audioAuthSeal != nil else {
                        return
                    }
                    if verified {
                        self.resolveAudioAuthorization(true, persist: true)
                        return
                    }
                    guard let delegate = self.delegate else {
                        self.resolveAudioAuthorization(false, persist: false)
                        return
                    }
                    self.audioAuthSeal = nil
                    self.presentAudioAuthorizationPrompt(delegate: delegate, seal: seal)
                }
                return
            }
            self.presentAudioAuthorizationPrompt(delegate: delegate, seal: seal)
        }
        audioAuthPromise = promise
        promise.then { [weak self] _ in
            self?.audioAuthPromise = nil
        }
        return promise
    }

    private func presentAudioAuthorizationPrompt(delegate: ConductorDelegate, seal: iTermPromiseSeal) {
        guard let request = delegate.conductorRequestAudioAuthorization else {
            audioAuthSeal = seal
            resolveAudioAuthorization(false, persist: false)
            return
        }
        request(guid, it2DisplayName) { [weak self] granted, remember, alwaysForHost in
            self?.resolveAudioAuthorization(granted, persist: remember)
            if granted && alwaysForHost {
                self?.mintAudioHostGrant()
            }
        }
        // Assign the seal AFTER presenting so synchronous dismissal of any orphaned prompt
        // sharing the same announcement identifier cannot resolve this fresh prompt early.
        audioAuthSeal = seal
    }

    func audioHostGrantVerifies(_ grant: AudioHostGrant, home: String) async -> Bool {
        guard AudioGrantToken.isHex(grant.id) else {
            DLog("audio host grant for \(grant.host) has a malformed id")
            return false
        }
        let path = AudioGrantToken.remoteRelativePath(id: grant.id)
        do {
            let data = try await download("\(home)/\(path)", chunk: nil, uniqueID: nil)
            let verified = AudioGrantToken.verify(fileContents: String(decoding: data, as: UTF8.self),
                                                  against: grant)
            DLog("audio host grant for \(grant.host) in \(path): \(verified ? "verified" : "does not match")")
            return verified
        } catch {
            DLog("audio host grant for \(grant.host) could not be read from \(path): \(error)")
            return false
        }
    }

    func mintAudioHostGrant() {
        let host = sshIdentity.stringIdentifier
        let token = AudioGrantToken.mint()
        let previous = Conductor.audioHostGrantStore.grant(forHost: host)?.id
        framerExecPythonStatements(statements: AudioGrantToken.remoteWriteStatements(id: token.id,
                                                                                     secret: token.secret,
                                                                                     replacing: previous)) { [weak self] ok, output in
            guard ok else {
                RLog("Could not write the audio microphone grant to the remote host")
                self?.DLog("audio grant write to \(host) failed: \(output)")
                return
            }
            Conductor.audioHostGrantStore.add(AudioHostGrant(host: host,
                                                             id: token.id,
                                                             secretSHA256: AudioGrantToken.sha256Hex(token.secret),
                                                             granted: Date()))
            self?.DLog("audio microphone host grant minted for \(host)")
        }
    }

    func resolveAudioAuthorization(_ granted: Bool, persist: Bool) {
        guard let seal = audioAuthSeal else {
            return
        }
        audioAuthSeal = nil
        delegate?.conductorDismissAudioAuthorizationPrompt?(guid: guid)
        if persist {
            audioMicAuthorized = granted
        }
        seal.fulfill(NSNumber(value: granted))
        delegate?.conductorStateDidChange()
    }

    @objc func resolveAudioAuthorizationFailClosed() {
        resolveAudioAuthorization(false, persist: false)
    }

    // MARK: - Session Menu & Tab Status Indicators

    @objc var audioProxyActive: Bool {
        return framing && pulseSocketPath != nil && pulseListenSucceeded
    }

    @objc var isPlayingRemoteAudio: Bool {
        return audioDemux?.isPlayingAudio == true
    }

    @objc var isCapturingRemoteAudio: Bool {
        return audioDemux?.isCapturingAudio == true
    }

    @objc var isRemoteAudioMuted: Bool {
        return audioProxy.muted
    }

    @objc func setRemoteAudioMuted(_ muted: Bool) {
        audioProxy.muted = muted
        audioEngine?.isMuted = muted
        delegate?.conductorStateDidChange()
    }

    @objc var audioMicAuthorizedByUser: Bool {
        return audioMicAuthorized == true
    }

    @objc func setAudioMicAuthorizationFromMenu(_ granted: Bool) {
        let host = sshIdentity.stringIdentifier
        if !granted && Conductor.audioHostGrantStore.grant(forHost: host) != nil {
            Conductor.audioHostGrantStore.revoke(host: host)
        }
        audioMicAuthorized = granted
        resolveAudioAuthorization(granted, persist: true)
        if !granted {
            audioDemux?.closeCaptureConnections()
        }
        delegate?.conductorStateDidChange()
    }

    @objc func disconnectRemoteAudio() {
        audioDemux?.closeAll(notifyTransport: true)
        audioEngine?.shutdownAll()
        delegate?.conductorStateDidChange()
    }

    // MARK: - Socket Setup

    func activateAudioProxy(home: String, env: inout [String: String]) {
        let socketPath = Self.pulseSocketPath(home: home)
        pulseSocketPath = socketPath
        env["PULSE_SERVER"] = "unix:" + socketPath
    }

    static func pulseSocketPath(home: String) -> String {
        let result = SSHAudioSocketPath.make(home: home)
        if result.usedTmpFallback {
            RLog("pulse socket for a home of \(home.utf8.count) bytes would exceed the socket path limit; using /tmp")
        }
        return result.path
    }
}
