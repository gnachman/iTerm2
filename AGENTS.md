# iTerm2 Agent Guide

> Comprehensive guide for AI agents working on iTerm2, a feature-rich terminal emulator for macOS.

## Quick Reference

### Common Tasks
- **Find session logic**: `sources/PTYSession.{h,m}`, `sources/PseudoTerminal.{h,m}`
- **Terminal emulation**: `sources/VT100Screen.{h,m}`, `sources/VT100Terminal.{h,m}`
- **UI rendering**: `sources/PTYTextView.{h,m}`, `sources/SessionView.{h,m}`
- **Chat/AI features**: `sources/Chat*.swift`, `sources/AI*.swift`
- **Preferences**: `sources/PreferencePanel.*`, `sources/*PreferencesViewController.*`
- **API definitions**: `proto/api.proto` (Protobuf), `iTerm2.sdef` (AppleScript)
- **Tests**: `tests/iTerm2XCTests/`

### Critical Rules (from CLAUDE.md)
1. ⚠️ **Never** write >1 line of JavaScript/HTML/CSS inline in Swift/Objective-C
2. ⚠️ Use `it_fatalError` and `it_assert` (not `fatalError`/`assert`) for proper crash logs
3. ⚠️ **Never** create dependency cycles - use delegates/closures instead
4. ⚠️ `git add` new files immediately after creation
5. ⚠️ Load complex web content via `iTermBrowserTemplateLoader.swift`

## Project Overview

**iTerm2** is a mature macOS terminal emulator with:
- **~1,974 source files**: 1,595 Objective-C (.m/.h), 379 Swift (.swift)
- **Hybrid architecture**: Core system in Objective-C, modern features in Swift
- **Rich feature set**: Tmux integration, AI assistance, chat, profiles, scripting
- **Target**: macOS 12+ (with feature gates for 14+)
- **Build system**: Xcode with Swift Package Manager for frameworks

## Architecture Overview

### Core Layers

```
┌─────────────────────────────────────────────────────────────────┐
│ Application Layer                                               │
│ • iTermApplication, iTermApplicationDelegate                    │
│ • iTermController (main coordinator, AppDelegate)               │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Window/Tab Management                                           │
│ • PseudoTerminal (window controller)                            │
│ • PTYWindow (custom NSWindow)                                   │
│ • PTYTab (tab management + scripting)                           │
│ • PSMTabBarControl (tab bar UI)                                 │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Session Layer                                                   │
│ • PTYSession (core session model - lifecycle, I/O, state)       │
│ • iTermSessionFactory (session creation)                        │
│ • iTermSessionLauncher (session initialization)                 │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Terminal Emulation                                              │
│ • VT100Screen (state machine, escape sequences)                 │
│ • VT100Terminal (parser)                                        │
│ • VT100Grid (grid data structure)                               │
│ • LineBuffer (scrollback)                                       │
│ • PTYTask (process I/O)                                         │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ View/Rendering Layer                                            │
│ • PTYTextView (main terminal view, Metal rendering)             │
│ • SessionView (container view)                                  │
│ • iTermRootTerminalView (split pane management)                 │
│ • PTYScrollView (custom scrolling)                              │
└─────────────────────────────────────────────────────────────────┘
```

### Feature Modules

#### AI/Chat System (Swift)
- **ChatViewController.swift** (80K lines) - Main chat UI
- **ChatAgent.swift** - AI agent logic
- **ChatService.swift** - Service coordinator
- **ChatDatabase.swift** - Persistence layer
- **AITerm.swift** (40K lines) - Terminal AI integration
- **AICompletion.swift** - Command completion
- **AIMetadata.swift** - Model/provider metadata

