//
//  SecureUserDefaults.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/7/22.
//

import Foundation

protocol SecureUserDefaultStringTranscodable {
    var sudString: String { get }
    init?(sudString: String) throws
}

enum SecureUserDefaultValueError: Error {
    case decodingFailed
}

struct SecureUserDefaultValue<T: SecureUserDefaultStringTranscodable> {
    let value: T
    var encodedString: String {
        return (value.sudString.data(using: .utf8)! as NSData).it_hexEncoded()
    }
    init(value: T) {
        self.value = value
    }
    init?(sudString string: String) throws {
        let data = (string as NSString).dataFromHexValues()
        guard let decodedString = String(data: data, encoding: .utf8) else {
            return nil
        }
        guard let decoded = try T(sudString: decodedString) else {
            return nil
        }
        value = decoded
    }
}

extension Bool: SecureUserDefaultStringTranscodable {
    var sudString: String {
        return String(self)
    }
    init?(sudString string: String) throws {
        guard let b = Bool(string) else {
            throw SecureUserDefaultValueError.decodingFailed
        }
        self = b
    }
}

extension String: SecureUserDefaultStringTranscodable {
    var sudString: String {
        self
    }
    init?(sudString string: String) throws {
        self = string
    }
}

protocol SerializableUserDefault {
    var key: String { get }
    func encode(to: inout [String: String])
    func setFromSerialized(value: String)
}

struct SecureUserDefaults {
    static var instance = SecureUserDefaults()

    mutating func serializeAll() -> [String: String] {
        var result = [String: String]()
        for serializable in serializables() {
            serializable.encode(to: &result)
        }
        return result
    }

    mutating func deserializeAll(dict: [String: String]) {
        for serializable in serializables() {
            if let json = dict[serializable.key] {
                serializable.setFromSerialized(value: json)
            }
        }
    }

    lazy var allowPaste = { SecureUserDefault<Bool>("AllowPaste", defaultValue: false) }()
    lazy var requireAuthToOpenPasswordmanager = { SecureUserDefault<Bool>("RequireAuthenticationToOpenPasswordManager", defaultValue: true) }()
    lazy var enableSecureKeyboardEntryAutomatically = { SecureUserDefault<Bool>("EnableSecureKeyboardEntryAutomatically", defaultValue: true) }()
    lazy var enableAI = { SecureUserDefault<Bool>("EnableAI", defaultValue: false) }()
    lazy var enableCompanionPairing = { SecureUserDefault<Bool>("EnableCompanionPairing", defaultValue: false) }()
    lazy var browserBundleID = { SecureUserDefault<String>("BrowserBundleID", defaultValue: "") }()
    lazy var aiCompletionsEnabled = { SecureUserDefault<Bool>("AICompletions", defaultValue: false) }()

    /// Grant AI and/or companion consent in a SINGLE administrator prompt.
    /// Setting these one at a time (the normal `set(true)` path) puts up one
    /// password dialog per value; the onboarding wizard needs both granted at
    /// once without making the user authenticate twice. Only the requested values
    /// are written, and only the `true` direction is supported here (revoking is
    /// fail-safe and needs no auth, so it stays on the per-value `reset()` path).
    ///
    /// Static, not a mutating instance method, on purpose: storeBatch posts
    /// secureUserDefaultDidChange synchronously, and its observers read
    /// SecureUserDefaults.instance (the companion gate does). A mutating method
    /// would hold exclusive access to `instance` across that callout and trip the
    /// Swift exclusivity checker. So gather the writes with brief accesses first,
    /// then run the batch with no access to `instance` held.
    static func grantConsent(ai: Bool, companion: Bool) throws {
        var writes: [SecureUserDefault<Bool>.PendingWrite] = []
        if ai {
            writes.append(instance.enableAI.pendingWrite(true))
        }
        if companion {
            writes.append(instance.enableCompanionPairing.pendingWrite(true))
        }
        guard !writes.isEmpty else { return }
        // storeBatch is not atomic across keys: an earlier statement can commit
        // its file before a later one fails (and on failure it posts no
        // notifications). Remember the prior values so a partial failure can be
        // rolled back to a consistent state rather than silently leaving one
        // consent on.
        let priorAI = instance.enableAI.value
        let priorCompanion = instance.enableCompanionPairing.value
        // The batch write changes the on-disk files; invalidate the in-memory
        // caches so the next read reflects the new values.
        instance.enableAI.invalidateCache()
        instance.enableCompanionPairing.invalidateCache()
        do {
            try SecureUserDefault<Bool>.storeBatch(writes)
        } catch {
            // Revert any key this call may have partially written back to its
            // prior value (reset needs no authorization), so a caller never sees a
            // half-applied grant.
            if ai, !priorAI { try? instance.enableAI.reset() }
            if companion, !priorCompanion { try? instance.enableCompanionPairing.reset() }
            instance.enableAI.invalidateCache()
            instance.enableCompanionPairing.invalidateCache()
            throw error
        }
    }

