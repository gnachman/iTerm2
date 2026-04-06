# iterm2-keepassxc-adapter

A Swift CLI that wraps `keepassxc-cli` to provide password manager integration for iTerm2.

## Architecture

This project uses Swift Package Manager and is organized into two modules:

- **PasswordManagerProtocol** - Protocol data structures (shared with iTerm2)
  - Located in `Sources/PasswordManagerProtocol/`
  - Can be included directly in iTerm2's Xcode project

- **iterm2-keepassxc-adapter** - CLI implementation specific to KeePassXC
  - Located in `Sources/iterm2-keepassxc-adapter/`
  - Imports and uses PasswordManagerProtocol

## Building

Build for release:
```bash
./build.sh
```

Or build for debugging:
```bash
swift build
```

This creates the executable at `.build/debug/iterm2-keepassxc-adapter` (or `.build/release/iterm2-keepassxc-adapter`)

## Running

You can use the wrapper script which automatically builds if needed:

```bash
./iterm2-keepassxc-adapter <command>
```

Or run the compiled binary directly:

```bash
.build/debug/iterm2-keepassxc-adapter <command>
```

## Usage

Set the database path via environment variable:

```bash
export KEEPASSXC_DATABASE="/path/to/database.kdbx"
```

Then use JSON-based commands:

```bash
echo '{"iTermVersion":"3.5.0","minProtocolVersion":0,"maxProtocolVersion":0}' | ./iterm2-keepassxc-adapter handshake
echo '{"masterPassword":"your-password"}' | ./iterm2-keepassxc-adapter login
```

## Supported Commands

1. **handshake** - Protocol version negotiation
2. **login** - Authenticate with master password
3. **list-accounts** - List all entries in the database
4. **get-password** - Retrieve password for an entry
5. **set-password** - Update password for an entry
6. **add-account** - Create new entry
7. **delete-account** - Delete entry (moves to Recycle Bin)

## Testing

Run all tests through Swift Package Manager:

```bash
swift test
```

Or run the shell script directly:

```bash
./run_all_tests.sh
```

Run individual tests:

```bash
./test_handshake.sh
./test_login.sh
./test_list_accounts.sh
./test_get_password.sh
./test_set_password.sh
./test_add_account.sh
./test_delete_account.sh
./test_integration.sh
```

## Integration with iTerm2

To integrate with iTerm2:

1. Add the **PasswordManagerProtocol** module to the iTerm2 Xcode project
   - Include `Sources/PasswordManagerProtocol/PasswordManagerProtocol.swift`
2. Import and use the protocol structures for JSON encoding/decoding:
   ```swift
   import PasswordManagerProtocol
   ```
3. Call the `iterm2-keepassxc-adapter` executable with appropriate JSON input/output

---

# iterm2-keeper-adapter

A Swift CLI that integrates Keeper Commander Service Mode with iTerm2 password manager support.

## Architecture

This project uses Swift Package Manager and is organized into two modules:

- **PasswordManagerProtocol** - Protocol data structures (shared with iTerm2)
  - Located in `Sources/PasswordManagerProtocol/`
  - Can be included directly in iTerm2's Xcode project

- **iterm2-keeper-adapter** - CLI implementation specific to Keeper Commander
  - Located in `Sources/iterm2-keeper-adapter/`
  - Imports and uses `PasswordManagerProtocol`
  - Handles Keeper Commander API calls and maps responses to protocol types

## Building

Build for release:

```bash
./build.sh
```

Or build for debugging:

```bash
swift build
```

This creates the executable at `.build/debug/iterm2-keeper-adapter` (or `.build/release/iterm2-keeper-adapter`).

## Running

You can use the wrapper script from the repo root:

```bash
./iterm2-keeper-adapter <command>
```

Or run the compiled binary directly:

```bash
.build/debug/iterm2-keeper-adapter <command>
```

## Usage

Keeper uses protocol headers for configuration. For Service Mode, set the Commander base URL in `header.pathToDatabase` (for example `http://127.0.0.1:8900`).

Handshake example:

```bash
echo '{"iTermVersion":"3.5.0","minProtocolVersion":0,"maxProtocolVersion":0}' | ./iterm2-keeper-adapter handshake
```

Login example (API key is passed in `masterPassword` and returned as a token):

```bash
echo '{"header":{"pathToDatabase":"http://127.0.0.1:8900","pathToExecutable":null,"mode":"terminal"},"userAccountID":null,"masterPassword":"YOUR_KEEPER_API_KEY"}' | ./iterm2-keeper-adapter login
```

## Supported Commands

1. **handshake** - Protocol version negotiation
2. **login** - Authenticate with Keeper API key
3. **list-accounts** - List Keeper records (`userName` comes from `ls` data: optional JSON `login`/`username`, else the description column — no per-record `get`, to avoid rate limits)
4. **get-password** - Get password for a record
5. **set-password** - Update password for a record
6. **add-account** - Create a new record
7. **delete-account** - Delete a record
8. **sync-down** (custom command) - Trigger Keeper `sync-down`

## Testing

Run Swift package tests:

```bash
swift test
```

Run Keeper adapter tests only:

```bash
swift test --filter KeeperIntegrationTests
```

From the iTerm2 repo root, run app-side Keeper wiring tests:

```bash
tools/run_tests.expect ModernTests/KeeperDataSourceTests
```

Optionally run the Keeper coverage helper:

```bash
tests/run_keeper_coverage.sh
```

## Integration with iTerm2

To integrate with iTerm2:

1. Add the **PasswordManagerProtocol** module to the iTerm2 Xcode project
   - Include `Sources/PasswordManagerProtocol/PasswordManagerProtocol.swift`
2. Import and use protocol structures for JSON encoding/decoding:
   ```swift
   import PasswordManagerProtocol
   ```
3. Bundle and invoke `iterm2-keeper-adapter` from iTerm2 adapter data source code

The protocol structures are shared between the CLI and iTerm2, ensuring type safety and compatibility.
