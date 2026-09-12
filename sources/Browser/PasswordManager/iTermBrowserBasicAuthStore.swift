//
//  iTermBrowserBasicAuthStore.swift
//  iTerm2
//
//  Remembers HTTP basic-authentication credentials for the built-in browser by storing
//  them as ordinary entries in the browser password manager
//  (PasswordManagerDataSourceProvider.forBrowser). That means remembered credentials
//  live wherever the user has pointed their browser password manager - the keychain,
//  1Password, LastPass, KeePassXC, Bitwarden, or Keeper - and are viewed and removed in
//  the same password manager UI as everything else, rather than in a private store.
//
//  An entry's accountName encodes the protection space (host, plus realm when present)
//  and its userName/password are the credential. Silent auto-fill only happens when the
//  password manager can be read WITHOUT an interactive auth prompt (auth-on-open is off,
//  or it's already unlocked this session); saving a new credential may prompt, which is
//  acceptable because the user just clicked OK. /dev/null sessions never remember, since
//  the shared password manager would outlive the tab.
//
//  The challenge decision (auto-try vs prompt) and the accountName derivation are pure
//  functions so they can be unit tested without the password-manager stack.
//

import Foundation

@MainActor
class iTermBrowserBasicAuthStore {
    struct Credential: Equatable {
        var user: String
        var password: String
    }

    private let user: iTermBrowserUser

    init(user: iTermBrowserUser) {
        self.user = user
    }

    // Remembering is disabled for /dev/null: the shared browser password manager would
    // persist a credential beyond the ephemeral session's lifetime.
    var canRemember: Bool {
        switch user {
        case .regular:
            return true
        case .devNull:
            return false
        }
    }

    // Wrap a completion so it always runs on the main thread. Returns immediately if already on
    // main (preserving synchronous delivery for the fast unlocked path), otherwise hops.
    private nonisolated static func onMain<T>(_ completion: @escaping (T) -> Void) -> (T) -> Void {
        return { value in
            if Thread.isMainThread {
                completion(value)
            } else {
                DispatchQueue.main.async { completion(value) }
            }
        }
    }

    // MARK: - Pure logic (unit tested)

    // The password-manager account name for a protection space, and the key we match/save
    // by. A protection space is (scheme, host, port, realm), so all four must be encoded or
    // two distinct servers can collide and overwrite each other's credential (e.g. https
    // vs http on the same host, or two ports of an intranet host). The scheme is always
    // included so http and https never collide; the port is shown only when non-default so
    // the common case reads cleanly. This string is also what the user sees in the password
    // manager list.
    nonisolated static func accountName(scheme: String, host: String, port: Int, realm: String) -> String {
        let isDefaultPort = (scheme == "https" && port == 443) || (scheme == "http" && port == 80)
        let origin = isDefaultPort ? "\(scheme)://\(host)" : "\(scheme)://\(host):\(port)"
        if realm.isEmpty {
            return origin
        }
        return "\(origin) (\(realm))"
    }

    // MARK: - Password manager access

    private var provider: PasswordManagerDataSourceProvider { .forBrowser }

    // True when the password manager can be read without showing an interactive auth
    // prompt: either it's already unlocked this session, or authentication isn't required
    // to open it.
    var isUnlockedWithoutPrompt: Bool {
        provider.authenticated || !SecureUserDefaults.instance.requireAuthToOpenPasswordmanager.value
    }

    // Look up a remembered credential without prompting. Calls completion(nil) if
    // remembering is disabled, the store is locked, nothing matches, or on error. When more
    // than one credential is saved for the same protection space (different usernames),
    // `preferredUser` (the server's proposed user, if any) is used to disambiguate before
    // falling back to the first match.
    func lookup(scheme: String,
                host: String,
                port: Int,
                realm: String,
                preferredUser: String?,
                window: NSWindow?,
                completion rawCompletion: @escaping (Credential?) -> Void) {
        // The password-manager backend (CLI-backed adapters in particular) may deliver its
        // fetchAccounts / fetchPassword callbacks off the main thread. This store is @MainActor,
        // so honor that contract by funneling every completion back onto the main thread instead
        // of leaking the backend's queue to the caller.
        let completion = Self.onMain(rawCompletion)
        guard canRemember, isUnlockedWithoutPrompt else {
            completion(nil)
            return
        }
        // Safe: isUnlockedWithoutPrompt guarantees this won't show a prompt (it either
        // no-ops because already authenticated, or unlocks silently when auth isn't
        // required).
        provider.requestAuthenticationIfNeeded { [weak self] authenticated in
            guard let self, authenticated, let dataSource = self.provider.dataSource else {
                completion(nil)
                return
            }
            let wanted = Self.accountName(scheme: scheme, host: host, port: port, realm: realm)
            let context = RecipeExecutionContext(window: window)
            dataSource.fetchAccounts(context: context) { accounts in
                let matches = accounts.filter { $0.accountName == wanted }
                guard !matches.isEmpty else {
                    completion(nil)
                    return
                }
                let account: PasswordManagerAccount
                if let preferredUser, !preferredUser.isEmpty,
                   let match = matches.first(where: { $0.userName == preferredUser }) {
                    account = match
                } else {
                    account = matches[0]
                }
                account.fetchPassword(context: context) { password, _, _ in
                    if let password {
                        completion(Credential(user: account.userName, password: password))
                    } else {
                        completion(nil)
                    }
                }
            }
        }
    }

    // Save (or update) a remembered credential. May prompt for authentication, which is
    // acceptable because the user explicitly asked to remember it. `completion(false)` means
    // the credential was NOT persisted - the store couldn't be authenticated/opened, or the
    // backend write failed - so the caller can tell the user rather than silently losing
    // their "Remember this password" intent.
    func save(_ credential: Credential,
              scheme: String,
              host: String,
              port: Int,
              realm: String,
              window: NSWindow?,
              completion rawCompletion: @escaping (Bool) -> Void) {
        // See lookup(): the backend may complete off the main thread; keep the @MainActor
        // contract by hopping back before calling the caller's completion.
        let completion = Self.onMain(rawCompletion)
        guard canRemember else {
            completion(false)
            return
        }
        provider.requestAuthenticationIfNeeded { [weak self] authenticated in
            guard let self, authenticated, let dataSource = self.provider.dataSource else {
                completion(false)
                return
            }
            let name = Self.accountName(scheme: scheme, host: host, port: port, realm: realm)
            let context = RecipeExecutionContext(window: window)
            dataSource.fetchAccounts(context: context) { accounts in
                if let existing = accounts.first(where: {
                    $0.accountName == name && $0.userName == credential.user
                }) {
                    existing.set(context: context, password: credential.password) { error in
                        completion(error == nil)
                    }
                } else {
                    dataSource.add(userName: credential.user,
                                   accountName: name,
                                   password: credential.password,
                                   flags: [:],
                                   context: context) { account, error in
                        completion(account != nil && error == nil)
                    }
                }
            }
        }
    }
}
