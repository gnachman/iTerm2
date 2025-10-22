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

The protocol structures are shared between the CLI and iTerm2, ensuring type safety and compatibility.
