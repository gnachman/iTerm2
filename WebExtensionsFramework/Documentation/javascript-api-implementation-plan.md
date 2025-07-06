# JavaScript API Implementation Plan

## Overview

This document outlines our plan to implement JavaScript APIs (`chrome.runtime`, `chrome.tabs`, etc.) for the web extensions framework. We'll use Mozilla's Firefox implementation as our primary guide due to its clean architecture and well-defined separation of concerns.

## Firefox Source Code Navigation Guide

### Understanding Firefox's Extension API Architecture

Firefox's WebExtension APIs follow a layered architecture:
1. **JS Host Layer** - JavaScript implementation with callback-style APIs
2. **WebIDL Binding Layer** - Interface definitions for browser object
3. **C++ Implementation Layer** - Native implementation backing the APIs

### Example: Tracing `browser.runtime.id` Implementation

To understand how any API is wired up in Firefox, follow these steps:

#### 1. Find the Schema Definition
Location: `toolkit/components/extensions/schemas/runtime.json`

Look for the property definition:
```json
"properties": {
  "id": {
    "type": "string",
    "allowedContexts": ["content", "devtools"],
    "description": "The ID of the extension/app."
  }
}
```

This schema serves multiple purposes:
- Defines API surface and validation rules
- Specifies allowed contexts (content scripts, devtools, etc.)
- Used to auto-generate WebIDL interfaces
- Referenced by the JS host registration

#### 2. Find the JS Host Registration
Location: `toolkit/components/extensions/ext-toolkit.json`

Look for the API namespace:
```json
"runtime": {
  "url": "chrome://extensions/content/parent/ext-runtime.js",
  "schema": "chrome://extensions/content/schemas/runtime.json", 
  "scopes": ["addon_parent","content_parent","devtools_parent"],
  "paths": [["runtime"]]
}
```

This tells the loader:
- Load `ext-runtime.js` for callback-style methods/events
- Use `runtime.json` schema for validation and WebIDL generation
- Make available in specified scopes
- Register under `chrome.runtime.*` namespace

#### 3. Check the Generated WebIDL
Location: `dom/webidl/ExtensionRuntime.webidl` (auto-generated from schema)

The schema generates WebIDL property definitions:
```webidl
// API properties.
[Replaceable]
readonly attribute DOMString id;
```

This creates the `browser.runtime.id` property binding.

#### 4. Locate the C++ Implementation
Location: `toolkit/components/extensions/webidl-api/ExtensionRuntime.cpp`

```cpp
void ExtensionRuntime::GetId(dom::DOMString& aRetval) {
  GetWebExtPropertyAsString(u"id"_ns, aRetval);
}
```

#### 5. Important Distinction: Properties vs Methods/Events
**Properties** (like `runtime.id`):
- Defined in schema JSON
- Auto-generated WebIDL → C++ machinery
- **NOT** found in `ext-runtime.js`

**Methods/Events** (like `sendMessage`, `onMessage`):
- Defined in schema JSON for validation
- Custom implementation in `ext-runtime.js`
- Handle callback conversion and complex logic
- Implement only callbacks. We will later on add https://github.com/mozilla/webextension-polyfill to add support for promises.

So when tracing an API, check the schema first to understand whether it's a simple property or requires custom JavaScript logic.

### Key Firefox Source Locations

The firefox source is located in the root of the WebExtensionsFramework repo. Source locations below are relative to the firefox directory.

| Component | Location | Purpose |
|-----------|----------|---------|
| API Registry | `firefox/toolkit/components/extensions/ext-toolkit.json` | Maps namespaces to implementations |
| JS Host APIs | `firefox/toolkit/components/extensions/parent/ext-*.js` | JavaScript callback-style implementations |
| Schemas | `firefox/toolkit/components/extensions/schemas/*.json` | API parameter validation schemas |
| WebIDL Interfaces | `firefox/dom/webidl/Extension*.webidl` | Browser object interface definitions |
| C++ Bindings | `firefox/toolkit/components/extensions/webidl-api/` | Native implementation backing |

## Our Swift Implementation Architecture

### Proposed Layer Structure

```
┌─────────────────────────────────────────┐
│           JavaScript Layer              │
│  (webextension-polyfill + our bindings) │
├─────────────────────────────────────────┤
│           Message Router                │
│    (WKWebView ↔ Swift communication)    │
├─────────────────────────────────────────┤
│          Swift API Handlers             │
│     (BrowserExtensionRuntimeAPI)        │
├─────────────────────────────────────────┤
│         Core Extension Engine           │
│   (Manifest, Context, Security)         │
└─────────────────────────────────────────┘
```

### Phase 1: Core Infrastructure

#### 1.1 Message Router Foundation
Create the communication bridge between JavaScript and Swift:

```swift
protocol BrowserExtensionMessageRouter {
    func handleMessage(_ message: BrowserExtensionMessage) async -> BrowserExtensionResponse
    func sendEvent(_ event: BrowserExtensionEvent, to context: BrowserExtensionContext)
}
```

