# iTerm2 Agent Guide

> Essential guide for AI agents working on iTerm2.

## Critical Rules

**Read `CLAUDE.md` first** - it contains mandatory coding practices. Key rules:

1. **Never** write >1 line of JavaScript/HTML/CSS inline - use external files with `iTermBrowserTemplateLoader.swift`
2. Use `it_fatalError` and `it_assert` (not standard `fatalError`/`assert`) for proper crash logs
3. **Never** create dependency cycles - use delegates/closures instead
4. `git add` new files immediately after creation

## Architecture

**iTerm2** uses hybrid Objective-C/Swift: core system in Objective-C, modern features in Swift.

**Application Flow:** App → Window/Tab → Session → Terminal Emulation → Rendering

### Key Components

- **Application:** `iTermController` - Main coordinator
- **Window/Tab:** `PseudoTerminal`, `PTYTab` - Window and tab management
- **Session:** `PTYSession` - Session lifecycle, I/O, state
- **Terminal Emulation:** `VT100Parser`, `VT100Terminal`, `VT100ScreenMutableState`, `VT100Screen`, `VT100Grid`
- **Rendering:** `PTYTextView` - Metal-accelerated rendering

## Directory Structure

```
iTerm2/
├── sources/               # Main application code
├── tests/iTerm2XCTests/   # Unit tests
├── proto/api.proto        # Protocol Buffer API
├── tools/                 # Build scripts
├── submodules/            # Git submodules
├── WebExtensionsFramework/  # Swift SPM framework (see WebExtensionsFramework/CLAUDE.md)
├── iTerm2.sdef            # AppleScript API
├── CLAUDE.md              # Code best practices
└── iTerm2.xcodeproj/      # Xcode project
```

## Common Development Tasks

### Modifying Terminal Emulation
- Escape sequences flow: `VT100Parser`/`VT100Terminal` → `VT100ScreenMutableState`/`VT100Screen` → `VT100Grid`
- Look at `VT100ScreenTest.m` for examples
- Test changes thoroughly

### Extending APIs
- **WebSocket API:** Edit `proto/api.proto`, run `tools/build_proto.sh`
- **AppleScript:** Edit `iTerm2.sdef`, implement in `*+Scripting.{h,m}` files

## Code Patterns

### Avoiding Dependency Cycles
```swift
// ❌ Bad: Strong reference cycle
class Parent { var child: Child? }
class Child { var parent: Parent? }

// ✅ Good: Use weak reference
class Child { weak var parent: Parent? }
```

### Using External Templates
```objc
// ✅ Good
NSString *html = [iTermBrowserTemplateLoader loadTemplateNamed:@"chat"];

// ❌ Bad: Inline HTML
NSString *html = @"<html><body>...</body></html>";
```

### Error Handling
```swift
// ✅ Good
it_fatalError("Unexpected state")
it_assert(value != nil, "Value required")

// ❌ Bad: Won't create crash logs
fatalError("Unexpected state")
assert(value != nil)
```

## Finding Your Way

**Language choice:**
- Use Objective-C when modifying existing Objective-C code
- Use Swift for new features
- Use `@objc` attributes for Swift/Objective-C interop

**Where code lives:**
- Session logic → `PTYSession.{h,m}`
- Terminal emulation → `VT100Parser`, `VT100Terminal`, `VT100ScreenMutableState`
- UI rendering → `PTYTextView.{h,m}`
- Tests → `tests/iTerm2XCTests/`