#### Plugin/Extension System
- **WebExtensionsFramework/** - Browser WebExtensions API (Swift SPM)
- **iTermBrowserPlugin/** - Browser integration
- **Protocol Buffers** - WebSocket API (`proto/api.proto`)

#### Other Key Features
- **Tmux integration**: TmuxController, TmuxGateway
- **Profiles**: ProfileModel, ITAddressBookMgr
- **Triggers**: Alert/Bounce/Highlight/MuteCoprocessTrigger, etc.
- **Shell integration**: OtherResources/shell_integration/

## Directory Structure

```
iTerm2/
├── sources/                    # Main application code (1,974 files)
│   ├── PTY*.{h,m}             # Session management
│   ├── VT100*.{h,m}           # Terminal emulation
│   ├── Chat*.swift            # Chat features
│   ├── AI*.swift              # AI features
│   ├── iTermController.m      # Main app coordinator
│   ├── PseudoTerminal.{h,m}   # Window controller
│   └── *PreferencesViewController.* # Preferences UI
│
├── Interfaces/                 # XIB/Storyboard files (38 files)
│   ├── *.xib                  # Interface Builder files
│   └── *.storyboard           # Storyboards
│
├── tests/
│   ├── iTerm2XCTests/         # Unit tests (45+ test files)
│   │   ├── VT100ScreenTest.m  # Terminal emulation tests (180K)
│   │   ├── PTYTextViewTest.m  # View tests (119K)
│   │   └── SearchEngineTests.swift
│   └── ModernTests/           # Modern test suite
│
├── proto/
│   └── api.proto              # Protocol Buffer API definitions
│
├── tools/                      # Build scripts
│   ├── build_proto.sh         # Protobuf compilation
│   ├── build_terminfo.sh      # Terminal info generation
│   └── *.py                   # Python build utilities
│
├── submodules/                 # 18 Git submodules
│   ├── Sparkle/               # Auto-update framework
│   ├── libssh2/               # SSH support
│   ├── NMSSH/                 # SSH client
│   ├── openssl/               # Crypto
│   └── ...
│
├── WebExtensionsFramework/    # Swift SPM framework
│   ├── Sources/               # Framework sources
│   ├── Tests/                 # TDD tests
│   └── CLAUDE.md              # Framework-specific guidelines
│
├── iTermAI/                    # AI integration framework
├── Model.xcdatamodeld/         # Core Data models
├── OtherResources/             # Resources, scripts, utilities
├── iTerm2.sdef                 # AppleScript definitions
├── iTerm2.entitlements         # App sandboxing
├── CLAUDE.md                   # Code best practices (CRITICAL)
└── iTerm2.xcodeproj/           # Xcode project
```

## Technology Stack

### Languages & Frameworks
- **Objective-C** (~1,595 files): Core system, terminal emulation, legacy UI
- **Swift** (~379 files): Modern features, chat, AI, new UI components
- **AppKit**: macOS UI framework
- **Core Data**: Profile and chat storage
- **Metal**: GPU-accelerated rendering
- **Protocol Buffers**: API serialization
- **XCTest**: Unit testing

### Key Dependencies (Submodules)
- **Sparkle**: Software updates
- **libssh2, NMSSH**: SSH protocol
- **openssl**: Cryptography
- **libgit2**: Git integration
- **fmdb**: SQLite wrapper
- **Highlightr**: Syntax highlighting
- **SwiftyMarkdown**: Markdown parsing
- **MultiCursor**: Multi-cursor editing
- **adblock-rust**: Ad blocking

### Build Tools
- **Xcode**: Primary IDE and build system
- **Swift Package Manager**: WebExtensionsFramework
- **Python**: Build automation (basechars.py, emoji.py, etc.)
- **Bash**: Build scripts in tools/

## Development Workflows

### Creating a New Feature

1. **Plan the change**
   - Identify affected layers (session, terminal, UI, etc.)
   - Check for existing patterns in similar features
   - Consider Objective-C vs Swift (prefer Swift for new code)

2. **Implement**
   - Follow CLAUDE.md rules strictly
   - Use delegates/closures to avoid dependency cycles
   - External files for any non-trivial JS/HTML/CSS
   - Use `it_fatalError`/`it_assert` for error handling

3. **Test**
   - Add tests to `tests/iTerm2XCTests/`
   - Follow TDD practices (see WebExtensionsFramework)
   - Test both Objective-C and Swift interfaces

4. **Commit**
   - `git add` new files immediately
   - Follow existing commit message conventions

### Modifying Terminal Emulation

Key files to understand:
- `VT100Screen.{h,m}` - Terminal state machine (core logic)
- `VT100Terminal.{h,m}` - Escape sequence parser
- `VT100Grid.{h,m}` - Grid data structure
- `LineBuffer.{h,m}` - Scrollback buffer

**Workflow:**
1. Read VT100ScreenTest.m (180K lines) for examples
2. Understand escape sequence flow: Terminal → Screen → Grid
3. Add new sequences in VT100Terminal parser
4. Update VT100Screen state handling
5. Test extensively with VT100ScreenTest

### Adding UI Components

1. **XIB-based UI** (Objective-C):
   - Create .xib in Interfaces/
   - Create controller in sources/
   - Wire outlets/actions in Interface Builder

2. **Programmatic UI** (Swift):
   - Create view controller in sources/
   - Use Auto Layout constraints
   - Follow existing patterns in Chat*.swift files

3. **Web-based UI**:
   - Create HTML/CSS/JS files (never inline!)
   - Use `iTermBrowserTemplateLoader.swift` to load
   - See existing templates for examples

### Working with Chat/AI Features

**Key entry points:**
- `ChatViewController.swift` - Main UI (80K lines)
- `ChatService.swift` - Service coordinator
- `AITermController.swift` - Terminal integration

**Pattern:**
1. Chat UI sends commands via ChatService
2. ChatService coordinates with ChatAgent
3. ChatAgent processes AI logic
4. Results flow back through ChatService to UI

**Database:**
- ChatDatabase.swift handles persistence
- Core Data model in Model.xcdatamodeld/

### Extending the API

#### WebSocket API (Protobuf)
1. Edit `proto/api.proto`
2. Run `tools/build_proto.sh` to regenerate
3. Implement handlers in relevant controllers
4. Add tests

#### AppleScript
1. Edit `iTerm2.sdef`
2. Implement methods in `*+Scripting.{h,m}` files
3. Test with Script Editor

## Code Patterns & Best Practices

### Objective-C Patterns

```objc
// ✅ Good: Delegate pattern to avoid cycles
@protocol MyDelegate <NSObject>
- (void)didCompleteOperation:(id)result;
@end

@interface MyClass : NSObject
@property (nonatomic, weak) id<MyDelegate> delegate;
@end

// ✅ Good: Custom error handling
if (error) {
    it_fatalError(@"Operation failed: %@", error);
}

// ❌ Bad: Standard error handling
if (error) {
    fatalError("Operation failed");  // Won't generate useful crash logs
}

// ✅ Good: External template
NSString *html = [iTermBrowserTemplateLoader loadTemplateNamed:@"chat"];

// ❌ Bad: Inline HTML
NSString *html = @"<html><body>...</body></html>";  // Too long!
```

### Swift Patterns

```swift
// ✅ Good: Protocol-based dependency injection
protocol ChatServiceProtocol {
    func sendMessage(_ message: String) async throws -> Response
}

class ChatViewController {
    private let service: ChatServiceProtocol
    init(service: ChatServiceProtocol) {
        self.service = service
    }
}

// ✅ Good: Async/await (no completion handlers)
func fetchData() async throws -> Data {
    let response = try await networkClient.fetch()
    return response.data
}

// ✅ Good: Actor for thread safety
actor ChatDatabase {
    private var cache: [String: Message] = [:]

    func store(_ message: Message) {
        cache[message.id] = message
    }
}

// ❌ Bad: Dependency cycle
class A {
    var b: B?  // Strong reference
}
class B {
    var a: A?  // Strong reference - cycle!
}

// ✅ Good: Break with weak/closure
class A {
    var b: B?
}
class B {
    weak var a: A?  // Weak reference
}
```

### WebExtensionsFramework Patterns (TDD)

Per `WebExtensionsFramework/CLAUDE.md`:

```swift
// ✅ Good: TDD workflow
// 1. Write test first
func testFetchesManifest() async throws {
    let mock = MockBrowser()
    let loader = ManifestLoader(browser: mock)

    let manifest = try await loader.load()

    XCTAssertEqual(manifest.version, "1.0")
}

// 2. Implement minimal code to pass
// 3. Refactor

// ✅ Good: No Task.sleep in tests
// ❌ Bad: await Task.sleep(...)

// ✅ Good: No default parameters in test functions
func testWithValue(value: Int) { ... }

// ❌ Bad: default parameters
func testWithValue(value: Int = 42) { ... }

// ✅ Good: Explicit async/await
func testAsync() async throws {
    let result = try await operation()
    XCTAssertNotNil(result)
}
```

## Testing Strategy

### Test Files (45+ in iTerm2XCTests/)
- **VT100ScreenTest.m** (180K) - Comprehensive terminal emulation tests
- **PTYTextViewTest.m** (119K) - View rendering tests
- **iTermCodingTests.m** (71K) - Serialization tests
- **SemanticHistoryTest.m** (77K) - Semantic history tests
- **SearchEngineTests.swift** - Search functionality
- **VT100GridTest.m** - Grid data structure tests

### Testing Approach

1. **Unit Tests**: Test individual classes in isolation
2. **Integration Tests**: Test component interactions
3. **Mock heavy dependencies**: Use protocols for testability
4. **TDD for new Swift code**: Test-first development
5. **Async testing**: Use async/await, avoid Task.sleep

### Running Tests

```bash
# From Xcode
# Cmd+U to run all tests
# Cmd+Ctrl+Alt+U to run tests without building

# From command line
xcodebuild test -project iTerm2.xcodeproj -scheme iTerm2

# Run specific test
xcodebuild test -project iTerm2.xcodeproj -scheme iTerm2 \
    -only-testing:iTerm2XCTests/VT100ScreenTest/testBasicScrolling
```

## API Surface

### Protocol Buffer API (proto/api.proto)

100+ message types for WebSocket communication:

**Session Management:**
- `ListSessionsRequest/Response`
- `CreateTabRequest/Response`
- `SplitPaneRequest/Response`
- `CloseRequest/Response`

**Content Access:**
- `GetBufferRequest/Response`
- `GetPromptRequest/Response`
- `GetScreenContentsRequest/Response`

**Configuration:**
- `SetProfilePropertyRequest/Response`
- `GetProfilePropertyRequest/Response`
- `SetPropertyRequest/Response`

**Tmux:**
- `TmuxRequest/Response`

**Functions:**
- `InvokeFunctionRequest/Response`
- `RegisterToolRequest/Response`

**Usage:**
```objc
// Objective-C (generated with ITM prefix)
ITMListSessionsRequest *request = [[ITMListSessionsRequest alloc] init];
// Send via WebSocket...
```

### AppleScript API (iTerm2.sdef)

Full scripting interface exposed via AppleScript:

**Examples:**
```applescript
tell application "iTerm2"
    create window with default profile
    tell current session of current window
        write text "echo Hello"
    end tell
end tell
```

**Implementation:**
- Scripting support in `*+Scripting.{h,m}` files
- PTYTab+Scripting, PTYSession+Scripting, etc.

## Build System

### Xcode Configuration
- **Project file**: `iTerm2.xcodeproj/project.pbxproj`
- **Object version**: 70 (modern Xcode)
- **Build system**: New Build System (default)
- **Deployment target**: macOS 12.0+
- **Swift version**: 5.x

### Product Types
- Main Application: iTerm2.app
- Static Libraries: Various internal libraries
- XPC Services: Helper services
- Command-line Tools: Utilities
- Unit Test Bundles: Test targets
- Frameworks: WebExtensionsFramework

### Build Scripts (tools/)

```bash
# Protocol buffer generation
./tools/build_proto.sh

# Terminal info generation
./tools/build_terminfo.sh

# Shell integration setup
./tools/copy_shell_integration.sh

# MIME types generation
swift ./tools/build_mimetypes.swift
```

### Entitlements
- **iTerm2.entitlements**: Main app sandboxing, network access, etc.
- **iTermFileProviderNightly.entitlements**: File provider permissions

## Common Pitfalls & Gotchas

### 1. Dependency Cycles 🔴
**Problem:** Swift/ObjC retain cycles causing memory leaks

**Solution:** Always use `weak` or `unowned` for back-references
```swift
// ❌ Bad
class Parent {
    var child: Child?
}
class Child {
    var parent: Parent?  // Cycle!
}

// ✅ Good
class Child {
    weak var parent: Parent?
}
```

### 2. Inline Web Content 🔴
**Problem:** Hard to maintain, violates CLAUDE.md

**Solution:** External files + template loader
```swift
// ❌ Bad
let html = """
<html>
<head><style>body { color: blue; }</style></head>
<body>...</body>
</html>
"""

// ✅ Good
let html = iTermBrowserTemplateLoader.load("my-template")
// my-template.html contains the full HTML
```

### 3. Error Handling 🔴
**Problem:** Using standard fatalError/assert doesn't create crash logs

**Solution:** Always use iTerm2's versions
```swift
// ❌ Bad
assert(value != nil, "Value must not be nil")
fatalError("Unexpected state")

// ✅ Good
it_assert(value != nil, "Value must not be nil")
it_fatalError("Unexpected state")
```

### 4. Forgetting git add 🟡
**Problem:** New files not tracked in git

**Solution:** Immediately after creating a file
```bash
# Create file
# Immediately:
git add path/to/new/file.swift
```

### 5. Threading Issues 🟡
**Problem:** UI updates on background threads, race conditions

**Solution:**
```swift
// ✅ Main thread UI updates
DispatchQueue.main.async {
    self.label.text = "Updated"
}

// ✅ Actor isolation for shared state
actor DataStore {
    private var items: [Item] = []
    func add(_ item: Item) { items.append(item) }
}
```

### 6. Objective-C/Swift Bridging 🟡
**Problem:** Name collisions, visibility issues

**Solution:**
- Use `@objc` attributes explicitly
- Check `-Swift.h` bridging header
- Use `NS_SWIFT_NAME` for better names

```swift
// Swift
@objc(ITMChatService)
class ChatService: NSObject {
    @objc func sendMessage(_ message: String) { }
}

// Objective-C can now use ITMChatService
```

### 7. Test Flakiness 🟡
**Problem:** Tests failing intermittently due to timing

**Solution:**
- Never use `Task.sleep` or `Thread.sleep` in tests
- Use proper async/await patterns
- Mock time-dependent operations

### 8. Submodule Updates 🟡
**Problem:** Submodules out of sync causing build failures

**Solution:**
```bash
git submodule update --init --recursive
```

## Notifications & Events

### Key Notifications (NSNotification)

```objc
// Session lifecycle
PTYSessionCreatedNotification
PTYSessionTerminatedNotification
PTYCommandDidExitNotification

// Window/tab events
PseudoTerminalStateDidChange
PTYTabDidChangeToState

// Profile changes
kReloadAddressBookNotification

// Subscribe example:
[[NSNotificationCenter defaultCenter]
    addObserver:self
       selector:@selector(sessionCreated:)
           name:PTYSessionCreatedNotification
         object:nil];
```

## Performance Considerations

### Metal Rendering
- PTYTextView uses Metal for hardware-accelerated rendering
- Fallback to Core Graphics for compatibility
- Batch operations when possible

### Large Buffers
- LineBuffer is optimized for scrollback
- VT100Grid uses compact character storage
- Lazy rendering of off-screen content

### Memory Management
- PTYSession lifecycle carefully managed
- Buried sessions for background processes
- Profile caching in ITAddressBookMgr

## Integration Points

### Shell Integration
- Scripts in `OtherResources/shell_integration/`
- Bash, Zsh, Fish, Tcsh support
- Provides: command tracking, directory detection, prompt markers

### Tmux Integration
- TmuxController manages tmux gateway
- Protocol translation: tmux ↔ iTerm2
- Window/pane mapping

### Git Integration
- libgit2 submodule for Git operations
- Used for repository status, diffs
- Integrated into file browser features

## Security Considerations

### Sandboxing
- App sandbox enabled (iTerm2.entitlements)
- Network client/server entitlements
- File access scoped appropriately

### Input Validation
- Escape sequence parsing carefully bounds-checked
- API input validation in Protocol Buffer handlers
- User input sanitization in chat/AI features

### Credentials
- Secure storage via Keychain
- SSH key management through NMSSH
- No hardcoded secrets

## Debugging Tips

### Xcode Breakpoints
```
# Break on iTerm2 assertions
it_fatalError
it_assert

# Break on session events
-[PTYSession initWithProfile:]
-[PTYSession terminate]

# Break on terminal state changes
-[VT100Screen setTerminalOutput:]
```

### Logging
```objc
// Use DLog macros (compile-time debug logs)
DLog(@"Session created: %@", session);

// ITerm2 logging system
[iTermAdvancedSettingsModel logLevel];  // Check current level
```

### Common Issues
1. **Blank screen**: Check Metal rendering fallback
2. **Garbled output**: VT100 escape sequence parsing
3. **Memory leaks**: Check retain cycles with Instruments
4. **Crash on exit**: Session cleanup in PTYSession terminate

## Resources

### Documentation Files
- `CLAUDE.md` - Core development rules (READ FIRST)
- `WebExtensionsFramework/CLAUDE.md` - Framework-specific guidelines
- `sources/ai-prompt-help.md` - AI feature documentation
- `iTerm2.sdef` - AppleScript API reference
- `proto/api.proto` - Protocol Buffer API definitions

### External Documentation
- [iTerm2 Website](https://iterm2.com)
- [Python API Docs](https://iterm2.com/python-api/)
- [Tmux Integration Guide](https://gitlab.com/gnachman/iterm2/-/wikis/tmux-Integration-Best-Practices)

### Code Size Reference
- VT100ScreenTest.m: 180K lines (terminal emulation tests)
- PTYTextViewTest.m: 119K lines (view tests)
- ChatViewController.swift: 80K lines (chat UI)
- iTermCodingTests.m: 71K lines (serialization)
- SemanticHistoryTest.m: 77K lines (semantic history)
- AITerm.swift: 40K lines (AI integration)

---

## Quick Decision Trees

### "Should I use Objective-C or Swift?"
- **Objective-C**: Modifying existing ObjC code, deep AppKit integration
- **Swift**: New features, chat/AI, modern UI, better type safety
- **Bridge**: Use `@objc` when Swift needs to interop with ObjC

### "Where should this code go?"
- **Session logic** → `PTYSession.{h,m}`
- **Terminal emulation** → `VT100Screen.{h,m}`, `VT100Terminal.{h,m}`
- **UI rendering** → `PTYTextView.{h,m}`, `SessionView.{h,m}`
- **Chat/AI** → `Chat*.swift`, `AI*.swift`
- **Window management** → `PseudoTerminal.{h,m}`, `PTYWindow.{h,m}`
- **Preferences** → `*PreferencesViewController.*`
- **API** → Protocol handlers for proto/api.proto messages
- **Utilities** → Category files with `+iTerm` suffix

### "How do I add a new escape sequence?"
1. Add token to VT100Terminal parser
2. Handle in VT100Screen state machine
3. Update VT100Grid if needed
4. Add test case in VT100ScreenTest.m
5. Document behavior

### "How do I expose functionality to scripts?"
**AppleScript:**
1. Add to iTerm2.sdef
2. Implement in `*+Scripting.{h,m}`
3. Test in Script Editor

**WebSocket API:**
1. Add message to proto/api.proto
2. Run tools/build_proto.sh
3. Implement handler
4. Add to API documentation

## Architectural Decisions

### Why Objective-C + Swift Hybrid?
- **Legacy**: Core system predates Swift
- **Performance**: ObjC has less overhead for terminal emulation hot paths
- **Modern features**: Swift for new functionality (chat, AI)
- **Safety**: Swift's type system for complex logic
- **Transition**: Gradual modernization without rewrite

### Why Protocol Buffers?
- **Efficiency**: Compact binary serialization
- **Versioning**: Forward/backward compatibility
- **Cross-language**: Python API uses same definitions
- **Type safety**: Generated code with type checking

### Why Metal Rendering?
- **Performance**: GPU acceleration for smooth scrolling
- **Efficiency**: Reduced CPU usage
- **Quality**: Better anti-aliasing and text rendering
- **Fallback**: Core Graphics for compatibility

---

## Agent Workflow Checklist

Before starting work:
- [ ] Read CLAUDE.md rules
- [ ] Understand which layer you're modifying
- [ ] Check for existing patterns in similar code
- [ ] Plan approach to avoid dependency cycles

While coding:
- [ ] External files for any HTML/CSS/JS >1 line
- [ ] Use it_fatalError/it_assert exclusively
- [ ] git add new files immediately
- [ ] Follow existing naming conventions
- [ ] Add tests as you go

Before committing:
- [ ] Tests pass (Cmd+U in Xcode)
- [ ] No new warnings
- [ ] Code follows project patterns
- [ ] Documentation updated if needed
- [ ] No dependency cycles introduced

---

**Last updated**: 2025-12-01
**Project version**: iTerm2 v3.x (master branch)
**For questions**: Check documentation or existing code patterns first