    private var hostToOpenURLSUDs = [String: SecureUserDefault<Bool>]()
    mutating func openURL(host: String) -> SecureUserDefault<Bool> {
        if let value = hostToOpenURLSUDs[host] {
            return value
        }
        let safeHost = host.lossyData.hexified
        let sud = SecureUserDefault<Bool>("OpenURL" + safeHost,
                                          defaultValue: false)
        hostToOpenURLSUDs[host] = sud
        return sud
    }
    private mutating func serializables() -> [any SerializableUserDefault] {
        [allowPaste,
         requireAuthToOpenPasswordmanager,
         enableSecureKeyboardEntryAutomatically,
         enableAI,
         enableCompanionPairing,
         browserBundleID,
         aiCompletionsEnabled] + Array(hostToOpenURLSUDs.values)
    }
}

fileprivate let secureUserDefaultDidChange = NSNotification.Name("iTermSecureUserDefaultDidChange")

@objc
class iTermSecureUserDefaults: NSObject {
    static let didChange = secureUserDefaultDidChange
    @objc static let secureUserDefaultsDidChangeNotificationName = secureUserDefaultDidChange

    @objc static let instance = iTermSecureUserDefaults()
    @objc var requireAuthToOpenPasswordManager: Bool {
        get {
            return SecureUserDefaults.instance.requireAuthToOpenPasswordmanager.value
        }
        set {
            try? SecureUserDefaults.instance.requireAuthToOpenPasswordmanager.set(newValue)
        }
    }
    @objc var defaultValue_enableSecureKeyboardEntryAutomatically: Bool {
        return SecureUserDefaults.instance.enableSecureKeyboardEntryAutomatically.defaultValue
    }
    @objc var enableSecureKeyboardEntryAutomatically: Bool {
        get {
            return SecureUserDefaults.instance.enableSecureKeyboardEntryAutomatically.value
        }
        set {
            try? SecureUserDefaults.instance.enableSecureKeyboardEntryAutomatically.set(newValue)
        }
    }
    @objc var enableAI: Bool {
        get {
            return SecureUserDefaults.instance.enableAI.value
        }
        set {
            try? SecureUserDefaults.instance.enableAI.set(newValue)
        }
    }
    @objc var defaultValue_browserBundleID: String {
        return SecureUserDefaults.instance.browserBundleID.defaultValue
    }
    @objc var browserBundleID: String {
        get {
            return SecureUserDefaults.instance.browserBundleID.value
        }
        set {
            try? SecureUserDefaults.instance.browserBundleID.set(newValue)
        }
    }
    @objc var defaultValue_aiCompletionsEnabled: Bool {
        return SecureUserDefaults.instance.aiCompletionsEnabled.defaultValue
    }
    @objc var aiCompletionsEnabled: Bool {
        get {
            return SecureUserDefaults.instance.aiCompletionsEnabled.value
        }
        set {
            try? SecureUserDefaults.instance.aiCompletionsEnabled.set(newValue)
        }
    }
    @objc static var aiCompletionsKey: String {
        SecureUserDefaults.instance.aiCompletionsEnabled.key
    }
    @objc(resetAICompletionsEnabled) func resetAICompletionsEnabled() {
        try? SecureUserDefaults.instance.aiCompletionsEnabled.reset()
    }
    @objc static func openURL(host: String) -> Bool {
        SecureUserDefaults.instance.openURL(host: host).value
    }
    @objc static func setOpenURL(host: String, allowed: Bool) {
        try? SecureUserDefaults.instance.openURL(host: host).set(allowed)
    }
}

