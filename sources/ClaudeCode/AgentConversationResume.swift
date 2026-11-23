//
//  AgentConversationResume.swift
//  iTerm2SharedARC
//
//  Offers to resume AI coding agent conversations that a restart ended (issue 13171).
//
//  The agent hook tells iTerm2 which conversation is running in each session (it2 session
//  set-agent-conversation, which calls iterm2.set_agent_conversation). The session keeps that in
//  its restorable state. When restoration has to start a new shell because the old job is gone,
//  as after a reboot or a quit that killed the jobs, the restored session shows an announcement
//  offering to resume the conversation. Nothing is typed unless the user asks for it.
//

import Foundation

/// Which agent conversation was last reported running in a session.
///
/// The values come through the scripting API, which any program the user runs can reach, and they
/// end up typed into a shell, so this accepts only what the command needs: a known agent, a UUID,
/// and a directory without control characters. The command itself is built here, never taken from
/// the caller.
@objc(iTermAgentConversationRecord)
final class AgentConversationRecord: NSObject {
    enum Agent: String {
        case claude
        case codex
    }

    let agent: Agent
    /// Lowercase canonical UUID.
    let conversationID: String
    /// The directory the agent ran in, or nil when unknown.
    let directory: String?
    /// The file the agent keeps the conversation in, or nil when unknown. The agent writes it
    /// only once the conversation has a message; until then there is nothing to resume.
    let transcript: String?

    private static let agentKey = "agent"
    private static let conversationIDKey = "conversation id"
    private static let directoryKey = "directory"
    private static let transcriptKey = "transcript"

    init?(agent: String, conversationID: String, directory: String?, transcript: String? = nil) {
        guard let agent = Agent(rawValue: agent),
              let uuid = UUID(uuidString: conversationID) else {
            return nil
        }
        self.agent = agent
        self.conversationID = uuid.uuidString.lowercased()
        self.directory = Self.usablePath(directory)
        self.transcript = Self.usablePath(transcript)
        super.init()
    }

    /// `path` if it is absolute and free of control characters, else nil.
    private static func usablePath(_ path: String?) -> String? {
        guard let path, path.hasPrefix("/"),
              path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return path
    }

    @objc(initWithDictionary:)
    convenience init?(dictionary: NSDictionary) {
        guard let agent = dictionary[Self.agentKey] as? String,
              let conversationID = dictionary[Self.conversationIDKey] as? String else {
            return nil
        }
        self.init(agent: agent,
                  conversationID: conversationID,
                  directory: dictionary[Self.directoryKey] as? String,
                  transcript: dictionary[Self.transcriptKey] as? String)
    }

    @objc var dictionaryValue: NSDictionary {
        var result: [String: String] = [Self.agentKey: agent.rawValue,
                                        Self.conversationIDKey: conversationID]
        if let directory {
            result[Self.directoryKey] = directory
        }
        if let transcript {
            result[Self.transcriptKey] = transcript
        }
        return result as NSDictionary
    }

    /// The command that resumes the conversation, typed into a shell that starts in
    /// `launchDirectory`. It changes directory first when the agent ran somewhere else, since an
    /// agent looks for the conversation among those of the directory it starts in.
    func command(launchDirectory: String?) -> String {
        // Localization unneeded
        let resume: String
        switch agent {
        case .claude:
            resume = "claude --resume \(conversationID)"
        case .codex:
            resume = "codex resume \(conversationID)"
        }
        guard let directory, !Self.sameDirectory(directory, launchDirectory) else {
            return resume
        }
        let escaped = (directory as NSString).withEscapedShellCharacters(includingNewlines: true)
        return "cd \(escaped) && \(resume)"
    }

    private static func sameDirectory(_ a: String, _ b: String?) -> Bool {
        guard let b else {
            return false
        }
        return (a as NSString).standardizingPath == (b as NSString).standardizingPath
    }

    /// Whether the agent was running in the session when its state was saved, judging by the
    /// foreground job's ancestry then (lowercased argv[0]s, deepest first). Without this, a
    /// conversation that ended in a way the hook could not see (a crash, an exit mid-turn) would
    /// be offered after every later restart. The agent's own name must appear: npm installs of
    /// both agents run a native binary (claude.exe, or codex with a platform suffix such as
    /// codex-aarch64-apple-darwin) rather than running inside node, so a node or bun process in
    /// the ancestry is some other program, such as a dev server started after the agent ended.
    func wasRunning(inForegroundJobAncestry names: [String]) -> Bool {
        let agentName = agent.rawValue
        return names.contains { name in
            let base = (name as NSString).lastPathComponent
            return base == agentName || base.hasPrefix(agentName + "-") || base.hasPrefix(agentName + ".")
        }
    }