#### 1.2 Context Management
Track different execution contexts (background, content, popup):

```swift
enum BrowserExtensionContextType {
    case background
    case contentScript(tabId: String)
    case popup
    case devtools
}

protocol BrowserExtensionContext {
    var type: BrowserExtensionContextType { get }
    var extensionId: String { get }
    var webView: WKWebView { get }
}
```

#### 1.3 JavaScript Binding Layer
Inject webextension-polyfill and our custom message bridge:

```javascript
// Injected into each context
window.chrome = window.browser = new Proxy({}, {
    get(target, namespace) {
        return createNamespaceProxy(namespace);
    }
});

function createNamespaceProxy(namespace) {
    return new Proxy({}, {
        get(target, method) {
            return (...args) => sendToNative(namespace, method, args);
        }
    });
}
```

### Phase 2: Simple APIs (No Message Passing)

Start with APIs that don't require inter-context communication:

#### 2.1 `chrome.runtime.getManifest()`
**Firefox Reference**: `ext-runtime.js` - direct manifest access
**Implementation**: 
```swift
func handleGetManifest() -> [String: Any] {
    return manifestParser.parsedManifest
}
```

#### 2.2 `chrome.runtime.id`
**Firefox Reference**: Auto-generated from `runtime.json` schema
**Implementation**:
```swift
var runtimeId: String {
    return browserExtension.manifest.id
}
```

#### 2.3 `chrome.runtime.getURL(path)`
**Firefox Reference**: `ext-runtime.js` - URL construction
**Implementation**:
```swift
func getURL(path: String) -> String {
    return "chrome-extension://\(extensionId)/\(path)"
}
```

### Phase 3: Message Passing APIs

Implement inter-context communication:

#### 3.1 `chrome.runtime.sendMessage()`
**Firefox Reference**: `ext-runtime.js` - uses message manager
**Architecture**:
```
Content Script → Message Router → Background Script
              ← Response ←
```

#### 3.2 `chrome.runtime.onMessage`
**Firefox Reference**: `ext-runtime.js` - event listener management
**Implementation**: Event subscription system with listener tracking

### Phase 4: Complex APIs

#### 4.1 `chrome.tabs.*`
**Firefox Reference**: `ext-tabs.js`
**Requires**: Tab management integration with host browser

#### 4.2 Port-based messaging
**Firefox Reference**: `ext-runtime.js` - long-lived connections
**Implementation**: Persistent communication channels

## Implementation Strategy

### 1. Test-Driven Development
Following the project's TDD practice:

```swift
// Example test structure
class BrowserExtensionRuntimeAPITests: XCTestCase {
    func testGetManifestReturnsValidManifest() async {
        // Given: Extension with known manifest
        // When: Call getManifest()
        // Then: Returns parsed manifest data
    }
}
```

### 2. Dependency Injection
All components use protocols for testability:

```swift
protocol BrowserExtensionManifestProvider {
    var manifest: BrowserExtensionManifest { get }
}

class BrowserExtensionRuntimeAPI {
    private let manifestProvider: BrowserExtensionManifestProvider
    
    init(manifestProvider: BrowserExtensionManifestProvider) {
        self.manifestProvider = manifestProvider
    }
}
```

### 3. Security First
- Validate all JavaScript→Swift messages
- Enforce extension permissions
- Sanitize URLs and paths
- Prevent privilege escalation

### 4. Async/Await Throughout
Use modern Swift concurrency:

```swift
func sendMessage(_ message: Any, to extensionId: String?) async throws -> Any? {
    // Implementation using async/await
}
```

## Testing Strategy

### Unit Tests
- Mock all dependencies using protocols
- Test each API method in isolation
- Use sinon-chrome patterns for JavaScript testing

### Integration Tests
- Test JavaScript↔Swift message flow
- Verify webextension-polyfill integration
- Test with real WKWebView instances

### Security Tests
- Validate permission enforcement
- Test malicious input handling
- Verify context isolation

## Rollout Plan

1. **Week 1-2**: Core infrastructure (message router, context management)
2. **Week 3**: Simple runtime APIs (getManifest, id, getURL)
3. **Week 4**: Message passing (sendMessage, onMessage)
4. **Week 5-6**: Tabs APIs
5. **Week 7+**: Additional namespaces as needed

## Success Metrics

- [ ] webextension-polyfill integration working
- [ ] sinon-chrome tests passing in WKWebView
- [ ] Basic extension can load and execute
- [ ] Message passing between contexts functional
- [ ] Security model enforced correctly

## Next Steps

1. Create `BrowserExtensionMessageRouter` protocol and implementation
2. Design JavaScript injection system for webextension-polyfill
3. Implement `chrome.runtime.getManifest()` with full TDD cycle
4. Add integration with existing manifest parsing code

This plan provides a roadmap for systematically implementing the JavaScript API surface while following Firefox's proven architecture patterns.