// Save secure user defaults here if the home directory is on a network mount.
// Secure user defaults must be writable only by root and network mounts obviously can't do that.
fileprivate var FallbackFolder: String {
    if let suite = iTermUserDefaults.customSuiteName() as String? {
        return "/usr/local/\(suite)-secure-settings"
    }
    return "/usr/local/iTerm2-secure-settings"
}

// (path, is unix filesystem)
fileprivate var secureUserDefaultsFolderIsOnUnixFilesystem: (String, Bool)?

// (path, supports ownserhip)
fileprivate var secureUserDefaultsFolderIsOnOwnershipSupportingFilesystem: (String, Bool)?

// Secure user defaults are a way of saving user preferences that are hard to tamper with.
// Like UserDefaults, it is a database of key-value pairs.
// Unlike UserDefaults, the user must authenticate to set a value.
// Values can be restored to their default state without authentication, so they must fail safe.
// The implementation is to create a file owned by root that holds the setting.
// The file's contents are:
// <encoded path> <sha of key>\n<value>
// Where:
//   * <encoded path> is the path to the file as hex-encoded UTF-8.
//   * <sha of key> is the hex-encoded SHA-256 of the user defaults key. The key is the same as the filename minus directory and extension.
//   * <value> is a hex-encoded UTF8 string representation of the value (e.g., "true" or "false" for a boolean). It is hex encoded to avoid injection bugs during writing.
class SecureUserDefault<T: SecureUserDefaultStringTranscodable & Codable & Equatable> {
    let key: String
    let defaultValue: T
    private var cached: T?

    enum SecureUserDefaultError: LocalizedError {
        case usrLocalIsFile
        case failedToCreateUsrLocal
        case badMagic
        case scriptError(String?)
        case directoryDoesNotExist

        var errorDescription: String? {
            switch self {
            case .usrLocalIsFile:
                "\(FallbackFolder) is a file, not a directory. Please remove it and try again."
            case .failedToCreateUsrLocal:
                "Failed to create \(FallbackFolder). Please manually create this folder."
            case .badMagic:
                "The secure user default is corrupted."
            case .scriptError(let message):
                message
            case .directoryDoesNotExist:
                "The containing directory for secure user defaults does not exist"
            }
        }
    }

    init(_ key: String, defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
    }

    var value: T {
        DLog("Get for \(key)")
        if let cached {
            DLog("Return cached value \(cached)")
            return cached
        }
        DLog("Will get")
        if let value = try? get() {
            DLog("Return value \(value)")
            cached = value
            return value
        }
        cached = defaultValue
        DLog("Return default \(defaultValue)")
        return defaultValue
    }

    var url: URL? {
        return try? Self.path(key, create: false)
    }

    private func get() throws -> T {
        return try Self.load(key) ?? defaultValue
    }

    func set(_ newValue: T?) throws {
        // Keep the value out of the ring (generic path; guard against a future
        // secret-valued key); the opt-in debug log still gets it.
        RLog("Set \(key) to \(redacted: (newValue?.sudString).d, or: "value redacted, length=\((newValue?.sudString).d.count)")")
        cached = nil
        do {
            if let value = newValue {
                DLog("Will store")
                try Self.store(key, value: value)
            } else {
                DLog("Will delete")
                try Self.delete(key)
            }
        } catch {
            RLog("Fail: \(error)")
            iTermWarning.show(withTitle: error.localizedDescription,
                              actions: ["OK"],
                              accessory: nil,
                              identifier: "NoSyncSecureUserDefaultsSetFailed",
                              silenceable: .kiTermWarningTypeTemporarilySilenceable,
                              heading: "Failed to Save Secure Setting",
                              window: nil)
            throw error
        }
    }

    func reset() throws {
        RLog("Reset \(key)")
        cached = nil
        try Self.delete(key)
    }

    /// Drop the in-memory cache so the next read re-loads from disk. Used after a
    /// batch write (storeBatch), which changes the files behind the cache's back.
    func invalidateCache() {
        cached = nil
    }

