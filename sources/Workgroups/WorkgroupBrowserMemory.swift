//
//  WorkgroupBrowserMemory.swift
//  iTerm2
//
//  Remembers what a workgroup's browser showed for each agent conversation.
//

import Foundation

/// An agent such as Claude Code shows pages in a workgroup's browser by setting
/// user variables (see WorkgroupBrowserURLBinding). Resuming the conversation
/// later starts a new workgroup whose browser is blank, and the agent has no
/// reason to set them again. So iTerm2 keeps the variables each browser member
/// was last given, keyed by the agent's conversation ID, and sets them again
/// when that conversation starts.
///
/// The agent's hook reports the ID when a conversation starts or resumes
/// (`it2 session set-agent-conversation`), and again when it ends.
/// Resuming keeps the ID; a new conversation, or /clear, gets a new one, so it
/// finds nothing to restore.
final class WorkgroupBrowserMemory {
    static let shared: WorkgroupBrowserMemory = {
        let memory = WorkgroupBrowserMemory(defaults: iTermUserDefaults.userDefaults())
        memory.forgetSessionsWhenTheyTerminate()
        return memory
    }()

    // Holds URLs, so tools/sanitize_iterm2_plist.py removes it.
    static let userDefaultsKey = "NoSyncWorkgroupBrowserMemory"

    /// Conversations remembered. The oldest are forgotten first.
    static let capacity = 100

    struct Entry: Equatable {
        var conversation: String
        /// The browser member's config uniqueIdentifier, which every instance
        /// of a workgroup shares.
        var member: String
        /// User variable paths to the values last set.
        var values: [String: String]
    }

    private let defaults: UserDefaults
    // Session GUID to the conversation its agent last reported. Not saved
    // here: an agent that keeps running across a relaunch never reports again,
    // so a workgroup saves its leader's conversation with its restoration data
    // (iTermWorkgroupRestoration.Key.agentConversation), and restoring puts
    // it back here and on the instance that adopts it. A workgroup adopted
    // from tmux doesn't, so its agent goes unrecorded until it starts or
    // resumes a conversation.
    private var conversationsBySessionGUID = [String: Report]()

    struct Report: Equatable {
        var conversation: String
        /// The session's job pid when the agent reported, if known. iTerm2
        /// polls for the foreground job, so just after an agent starts the pid
        /// is still the shell's; see iTermWorkgroupInstance.agentConversationID.
        /// Cleared once the job moves on, so a later return to that shell
        /// doesn't count.
        var jobPID: Int32?
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: - Conversations

    func setConversation(_ conversation: String, forSessionGUID guid: String, jobPID: Int32? = nil) {
        conversationsBySessionGUID[guid] = Report(conversation: conversation, jobPID: jobPID)
    }

    func report(forSessionGUID guid: String) -> Report? {
        return conversationsBySessionGUID[guid]
    }

    /// The session's job is now `jobPID`. If that isn't the job the report
    /// was made from, the job poll has caught up, and the report's job pid
    /// stops vouching for the conversation.
    func jobChanged(forSessionGUID guid: String, to jobPID: Int32?) {
        guard let reported = conversationsBySessionGUID[guid]?.jobPID, reported != jobPID else {
            return
        }
        conversationsBySessionGUID[guid]?.jobPID = nil
    }

    func conversation(forSessionGUID guid: String) -> String? {
        return conversationsBySessionGUID[guid]?.conversation
    }

    func forgetSession(guid: String) {
        conversationsBySessionGUID.removeValue(forKey: guid)
    }

    /// Forgets `conversation` for the session only if it is still the one on
    /// record, so a late report that it ended can't erase a newer one.
    func forgetConversation(_ conversation: String, forSessionGUID guid: String) {
        if conversationsBySessionGUID[guid]?.conversation == conversation {
            conversationsBySessionGUID.removeValue(forKey: guid)
        }
    }

    private var terminationObserver: NSObjectProtocol?

    private func forgetSessionsWhenTheyTerminate() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.iTermSessionWillTerminate,
            object: nil,
            queue: nil) { [weak self] notification in
                guard let session = notification.object as? PTYSession else {
                    return
                }
                self?.forgetSession(guid: session.guid)
            }
    }

    // MARK: - Values

    func values(conversation: String, member: String) -> [String: String]? {
        return entries.last { $0.conversation == conversation && $0.member == member }?.values
    }

    func record(_ values: [String: String], conversation: String, member: String) {
        guard !values.isEmpty else {
            return
        }
        var updated = entries.filter { !($0.conversation == conversation && $0.member == member) }
        updated.append(Entry(conversation: conversation, member: member, values: values))
        // A conversation can have more than one browser member, so the cap
        // counts conversations rather than entries.
        var keep = Set<String>()
        for entry in updated.reversed() where keep.count < Self.capacity {
            keep.insert(entry.conversation)
        }
        entries = updated.filter { keep.contains($0.conversation) }
    }

    // Oldest first.
    private(set) var entries: [Entry] {
        get {
            guard let array = defaults.array(forKey: Self.userDefaultsKey) else {
                return []
            }
            return array.compactMap { item in
                guard let dict = item as? [String: Any],
                      let conversation = dict["conversation"] as? String,
                      let member = dict["member"] as? String,
                      let values = dict["values"] as? [String: String] else {
                    return nil
                }
                return Entry(conversation: conversation, member: member, values: values)
            }
        }
        set {
            let array: [[String: Any]] = newValue.map {
                ["conversation": $0.conversation, "member": $0.member, "values": $0.values]
            }
            defaults.set(array, forKey: Self.userDefaultsKey)
        }
    }
}