    /// Whether resuming makes sense on this Mac: the agent's directory must still be there.
    var directoryExists: Bool {
        guard let directory else {
            return true
        }
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Whether there is a conversation to resume: the agent has written its transcript. True when
    /// the transcript is unknown.
    var transcriptExists: Bool {
        guard let transcript else {
            return true
        }
        return FileManager.default.fileExists(atPath: transcript)
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? AgentConversationRecord else {
            return false
        }
        return (agent == other.agent &&
                conversationID == other.conversationID &&
                directory == other.directory &&
                transcript == other.transcript)
    }

    override var hash: Int {
        return conversationID.hash
    }

    override var description: String {
        return "<AgentConversationRecord \(agent.rawValue) \(conversationID) in \(directory ?? "(unknown)")>"
    }
}

/// Holds the offers to resume conversations in restored sessions. Offers wait until launch-time
/// restoration has created every session it is going to, so each banner knows whether there is
/// more than one and can offer Resume All.
@objc(iTermAgentConversationResumeOffers)
final class AgentConversationResumeOffers: NSObject {
    @objc static let shared = AgentConversationResumeOffers()

    static let announcementIdentifier = "AgentConversationResumeOffer"

    /// What a button on an offer does.
    enum Action {
        case resume
        case resumeAll
        case dontAskAgain
    }

    // Seams for tests. Production uses the advanced setting and the session's own input.
    var isEnabled: () -> Bool = { iTermAdvancedSettingsModel.offerToResumeAgentConversations() }
    var disable: () -> Void = { iTermAdvancedSettingsModel.setOfferToResumeAgentConversations(false) }
    var typeText: (PTYSession, String) -> Void = { session, text in session.writeTaskNoBroadcast(text) }
    /// False while shell integration says the session is not at a prompt yet.
    var isReadyForInput: (PTYSession) -> Bool = { session in
        !session.screen.shellIntegrationInstalled || session.isAtShellPrompt
    }

    private struct Offer {
        let session: WeakBox<PTYSession>
        let record: AgentConversationRecord
        let launchDirectory: String?
        var actions = [Action]()
        /// Tells this offer's banner from one that replaced it in the same session.
        var token = UUID()
    }

    /// Relaunched sessions waiting for restoration to finish.
    private var pending = [Offer]()
    /// Offers on screen.
    private var shown = [Offer]()
    /// Resumes the user asked for before the shell had shown its first prompt. Each is typed
    /// when its session's next prompt appears.
    private var awaitingPrompt = [Offer]()
    private var restorationFinished = false

    /// Records what the agent hook reported. Any report means an agent has run in the session
    /// since the offer was made, very likely the user resuming this same conversation by hand, so
    /// the offer goes whatever the conversation is. Typing the command into a running agent is
    /// what this prevents.
    /// The agent hook reported, through iterm2.set_agent_conversation, that `session` now runs
    /// this conversation. Nothing is recorded where the conversation could not be resumed after a
    /// restart, or for arguments that make no sense; the report still withdraws any offer.
    func conversationDidStart(_ conversationID: String,
                              agent: String,
                              directory: String?,
                              transcript: String?,
                              in session: PTYSession) {
        guard let record = AgentConversationRecord(agent: agent,
                                                   conversationID: conversationID,
                                                   directory: directory,
                                                   transcript: transcript) else {
            DLog("Ignoring agent conversation \(conversationID) from \(agent) in \(session): not an agent and a UUID")
            setConversation(nil, in: session)
            return
        }
        guard Self.canResume(in: session) else {
            DLog("Ignoring agent conversation in \(session): it would not run in a relaunched shell")
            setConversation(nil, in: session)
            return
        }
        setConversation(record, in: session)
    }

    /// The agent hook reported that a conversation in `session` ended. Only the user quitting on
    /// purpose forgets it: the agent also ends when it is killed, as while macOS shuts down, and
    /// that is what the offer is for. The ID must match, since on /clear the old conversation's
    /// end can arrive after the new one's start.
    func conversationDidEnd(_ conversationID: String, userQuit: Bool, in session: PTYSession) {
        guard userQuit,
              let record = session.agentConversation,
              UUID(uuidString: conversationID)?.uuidString.lowercased() == record.conversationID else {
            return
        }
        setConversation(nil, in: session)
    }

    /// Whether a conversation in `session` would run in a new shell there after a restart. An
    /// agent on a host reached through SSH Integration would not, nor would one in a tmux pane,
    /// which restoration does not relaunch.
    static func canResume(in session: PTYSession) -> Bool {
        return session.hostConductor == nil && !session.isTmuxClient
    }