    /// A single key/value to be written by storeBatch. The value is pre-encoded
    /// (hex of the UTF-8 string form) so the batch primitive, which is generic
    /// over the element type, only needs strings.
    struct PendingWrite {
        let key: String
        let encodedValue: String
    }

    /// Produce a PendingWrite for this default set to `value`, for use with
    /// storeBatch. Does not write anything by itself.
    func pendingWrite(_ value: T) -> PendingWrite {
        return PendingWrite(key: key,
                            encodedValue: SecureUserDefaultValue<T>(value: value).encodedString)
    }

    /// Write several secure settings with ONE administrator prompt. Each write
    /// is the same root-owned mktemp/chmod/mv sequence as store(), but all of
    /// them run inside a single `do shell script ... with administrator
    /// privileges`, so macOS authorizes once for the whole batch. The path/magic
    /// computation is identical to store() so the files load() produces are
    /// indistinguishable from singly-written ones.
    static func storeBatch(_ writes: [PendingWrite]) throws {
        guard !writes.isEmpty else { return }
        let statements = try writes.map {
            try writeStatement(key: $0.key, encodedValue: $0.encodedValue)
        }
        // Each statement aborts the script (exit 1) on its own failure, so a
        // partial batch surfaces as an error here rather than posting change
        // notifications for keys that were never written.
        try runPrivilegedWrites(statements: statements,
                                keys: writes.map { $0.key },
                                prompt: "iTerm2 needs to modify secure settings.")
    }

