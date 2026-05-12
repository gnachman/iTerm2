import Foundation
import CryptoKit

@objcMembers final class MomentermPasskeyManager: NSObject {
    static let shared = MomentermPasskeyManager()

    // Per-launch unlock state — once unlocked, stays unlocked for the session
    private(set) var isUnlocked: Bool = false

    private let passkeyURL: URL

    private override init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        passkeyURL = home.appendingPathComponent(".momenterm/passkey")
        super.init()
    }

    var isPasskeySet: Bool {
        FileManager.default.fileExists(atPath: passkeyURL.path)
    }

    func verifyAndUnlock(_ input: String) -> Bool {
        guard let stored = try? String(contentsOf: passkeyURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !stored.isEmpty else { return false }
        let hashed = SHA256.hash(data: Data(input.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
        if hashed == stored {
            isUnlocked = true
            return true
        }
        return false
    }

    func setPasskey(_ input: String) {
        let hashed = SHA256.hash(data: Data(input.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
        let dir = passkeyURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? hashed.write(to: passkeyURL, atomically: true, encoding: .utf8)
        isUnlocked = true
    }

    func clearPasskey() {
        try? FileManager.default.removeItem(at: passkeyURL)
        isUnlocked = false
    }

    func markUnlocked() {
        isUnlocked = true
    }
}
