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
        guard let data = (string as NSString).dataFromHexValues() else {
            return nil
        }
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
    lazy var browserBundleID = { SecureUserDefault<String>("BrowserBundleID", defaultValue: "") }()
    lazy var aiCompletionsEnabled = { SecureUserDefault<Bool>("AICompletions", defaultValue: false) }()

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
fileprivate let FallbackFolder = "/usr/local/iTerm2-secure-settings"

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
        DLog("Set \(key) to \((newValue?.sudString).d)")
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
            DLog("Fail: \(error)")
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
        DLog("Reset \(key)")
        cached = nil
        try Self.delete(key)
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
            DLog("Error \(error)")
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

        DLog("Filesystem type of \(path) is \(fsTypeName)")
        let result = nonUnixTypes.contains(fsTypeName)
        secureUserDefaultsFolderIsOnUnixFilesystem = (path, result)
        return result
    }

    private static func baseDirectory(create: Bool) throws -> String {
        DLog("create=\(create)")
        guard let appSupportString = FileManager.default.applicationSupportDirectory() else {
            DLog("Failed to get regular app support directory. Use fallback")
            return try fallbackBaseDirectory(create: create)
        }
        DLog("appSupportString=\(appSupportString)")
        // I have to go directly to user defaults rather than through
        // iTermAdvancedSettingsModel because this is called during
        // iTermAdvancedSettingsModel.initialize, so its values may not be
        // loaded yet.
        let pathsToIgnore = UserDefaults.standard.string(forKey: "PathsToIgnore")?.components(
            separatedBy: ",") ?? []
        DLog("pathsToIgnore=\(pathsToIgnore)")
        let isLocal = FileManager.default.fileIsLocal(
            appSupportString,
            additionalNetworkPaths: pathsToIgnore,
            allowNetworkMounts: false)
        if !isLocal {
            DLog("Not local. Use fallback")
            return try fallbackBaseDirectory(create: create)
        }
        if isOnNonUnixFilesystem(atPath: appSupportString) {
            DLog("Not a unix filesystem. Use fallback")
            return try fallbackBaseDirectory(create: create)
        }
        if ignoresOwnership(atPath: appSupportString) {
            DLog("Ownership ignored. Use fallback")
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
            DLog("Not owned by root. attributes=\(attributes)")
            return nil
        }
        guard let content = try? String(contentsOf: fileURL) else {
            DLog("Cannot read contents of \(fileURL)")
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
            DLog("In \(fileURL) magic is \(actualMagic) but expected \(expectedMagic)")
            throw SecureUserDefaultError.badMagic
        }
        let payload = content.suffix(from: newline.upperBound)
        DLog("payload=\(payload)")
        return try SecureUserDefaultValue<U>(sudString: String(payload))?.value
    }

    private static func delete(_ key: String) throws {
        DLog("delete \(key)")
        let filename = try path(key, create: false)
        DLog("Remove \(filename)")
        try FileManager.default.removeItem(at: filename)

        NotificationCenter.default.post(name: secureUserDefaultDidChange, object: key)
    }

    private static func store<U: SecureUserDefaultStringTranscodable>(_ key: String, value: U) throws {
        DLog("Store \(value) to \(key)")
        // Write to a temp file and then move it. If the destination is a link then it's not safe
        // to write to it.
        let unsafeURL = try self.path(key, create: true)
        let path = unsafeURL.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\\\\\"")
        let magic = Self.magic(key, filePath: URL(fileURLWithPath: path))
        let encodedValue = SecureUserDefaultValue<U>(value: value).encodedString
        let code =
        """
        do shell script "
            umask 077
            TF=$(mktemp)
            printf '%s\\n%s' '\(magic)' '\(encodedValue)' > \\"$TF\\" && \
                chmod a+r \\"$TF\\" && \
                mv \\"$TF\\" \\"\(path)\\" || \
                rm -f \\"$TF\\"
        " with prompt "iTerm2 needs to modify a secure setting." with administrator privileges
        """
        let script = NSAppleScript(source: code)
        var error: NSDictionary? = nil
        DLog("Will execute \(code)")
        script?.executeAndReturnError(&error)
        DLog("Execution complete. Error is \(error.d)")
        guard error == nil else {
            let maybeReason = error?[NSAppleScript.errorBriefMessage] as? String
            DLog("reason=\(maybeReason.d)")
            throw SecureUserDefaultError.scriptError(maybeReason)
        }
        DLog("Success. Post notif for \(key)")
        NotificationCenter.default.post(name: secureUserDefaultDidChange, object: key)
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