    private static func fallbackBaseDirectory(create: Bool) throws -> String {
        DLog("create=\(create)")
        // When the user's home directory is not local, we use FallbackFolder
        let path = FallbackFolder

        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            DLog("File exists at \(path)")
            if isDirectory.boolValue {
                // If it already exists and is a directory, just use it.
                DLog("Use it")
                return path
            }
            DLog("Not a directory")
            if !create {
                DLog("Fail, doesn't exist and can't create it")
                throw SecureUserDefaultError.directoryDoesNotExist
            }
            // wtf, it exists but is not a directory.
            DLog("Fail, exists but is not directory")
            throw SecureUserDefaultError.usrLocalIsFile
        }
        if !create {
            DLog("Fail, file doesn't exist and we don't want to create it")
            throw SecureUserDefaultError.directoryDoesNotExist
        }
        // Create it since it does not exist.
        // Folder is owned by root without sticky bit so user can delete files without permission (that enables the delete() method).
        // If the user rewrites a file the ownership changes, which we can check for.
        // I'm not worried about TOCTOU because the threat model is concerned with accidental changes rather than an active attacker.
        let code =
        """
        do shell script "
            umask 000
            /bin/mkdir -m 777 -p \(path)
        " with prompt "iTerm2 needs to create \(path) to store secure settings because your home directory is on a network file system." with administrator privileges
        """
        DLog("Will execute:\n\(code)")
        let script = NSAppleScript(source: code)
        var error: NSDictionary? = nil
        script?.executeAndReturnError(&error)
        DLog("Execution complete")
        if let error {
            RLog("Error \(error)")
            throw SecureUserDefaultError.failedToCreateUsrLocal
        }
        DLog("Success, return \(path)")
        return path
    }

    private static func ignoresOwnership(atPath path: String) -> Bool {
        switch secureUserDefaultsFolderIsOnOwnershipSupportingFilesystem {
        case .some((path, let value)):
            return value
        default:
            break
        }
        var stat = statfs()
        guard path.withCString({ statfs($0, &stat) }) == 0 else {
            DLog("Failed to statfs \(path), assuming filesystem is bad")
            return true
        }
        let result = (stat.f_flags & UInt32(MNT_IGNORE_OWNERSHIP)) != 0
        secureUserDefaultsFolderIsOnOwnershipSupportingFilesystem = (path, result)
        return result
    }

    private static func isOnNonUnixFilesystem(atPath path: String) -> Bool {
        switch secureUserDefaultsFolderIsOnUnixFilesystem {
        case .some((path, let value)):
            return value
        default:
            break
        }
        var stat = statfs()
        guard path.withCString({ statfs($0, &stat) }) == 0 else {
            DLog("Failed to statfs \(path), assuming filesystem is unix")
            return false
        }

        let fsTypeName = withUnsafePointer(to: &stat.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                String(cString: $0)
            }
        }

        // Common non-Unix filesystems
        let nonUnixTypes = [
            "msdos",
            "exfat",
            "ntfs",
            "cifs",
            "webdav"
        ]

        RLog("Filesystem type of \(path) is \(fsTypeName)")
        let result = nonUnixTypes.contains(fsTypeName)
        secureUserDefaultsFolderIsOnUnixFilesystem = (path, result)
        return result
    }

    private static func baseDirectory(create: Bool) throws -> String {
        DLog("create=\(create)")
        guard let appSupportString = FileManager.default.applicationSupportDirectory() else {
            RLog("Failed to get regular app support directory. Use fallback")
            return try fallbackBaseDirectory(create: create)
        }
        DLog("appSupportString=\(appSupportString)")
        // I have to go directly to user defaults rather than through
        // iTermAdvancedSettingsModel because this is called during
        // iTermAdvancedSettingsModel.initialize, so its values may not be
        // loaded yet.
        let pathsToIgnore = iTermUserDefaults.userDefaults().string(forKey: "PathsToIgnore")?.components(
            separatedBy: ",") ?? []
        DLog("pathsToIgnore=\(pathsToIgnore)")
        let isLocal = FileManager.default.fileIsLocal(
            appSupportString,
            additionalNetworkPaths: pathsToIgnore,
            allowNetworkMounts: false)
        if !isLocal {
            RLog("Not local. Use fallback")
            return try fallbackBaseDirectory(create: create)
        }
        if isOnNonUnixFilesystem(atPath: appSupportString) {
            RLog("Not a unix filesystem. Use fallback")
            return try fallbackBaseDirectory(create: create)
        }
        if ignoresOwnership(atPath: appSupportString) {
            RLog("Ownership ignored. Use fallback")
            return try fallbackBaseDirectory(create: create)
        }
        DLog("Use \(appSupportString)")
        return appSupportString
    }

    private static func path(_ key: String,
                             create: Bool) throws -> URL {
        precondition(key.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil)
        let baseURL = URL(fileURLWithPath: try baseDirectory(create: create))
        return baseURL.appendingPathComponent(key).appendingPathExtension("secureSetting")
    }

    private static func magic(_ key: String, filePath: URL) -> String {
        let pathData = filePath.path.data(using: .utf8)! as NSData
        let keyData = key.data(using: .utf8)! as NSData
        let sha = keyData.it_sha256() as NSData
        return "\(pathData.it_hexEncoded()) \(sha.it_hexEncoded())"

    }

    private static func load<U: SecureUserDefaultStringTranscodable>(_ key: String) throws -> U? {
        DLog("load \(key)")
        let fileURL = try Self.path(key, create: false)
        // Check if the file exists before gettings its attributes to avoid an annoying exception
        // while debugging.
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else {
            DLog("Either no file at \(fileURL.path)or failed to get its attributes. exists=\(FileManager.default.fileExists(atPath: fileURL.path)), attrs=\(String(describing: try? FileManager.default.attributesOfItem(atPath: fileURL.path))))")
            return nil
        }
        guard let owner = attributes[.ownerAccountID] as? Int, owner == 0 else {
            // Not owned by root
            RLog("Not owned by root. attributes=\(attributes)")
            return nil
        }
        guard let content = try? String(contentsOf: fileURL) else {
            RLog("Cannot read contents of \(fileURL)")
            return nil
        }
        DLog("content=\(content)")
        guard let newline = content.range(of: "\n") else {
            DLog("No newline found in \(fileURL.path)")
            return nil
        }
        let expectedMagic = magic(key, filePath: fileURL)
        let actualMagic = content.prefix(upTo: newline.lowerBound)
        guard actualMagic == expectedMagic else {
            RLog("In \(fileURL) magic is \(actualMagic) but expected \(expectedMagic)")
            throw SecureUserDefaultError.badMagic
        }
        let payload = content.suffix(from: newline.upperBound)
        DLog("payload=\(payload)")
        return try SecureUserDefaultValue<U>(sudString: String(payload))?.value
    }

    private static func delete(_ key: String) throws {
        RLog("delete \(key)")
        let filename = try path(key, create: false)
        DLog("Remove \(filename)")
        if (FileManager.default.fileExists(atPath: filename.path)) {
            DLog("Item exists, remove it")
            try FileManager.default.removeItem(at: filename)
        }

        NotificationCenter.default.post(name: secureUserDefaultDidChange, object: key)
    }

    private static func store<U: SecureUserDefaultStringTranscodable>(_ key: String, value: U) throws {
        // Keep the value out of the ring (generic path; guard against a future secret-valued key).
        RLog("Store \(redacted: value) to \(key)")
        let statement = try writeStatement(key: key, encodedValue: SecureUserDefaultValue<U>(value: value).encodedString)
        try runPrivilegedWrites(statements: [statement],
                                keys: [key],
                                prompt: "iTerm2 needs to modify a secure setting.")
    }

    /// The double-backslash/double-quote escaping for a path embedded in the
    /// `do shell script "…"` AppleScript string. Shared so store() and
    /// storeBatch() escape identically.
    private static func escapedShellPath(_ url: URL) -> String {
        return url.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\\\\\"")
    }

    /// One shell statement that writes `key`'s value to its root-owned file via a
    /// temp file and an atomic move. On ANY failure it removes the temp file and
    /// `exit 1`s, which aborts the whole `do shell script` so the AppleScript
    /// reports an error: a failed or partial write must not be masked as success
    /// (the old `|| rm -f` form swallowed the error and returned 0).
    private static func writeStatement(key: String, encodedValue: String) throws -> String {
        // Write to a temp file and then move it. If the destination is a link then
        // it's not safe to write to it.
        let unsafeURL = try self.path(key, create: true)
        let path = escapedShellPath(unsafeURL)
        let magic = Self.magic(key, filePath: URL(fileURLWithPath: path))
        // \\n -> printf interprets it as a newline; \\\" -> AppleScript turns it
        // into a literal " for the shell.
        return "TF=$(mktemp); printf '%s\\n%s' '\(magic)' '\(encodedValue)' > \\\"$TF\\\" && chmod a+r \\\"$TF\\\" && mv \\\"$TF\\\" \\\"\(path)\\\" || { rm -f \\\"$TF\\\"; exit 1; }"
    }

    /// Run one or more write statements inside a SINGLE root-privileged
    /// AppleScript (one authorization prompt). Throws if the script reports an
    /// error (any statement's `exit 1`); only on success are the change
    /// notifications posted, one per key.
    private static func runPrivilegedWrites(statements: [String],
                                            keys: [String],
                                            prompt: String) throws {
        let body = (["umask 077"] + statements).joined(separator: "\n")
        let code = "do shell script \"\n\(body)\n\" with prompt \"\(prompt)\" with administrator privileges"
        let script = NSAppleScript(source: code)
        var error: NSDictionary? = nil
        DLog("Will execute \(code)")
        script?.executeAndReturnError(&error)
        DLog("Execution complete. Error is \(error.d)")
        guard error == nil else {
            let maybeReason = error?[NSAppleScript.errorBriefMessage] as? String
            RLog("reason=\(maybeReason.d)")
            throw SecureUserDefaultError.scriptError(maybeReason)
        }
        for key in keys {
            RLog("Success. Post notif for \(key)")
            NotificationCenter.default.post(name: secureUserDefaultDidChange, object: key)
        }
    }
}

extension SecureUserDefault: SerializableUserDefault {
    func setFromSerialized(value: String) {
        DLog("Set from \(value)")
        let decoder = JSONDecoder()
        guard let savedValue = try? decoder.decode(T.self, from: value.data(using: .utf8) ?? Data()) else {
            DLog("Failed to decode \(value)")
            return
        }
        if savedValue != self.value {
            DLog("Value is changed")
            try? set(savedValue)
        } else {
            DLog("Value is unchanged")
        }
    }

    func encode(to dictionary: inout [String: String]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value) else {
            DLog("Failed to encode \(value) as JSON")
            return
        }
        DLog("data=\(data.stringOrHex)")
        if let jsonString = String(data: data, encoding: .utf8) {
            DLog("json=\(jsonString)")
            dictionary[key] = jsonString
        } else {
            DLog("Failed to stringify")
        }
    }
}