    func setConversation(_ record: AgentConversationRecord?, in session: PTYSession) {
        DLog("Agent conversation in \(session) is now \(record?.description ?? "none")")
        withdraw(session)
        session.agentConversation = record
    }

    /// Called when restoring `session` started a new job because the old one was gone.
    /// `launchDirectory` is where the new shell starts. `foregroundJobAncestors` is the
    /// foreground job's ancestry when the session was saved, or nil if none was saved.
    @objc(sessionDidRelaunch:launchDirectory:foregroundJobAncestors:)
    func sessionDidRelaunch(_ session: PTYSession,
                            launchDirectory: String?,
                            foregroundJobAncestors: [String]?) {
        guard let record = session.agentConversation else {
            DLog("Not offering to resume in \(session): no agent conversation was recorded")
            return
        }
        guard record.wasRunning(inForegroundJobAncestry: foregroundJobAncestors ?? []) else {
            DLog("Not offering to resume \(record) in \(session): it was not running when the session was saved (ancestry \(foregroundJobAncestors ?? []))")
            session.agentConversation = nil
            return
        }
        guard isEnabled() else {
            DLog("Not offering to resume \(record) in \(session): turned off")
            return
        }
        guard record.directoryExists else {
            DLog("Not offering to resume \(record) in \(session): its directory is gone")
            session.agentConversation = nil
            return
        }
        guard record.transcriptExists else {
            DLog("Not offering to resume \(record) in \(session): it has no transcript, so it never got a message or was deleted")
            session.agentConversation = nil
            return
        }
        RLog("Will offer to resume \(record.agent.rawValue) conversation \(record.conversationID) in \(session.guid)")
        let offer = Offer(session: WeakBox(session), record: record, launchDirectory: launchDirectory)
        if restorationFinished {
            // Restoration reports that it finished before every relaunched session is done
            // starting, so offers can trickle in after it. Banners already up gain Resume All.
            let others = liveShownOffers()
            show(offer, offerAll: !others.isEmpty)
            for other in others where !other.actions.contains(.resumeAll) {
                shown.removeAll { $0.token == other.token }
                show(other, offerAll: true)
            }
        } else {
            pending.append(offer)
        }
    }

    /// Called once launch-time restoration has created its sessions.
    @objc func sessionsDidFinishRestoring() {
        guard !restorationFinished else {
            return
        }
        restorationFinished = true
        let batch = pending.filter { $0.session.value != nil }
        pending = []
        let offerAll = batch.count + liveShownOffers().count > 1
        for offer in batch {
            show(offer, offerAll: offerAll)
        }
    }

    private func liveShownOffers() -> [Offer] {
        shown.removeAll { $0.session.value == nil }
        return shown
    }

    private func show(_ offer: Offer, offerAll: Bool) {
        guard let session = offer.session.value else {
            return
        }
        let title: String
        switch offer.record.agent {
        case .claude:
            title = String(localized: "AgentResume.Offer.Claude",
                           defaultValue: "Claude Code was running here before iTerm2 restarted. Resume the conversation?",
                           comment: "Announcement shown in a restored session where a Claude Code conversation was ended by a restart of iTerm2 or the Mac")
        case .codex:
            title = String(localized: "AgentResume.Offer.Codex",
                           defaultValue: "Codex was running here before iTerm2 restarted. Resume the conversation?",
                           comment: "Announcement shown in a restored session where a Codex CLI conversation was ended by a restart of iTerm2 or the Mac")
        }
        var actions: [(Action, String)] = [
            (.resume, String(localized: "AgentResume.Resume",
                             defaultValue: "Resume",
                             comment: "Button that resumes an AI coding agent conversation in this session by typing the command that resumes it"))]
        if offerAll {
            actions.append((.resumeAll, String(localized: "AgentResume.ResumeAll",
                                               defaultValue: "Resume All",
                                               comment: "Button that resumes the AI coding agent conversations in every restored session that offers to")))
        }
        actions.append((.dontAskAgain, String(localized: "AgentResume.DontAskAgain",
                                              defaultValue: "Don’t Ask Again",
                                              comment: "Button that stops iTerm2 from offering to resume AI coding agent conversations after a restart")))
        let record = offer.record
        var shownOffer = offer
        shownOffer.actions = actions.map { $0.0 }
        shownOffer.token = UUID()
        let token = shownOffer.token
        // Called with the button's index, and again with -2 once the announcement goes away,
        // whether after a button, because it was closed, or because a new banner replaced it.
        let completion: (Int32) -> Void = { [weak self, weak session] selection in
            guard let self, let session else {
                return
            }
            if selection >= 0 && Int(selection) < actions.count {
                self.perform(actions[Int(selection)].0, in: session)
            } else if selection == -2 {
                self.offerDidGoAway(in: session, record: record, token: token)
            }
        }
        guard let announcement = iTermAnnouncementViewController.announcement(withTitle: title,
                                                                                style: .kiTermAnnouncementViewStyleQuestion,
                                                                                withActions: actions.map { $0.1 },
                                                                                completion: completion) else {
            return
        }
        // Before queueing, which dismisses a banner this one replaces.
        shown.append(shownOffer)
        session.queueAnnouncement(announcement, identifier: Self.announcementIdentifier)
    }

