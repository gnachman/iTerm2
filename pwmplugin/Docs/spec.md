# Generic Password Manager CLI

A generic password manager CLI is a command line program that takes a single argument that names a subcommand. Inputs and outputs are JSON documents, which are described in this document as Swift structs since it makes for a nice simple JSON schema. Ignore unrecognized keys in JSON dictionaries (which you happens automatically if you use Swift's Codable).

Inputs are provided on stdin and outputs are provided on stdout. Both are terminated by EOF (i.e., closing the write side of the pipe).

All objects are encoded as JSON using UTF-8.

All subcommands other than Handshake take a RequestHeader, which contains optional information that some CLIs need.

struct RequestHeader: Codable {
    var pathToDatabase: String?  // User-selected database path.
    var pathToExecutable: String?  // Path to backend specific CLI
    var mode: Mode
    enum Mode: String, Codable {
        case terminal
        case browser
    }
}

Passwords for terminal-mode and browser-mode must be kept separate, typically using a feature like tags in the password database. It is nice if browser-mode passwords are the same that are exposed to web browsers using your password manager's browser extension.

# Subcommands

## handshake
This is used so that we can introduce new versions of the protocol in the future and detect a mismatch between iTerm2 version and CLI version. The CLI can respond with an error if it can't complete the protocol version negotiation or the version of iTerm2 is known not to work. This also provides a way to query for capabilities and metadata.

This draft document describes protocol version 0.

 * Input:
```
struct HandshakeRequest {
  var iTermVersion: String  // e.g., "3.5.13".
  var minProtocolVersion: Int  // The lowest acceptable protocol version
  var maxProtocolVersion: Int  // The highest acceptable protocol version
}
```
 * Output:
```
struct HandshakeResponse {
  var protocolVersion: Int  // Gives the version of the protocol you elect to use. Must fall within the version range in the request.
  var name: String  // Gives a descriptive name for the password manager, e.g. "Dashlane".
  var requiresMasterPassword: Bool  // Indicates whether the user should be prompted for a master password which will be sent in LoginRequest.
  var canSetPasswords: Bool  // Indicates whether the set-password API is available.
  var userAccounts: [UserAccount]?  // A list of user accounts available if the password manager supports multiple profiles. Otherwise, omit it.
}

struct UserAccount {
  var name: String // e.g., "Personal"
  var identifier: String  // A unique identifier, like a UUID
  var needsPathToDatabase: Bool  // true if the user must pick the db path and provide it in requests.
  var databaseExtension: String?  // File extension for compatible databases (e.g., "kdbx"), or nil if any file can be selected
  var needsPathToExecutable: String?  // Name of backend executable (e.g., "keepassxc-cli"), or nil if not needed

```

## login
Present authentication UI to the user. For example, request biometric authentication. The CLI is responsible for showing the authentication UI. It can return a token that will be passed to the password manager on future invocations.

 * Input:
```
struct LoginRequest {
  var header: RequestHeader

  var userAccountID: String?  // Will be set if HandshakeResponse.userAccounts was set
  var masterPassword: String?  // Will be set if HandshakeResponse.requiresMasterPassword was true
}
```

 * Outputs
```
struct LoginResponse {
  var token: String?  // You can omit this if you don't need an authentication token passed back in future requests
}
```

## list-accounts
Returns a list of items in the password manager.

 * Input
```
struct ListAccountsRequest {
  var header: RequestHeader

  var userAccountID: String?
  var token: String?
}
```
 * Output:
```
struct ListAccountsResponse {
  var accounts: [Account]
}

// Unique identifier for an item. Typically a UUID or something like that.
struct AccountIdentifier {
  var accountID: String
}

struct Account {
  var identifier: AccountIdentifier
  var userName: String  // e.g., "george"
  var accountName: String // e.g., "My personal Google account"
  var hasOTP: Bool  // If true, iTerm2 will ask for a 2nd factor code before sending the password or use the one provided by the pw manager
}
```

## get-password
Get the plaintext password for an account.
 * Input
```
struct GetPasswordRequest {
  var header: RequestHeader

  var userAccountID: String?
  var token: String?
  var accountIdentifier: AccountIdentifier
}
```

 * Output
```
struct Password {
  var password: String
  var otp: String?  // If the pw mgr supports generating 2fac codes, put it here otherwise omit.
}
```

## set-password
Change the password of an account.
 * Input
```
struct SetPasswordRequest {
  var header: RequestHeader

  var userAccountID: String?
  var token: String?
  var accountIdentifier: AccountIdentifier
  var newPassword: String?
}
```
 * Output
```
struct SetPasswordResponse {
}
```

## delete-account
  * Input:
```
struct DeleteAccountRequest {
  var header: RequestHeader

  var userAccountID: String?
  var token: String?
  var accountIdentifier: AccountIdentifier
}
```
  * Output:
```
struct DeleteAccountResponse {
}
```

## add-account
  * Input:
```
struct AddAccountRequest {
  var header: RequestHeader

  var userAccountID: String?
  var token: String?
  var userName: String
  var accountName: String
  var password: String?  // Will be omitted if HandshakeResponse indicated password setting is not allowed; the password manager should assign a random password in this case (this is how 1password works).
}
```
  * Output:
```
struct AddAccountResponse {
  var accountIdentifier: AccountIdentifier
}
```

# Error Handling

If an error occurs, any command can return an instance of this instead of the documented output JSON document:
```
struct ErrorResponse {
  var error: String
}
```

# Sample usage

```
% echo '{"header": { "pathToDatabase": "/Users/george/passwords.db", "pathToExecutable": "/opt/homebrew/bin/SomePasswordManagerCLI", mode: "terminal" }, "token": "secret goes here", "accountIdentifier": { "accountID": "123-456" } }' | pwmplugin get-password
{ "password": "Hunter2" }
```