/// `iterm2.set_agent_conversation(session_id:, conversation_id:, ended:)`
/// records which agent conversation `session_id` runs, and brings back what its
/// workgroup's browser showed for it. With `ended: true` it says that
/// conversation is over, which forgets it only if it is still the session's:
/// on /clear the old conversation's SessionEnd hook and the new one's
/// SessionStart hook run as separate processes, and the end may arrive last.
/// Agent hooks call it through `it2 session set-agent-conversation`.
@objc(iTermAgentConversationBuiltInFunction)
class AgentConversationBuiltInFunction: NSObject {
}

extension AgentConversationBuiltInFunction: iTermBuiltInFunctionProtocol {
    private static let errorDomain = "com.iterm2.set-agent-conversation"
    private static let sessionIDArg = "session_id"
    private static let conversationIDArg = "conversation_id"
    private static let endedArg = "ended"
    // For the offer to resume after a restart (AgentConversationResume.swift).
    private static let quitArg = "quit"
    private static let agentArg = "agent"
    private static let directoryArg = "directory"
    private static let transcriptArg = "transcript"

    private static func error(_ message: String) -> NSError {
        return NSError(domain: errorDomain,
                       code: 1,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func register() {
        let builtInFunction = iTermBuiltInFunction(
            name: "set_agent_conversation",
            arguments: [sessionIDArg: NSString.self,
                        conversationIDArg: NSString.self,
                        endedArg: NSNumber.self,
                        quitArg: NSNumber.self,
                        agentArg: NSString.self,
                        directoryArg: NSString.self,
                        transcriptArg: NSString.self],
            optionalArguments: Set([endedArg, quitArg, agentArg, directoryArg, transcriptArg]),
            defaultValues: [:],
            context: .app,
            sideEffectsPlaceholder: "[set_agent_conversation]") { parameters, completion in
                guard let sessionID = parameters[sessionIDArg] as? String,
                      let conversationID = parameters[conversationIDArg] as? String,
                      !conversationID.isEmpty else {
                    completion(nil, error(String(localized: "SetAgentConversation.MissingArgument",
                                                 defaultValue: "Missing required argument",
                                                 comment: "Error when a required argument to set_agent_conversation is absent")))
                    return
                }
                guard let session = iTermController.sharedInstance()?.anySession(withGUID: sessionID) else {
                    completion(nil, error(String(localized: "SetAgentConversation.NoSuchSession",
                                                 defaultValue: "No such session",
                                                 comment: "Error when set_agent_conversation is given a session ID that matches no session")))
                    return
                }
                // Only the leader's agent drives the browser (see
                // iTermWorkgroupInstance.agentConversationID).
                let instance = session.workgroupInstance.flatMap { $0.mainSession === session ? $0 : nil }
                if (parameters[endedArg] as? NSNumber)?.boolValue == true {
                    DLog("Session \(sessionID) ended agent conversation \(conversationID)")
                    WorkgroupBrowserMemory.shared.forgetConversation(conversationID, forSessionGUID: session.guid)
                    if instance?.leaderConversationID == conversationID {
                        instance?.leaderConversationID = nil
                        instance?.leaderReportJobPID = nil
                    }
                    AgentConversationResumeOffers.shared.conversationDidEnd(
                        conversationID,
                        userQuit: (parameters[quitArg] as? NSNumber)?.boolValue == true,
                        in: session)
                    completion(nil, nil)
                    return
                }
                if let agent = parameters[agentArg] as? String {
                    AgentConversationResumeOffers.shared.conversationDidStart(
                        conversationID,
                        agent: agent,
                        directory: parameters[directoryArg] as? String,
                        transcript: parameters[transcriptArg] as? String,
                        in: session)
                }
                // The report itself shows an agent runs there, though the job
                // iTerm2 last polled may still be the shell.
                let jobPID = iTermWorkgroupInstance.jobPID(of: session)
                DLog("Session \(sessionID) runs agent conversation \(conversationID); its job pid is \(jobPID.map(String.init) ?? "unknown")")
                WorkgroupBrowserMemory.shared.setConversation(conversationID, forSessionGUID: session.guid, jobPID: jobPID)
                if let instance {
                    instance.leaderConversationID = conversationID
                    instance.leaderReportJobPID = jobPID
                    instance.agentConversationDidStart()
                }
                completion(nil, nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }
}