    /// The buttons an offer in `session` shows, or nil when it shows none. Internal for tests.
    func actionsOffered(in session: PTYSession) -> [Action]? {
        return shown.first { $0.session.value === session }?.actions
    }

    /// Carries out a button press on the offer in `session`. Internal for tests.
    func perform(_ action: Action, in session: PTYSession) {
        switch action {
        case .resume:
            resume(session)
        case .resumeAll:
            resumeAll()
        case .dontAskAgain:
            stopOffering()
        }
    }

    /// Types the command. With shell integration, a session that is not at a prompt yet (the
    /// usual case right after launch, while the shell starts up) gets it at its next prompt
    /// instead. Without shell integration there is no telling, and the user asked for it.
    private func resume(_ session: PTYSession) {
        guard let index = shown.firstIndex(where: { $0.session.value === session }) else {
            return
        }
        let offer = shown.remove(at: index)
        if !isReadyForInput(session) {
            RLog("Will resume \(offer.record.agent.rawValue) conversation \(offer.record.conversationID) in \(session.guid) at its next prompt")
            awaitingPrompt.append(offer)
            return
        }
        type(offer, into: session)
    }

    private func type(_ offer: Offer, into session: PTYSession) {
        guard session.agentConversation == offer.record else {
            DLog("Not resuming in \(session): the conversation changed to \(session.agentConversation?.description ?? "none")")
            return
        }
        RLog("Resuming \(offer.record.agent.rawValue) conversation \(offer.record.conversationID) in \(session.guid)")
        session.agentConversation = nil
        typeText(session, offer.record.command(launchDirectory: offer.launchDirectory) + "\n")
    }

    /// Called when shell integration reports that `session` finished drawing a prompt.
    @objc(sessionDidShowPrompt:)
    func sessionDidShowPrompt(_ session: PTYSession) {
        awaitingPrompt.removeAll { $0.session.value == nil }
        guard let index = awaitingPrompt.firstIndex(where: { $0.session.value === session }) else {
            return
        }
        type(awaitingPrompt.remove(at: index), into: session)
    }

    /// Whether a resume is waiting for `session`'s next prompt. Internal for tests.
    func isAwaitingPrompt(_ session: PTYSession) -> Bool {
        return awaitingPrompt.contains { $0.session.value === session }
    }

    private func resumeAll() {
        for offer in liveShownOffers() {
            guard let session = offer.session.value else {
                continue
            }
            resume(session)
            session.dismissAnnouncement(withIdentifier: Self.announcementIdentifier)
        }
    }

    private func stopOffering() {
        RLog("User turned off offers to resume agent conversations")
        disable()
        for offer in liveShownOffers() {
            offer.session.value?.dismissAnnouncement(withIdentifier: Self.announcementIdentifier)
        }
    }

    /// Closing the offer declines it, so the conversation is forgotten rather than offered again
    /// after the next restart. One the hook has replaced since is left alone, and so is one
    /// whose resume is waiting for a prompt, and so is a banner that another replaced, or that
    /// was withdrawn.
    private func offerDidGoAway(in session: PTYSession, record: AgentConversationRecord, token: UUID) {
        guard shown.contains(where: { $0.token == token }) else {
            return
        }
        shown.removeAll { $0.token == token || $0.session.value == nil }
        if session.agentConversation === record && !isAwaitingPrompt(session) {
            session.agentConversation = nil
        }
    }

    private func withdraw(_ session: PTYSession) {
        pending.removeAll { $0.session.value === session }
        awaitingPrompt.removeAll { $0.session.value === session }
        guard shown.contains(where: { $0.session.value === session }) else {
            return
        }
        shown.removeAll { $0.session.value === session }
        session.dismissAnnouncement(withIdentifier: Self.announcementIdentifier)
    }
}
