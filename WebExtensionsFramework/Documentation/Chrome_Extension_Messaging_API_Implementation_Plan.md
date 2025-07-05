# Chrome Extension Messaging API Implementation Plan

## Overview

This document outlines the implementation plan for Chrome extension messaging APIs in the WebExtensions Framework. These APIs enable communication between different parts of an extension (content scripts, background service workers, and popup pages).

## API Reference Links

- Chrome Extensions Runtime API: https://developer.chrome.com/docs/extensions/reference/api/runtime
- Chrome Extensions Tabs API: https://developer.chrome.com/docs/extensions/reference/api/tabs
- Mozilla WebExtensions Runtime API: https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/runtime
- Mozilla WebExtensions Tabs API: https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/tabs

## Implementation Priority Order

### Phase 1: Minimal Working Implementation (Days 1-3)
Get basic message passing working between content script and background script.

1. **chrome.runtime.sendMessage()** (content script → background)
   - Full signature: `chrome.runtime.sendMessage([extensionId], message, [options], [responseCallback])`
   - Simplified v1: `chrome.runtime.sendMessage(message, responseCallback)`
   - Returns: `Promise<any>` if no callback provided

2. **chrome.runtime.onMessage** (receive in background)
   - Full signature: `chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {})`
   - `sender` object: `{ tab?: Tab, frameId?: number, id: string, url?: string, origin?: string }`
   - Must return `true` if responding asynchronously

3. **chrome.tabs.sendMessage()** (background → content script)
   - Full signature: `chrome.tabs.sendMessage(tabId, message, [options], [responseCallback])`
   - Options: `{ frameId?: number, documentId?: string }`
   - Returns: `Promise<any>` if no callback provided

### Phase 2: Complete Basic Messaging (Days 4-5)
Add runtime.id and bidirectional messaging.

4. **chrome.runtime.id** (property)
   - Simple string property containing extension ID
   - Available in all contexts

5. **chrome.runtime.getURL()**
   - Signature: `chrome.runtime.getURL(path)`
   - Returns: `string` - full URL to extension resource

6. **chrome.runtime.getManifest()**
   - Signature: `chrome.runtime.getManifest()`
   - Returns: `object` - the manifest.json content

### Phase 3: Port-based Communication (Days 6-8)
Add persistent connections for high-frequency messaging.

7. **chrome.runtime.connect()**
   - Full signature: `chrome.runtime.connect([extensionId], [connectInfo])`
   - `connectInfo`: `{ name?: string, includeTlsChannelId?: boolean }`
   - Returns: `Port` object

8. **chrome.tabs.connect()**
   - Full signature: `chrome.tabs.connect(tabId, [connectInfo])`
   - Returns: `Port` object

9. **Port object implementation**
   ```javascript
   Port {
       name: string,
       sender?: MessageSender,  // only on receiving end
       postMessage: (message: any) => void,
       disconnect: () => void,
       onMessage: ChromeEvent<(message: any, port: Port) => void>,
       onDisconnect: ChromeEvent<(port: Port) => void>
   }
   ```

10. **chrome.runtime.onConnect**
    - Signature: `chrome.runtime.onConnect.addListener((port: Port) => void)`

### Phase 4: External Messaging (Days 9-10)
Enable cross-extension communication.

11. **chrome.runtime.onMessageExternal**
    - Same as onMessage but for external extensions

12. **chrome.runtime.onConnectExternal**
    - Same as onConnect but for external extensions

### Phase 5: Additional Runtime APIs (Days 11-12)
Complete the runtime namespace.

13. **chrome.runtime.lastError**
    - Property checked in callbacks for errors

14. **chrome.runtime.onInstalled**
    - Event fired when extension is installed/updated

15. **chrome.runtime.onStartup**
    - Event fired when browser starts

## Complete List of APIs to Implement

### chrome.runtime APIs

#### Available in: Background Service Worker, Content Scripts, Popup/Extension Pages

1. **chrome.runtime.sendMessage()**
   - Overloaded signatures:
     - `sendMessage(message, responseCallback?)`
     - `sendMessage(message, options, responseCallback?)`
     - `sendMessage(extensionId, message, options?, responseCallback?)`
   - Returns: `Promise<any>` if no callback
   - Purpose: Send a single message to extension listeners

2. **chrome.runtime.onMessage**
   - Event with methods: `addListener()`, `removeListener()`, `hasListener()`
   - Listener signature: `(message: any, sender: MessageSender, sendResponse: (response?: any) => void) => boolean | void`
   - MessageSender: `{ tab?: Tab, frameId?: number, id: string, url?: string, origin?: string }`

3. **chrome.runtime.connect()**
   - Overloaded signatures:
     - `connect(connectInfo?)`
     - `connect(extensionId, connectInfo?)`
   - ConnectInfo: `{ name?: string, includeTlsChannelId?: boolean }`
   - Returns: Port object

4. **chrome.runtime.onConnect**
   - Event listener for incoming connections
   - Listener signature: `(port: Port) => void`

5. **chrome.runtime.id**
   - Read-only property: `string`

6. **chrome.runtime.getURL()**
   - Signature: `getURL(path: string): string`

7. **chrome.runtime.getManifest()**
   - Signature: `getManifest(): object`

8. **chrome.runtime.lastError**
   - Property: `{ message?: string } | undefined`

9. **chrome.runtime.onMessageExternal**
   - Same as onMessage but for external extensions

10. **chrome.runtime.onConnectExternal**
    - Same as onConnect but for external extensions

### chrome.tabs APIs

#### Available in: Background Service Worker ONLY

1. **chrome.tabs.sendMessage()**
   - Signature: `sendMessage(tabId: number, message: any, options?: object, responseCallback?: function)`
   - Options: `{ frameId?: number, documentId?: string }`
   - Returns: `Promise<any>` if no callback

2. **chrome.tabs.connect()**
   - Signature: `connect(tabId: number, connectInfo?: object)`
   - Returns: Port object

### Port Object APIs

1. **port.name**
   - Property: `string | undefined`

2. **port.sender**
   - Property: `MessageSender | undefined` (only on receiving end)

3. **port.postMessage()**
   - Signature: `postMessage(message: any): void`

4. **port.disconnect()**
   - Signature: `disconnect(): void`

5. **port.onMessage**
   - Event with `addListener()`, `removeListener()`, `hasListener()`
   - Listener: `(message: any, port: Port) => void`

6. **port.onDisconnect**
   - Event with `addListener()`, `removeListener()`, `hasListener()`
   - Listener: `(port: Port) => void`

### Native Web APIs

#### Already available via WKWebView

1. **window.postMessage()**
   - Standard web API for cross-origin communication
   - Can be used for iframe communication within content scripts

2. **window.addEventListener('message', handler)**
   - Standard web API for receiving postMessage events

## Development Process

### Test-Driven Development Approach

All development will follow strict TDD principles as outlined in CLAUDE.md:
1. Write tests first
2. Ensure tests fail
3. Write implementation
4. Ensure tests pass
5. Refactor if needed

### Test Harness Architecture

#### 1. Mock Chrome API Environment
Create a test harness that simulates the Chrome extension environment without requiring a full browser:

```swift
// ChromeAPITestHarness.swift
class ChromeAPITestHarness {
    private var contentScriptWebView: WKWebView
    private var backgroundWebView: WKWebView
    private var messageRouter: ExtensionMessageRouter
    
    func injectChromeAPIs(into webView: WKWebView, context: ExtensionContext)
    func evaluateJavaScript(_ script: String, in context: ExtensionContext) async throws -> Any?
    func waitForMessage(matching predicate: (Any) -> Bool, timeout: TimeInterval) async throws -> Any
}
```

#### 2. JavaScript Test Environment
Create JavaScript test utilities that will be injected alongside the Chrome APIs:

```javascript
// test-utilities.js
window.__testHarness = {
    // Capture all messages sent
    sentMessages: [],
    
    // Track all registered listeners
    registeredListeners: new Map(),
    
    // Mock responses for testing
    mockResponses: new Map(),
    
    // Assertions
    assertMessageSent: function(expectedMessage) { /* ... */ },
    assertListenerCalled: function(listenerId) { /* ... */ },
    
    // Setup/teardown
    reset: function() { /* ... */ }
};
```

#### 3. Test Structure

Each API will have corresponding test files:

```
Tests/
├── ChromeRuntimeTests/
│   ├── SendMessageTests.swift
│   ├── OnMessageTests.swift
│   ├── ConnectTests.swift
│   └── PortTests.swift
├── ChromeTabsTests/
│   ├── TabsSendMessageTests.swift
│   └── TabsConnectTests.swift
└── IntegrationTests/
    ├── ContentToBackgroundMessagingTests.swift
    ├── BackgroundToContentMessagingTests.swift
    └── PortCommunicationTests.swift
```

### Development Workflow for Each API

#### Example: Implementing chrome.runtime.sendMessage()

**Step 1: Write the test (Tests/ChromeRuntimeTests/SendMessageTests.swift)**
```swift
func testSendMessageFromContentScriptToBackground() async throws {
    // Arrange
    let harness = ChromeAPITestHarness()
    let testMessage = ["type": "test", "data": "hello"]
    let expectedResponse = ["status": "received"]
    
    // Register a message listener in background
    try await harness.evaluateJavaScript("""
        chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
            window.__testHarness.assertMessageReceived(message);
            sendResponse({status: 'received'});
        });
    """, in: .background)
    
    // Act - Send message from content script
    let response = try await harness.evaluateJavaScript("""
        chrome.runtime.sendMessage({type: 'test', data: 'hello'})
    """, in: .contentScript)
    
    // Assert
    XCTAssertEqual(response as? [String: String], expectedResponse)
}

func testSendMessageWithPromise() async throws {
    // Test promise-based API when no callback provided
}

func testSendMessageToSpecificExtension() async throws {
    // Test sending to specific extension ID
}
```

**Step 2: Run test and verify it fails**
```bash
swift test --filter SendMessageTests
# Expected: Test fails because chrome.runtime.sendMessage is not defined
```

**Step 3: Implement the API**

Create JavaScript implementation:
```javascript
// Sources/JavaScriptAPIs/chrome-runtime-api.js
chrome.runtime.sendMessage = function(/* ... */) {
    // Implementation
};
```

Create Swift bridge:
```swift
// Sources/BrowserExtensionRuntimeAPI.swift
class BrowserExtensionRuntimeAPI {
    func handleSendMessage(/* ... */) async throws -> Any? {
        // Route message through ExtensionMessageRouter
    }
}
```

**Step 4: Run test and verify it passes**
```bash
swift test --filter SendMessageTests
# Expected: All tests pass
```

### Testing Guidelines

1. **Unit Tests**
   - Test each API method in isolation
   - Mock all dependencies
   - Test error conditions
   - Test parameter validation
   - Test callback vs promise behavior

2. **Integration Tests**
   - Test actual message flow between contexts
   - Test with multiple extensions
   - Test message ordering
   - Test concurrent operations

3. **Edge Case Tests**
   - Large messages
   - Rapid message sending
   - Extension unload during messaging
   - Invalid extension IDs
   - Circular message patterns

4. **Performance Tests**
   - Message throughput
   - Memory usage with many listeners
   - Port connection limits

### Continuous Integration

Each commit should:
1. Pass all existing tests
2. Include new tests for new functionality
3. Maintain 100% code coverage for new code
4. Pass linting and format checks

### Example Test Implementation Timeline

**Day 1: Test Harness**
- Create ChromeAPITestHarness
- Create JavaScript test utilities
- Set up basic test structure

**Day 2-3: Phase 1 APIs**
- Write tests for sendMessage
- Implement sendMessage
- Write tests for onMessage
- Implement onMessage
- Write tests for tabs.sendMessage
- Implement tabs.sendMessage

**Day 4-5: Phase 2 APIs**
- Write tests for runtime.id, getURL, getManifest
- Implement these simpler APIs

**Day 6-8: Phase 3 APIs**
- Write tests for connect() and Port
- Implement Port-based messaging

This TDD approach ensures:
- APIs work correctly before integration
- Regressions are caught immediately
- API contracts are well-defined
- Code is testable and maintainable

## Implementation Architecture

### 1. Swift Components

#### ExtensionMessage.swift
```swift
struct ExtensionMessage {
    let id: UUID
    let source: MessageSource
    let destination: MessageDestination
    let payload: Any // JSON-serializable
    let responseCallback: ((Any?) -> Void)?
}

enum MessageSource {
    case contentScript(tabId: Int, frameId: Int)
    case backgroundScript
    case popup
    case devtools
}

enum MessageDestination {
    case backgroundScript
    case contentScript(tabId: Int, frameId: Int?)
    case allContentScripts
    case extension(id: String)
}
```

#### ExtensionMessageRouter.swift
- Central message routing between all extension contexts
- Maintains registry of message handlers
- Handles async message responses
- Manages port connections

#### BrowserExtensionRuntimeAPI.swift
- Implements the Swift side of runtime API
- Handles incoming JavaScript messages
- Manages callbacks and promises

#### BrowserExtensionTabsMessagingAPI.swift
- Implements tabs.sendMessage and tabs.connect
- Integrates with tab management system

### 2. JavaScript Implementation

#### chrome-runtime-api.js
```javascript
// Injected into all extension contexts
chrome.runtime = {
    id: '__EXTENSION_ID__',
    
    sendMessage: function(extensionId, message, options, callback) {
        // Handle overloaded parameters
        if (typeof extensionId !== 'string') {
            callback = options;
            options = message;
            message = extensionId;
            extensionId = null;
        }
        
        // Create promise if no callback
        if (!callback && typeof options !== 'function') {
            return new Promise((resolve) => {
                this.sendMessage(extensionId, message, options, resolve);
            });
        }
        
        // Send to native bridge
        window.webkit.messageHandlers.chromeRuntime.postMessage({
            action: 'sendMessage',
            extensionId: extensionId,
            message: message,
            options: options,
            callbackId: __registerCallback(callback)
        });
    },
    
    onMessage: __createChromeEvent('runtime.onMessage'),
    
    connect: function(extensionId, connectInfo) {
        // Implementation similar to sendMessage
        // Returns Port object
    },
    
    onConnect: __createChromeEvent('runtime.onConnect')
};
```

#### chrome-tabs-api.js
```javascript
// Injected into background service worker ONLY
chrome.tabs = {
    sendMessage: function(tabId, message, options, callback) {
        // Similar pattern to runtime.sendMessage
        window.webkit.messageHandlers.chromeTabs.postMessage({
            action: 'sendMessage',
            tabId: tabId,
            message: message,
            options: options,
            callbackId: __registerCallback(callback)
        });
    },
    
    connect: function(tabId, connectInfo) {
        // Returns Port object
    }
};
```

#### port-implementation.js
```javascript
class Port {
    constructor(name, portId) {
        this.name = name;
        this.sender = null; // Set by receiver
        this._portId = portId;
        this.onMessage = __createChromeEvent('port.onMessage.' + portId);
        this.onDisconnect = __createChromeEvent('port.onDisconnect.' + portId);
    }
    
    postMessage(message) {
        window.webkit.messageHandlers.chromePort.postMessage({
            action: 'postMessage',
            portId: this._portId,
            message: message
        });
    }
    
    disconnect() {
        window.webkit.messageHandlers.chromePort.postMessage({
            action: 'disconnect',
            portId: this._portId
        });
    }
}
```

### 3. Message Flow

#### Content Script → Background Script
1. Content script calls `chrome.runtime.sendMessage()`
2. JavaScript bridge sends to Swift via webkit.messageHandlers
3. ExtensionMessageRouter routes to background service worker
4. Background script's onMessage listener receives message
5. Response flows back through same path

#### Background Script → Content Script
1. Background script calls `chrome.tabs.sendMessage(tabId, message)`
2. ExtensionMessageRouter identifies target content script
3. Message injected into content script's context
4. Content script's onMessage listener receives message

#### Port-based Communication
1. Initiator calls connect()
2. Port objects created on both ends
3. Messages flow through dedicated channel
4. Either end can disconnect

## Implementation Phases

### Phase 1: Core Infrastructure
- ExtensionMessage and MessageRouter
- Basic JavaScript bridge setup
- Message handler registration in WebViews

### Phase 2: Runtime API - Basic Messaging
- Implement sendMessage/onMessage
- Handle callbacks and promises
- Test content ↔ background communication

### Phase 3: Port-based Messaging
- Implement connect() methods
- Create Port object implementation
- Handle port lifecycle

### Phase 4: Tabs API Messaging
- Implement tabs.sendMessage
- Implement tabs.connect
- Integrate with tab management

### Phase 5: External Messaging
- onMessageExternal/onConnectExternal
- Cross-extension communication
- Security considerations

### Phase 6: Edge Cases & Polish
- Error handling
- Message size limits
- Timeout handling
- Performance optimization

## Security Considerations

1. **Message Validation**
   - Validate all messages are JSON-serializable
   - Sanitize message content
   - Enforce message size limits

2. **Origin Verification**
   - Verify sender extension ID
   - Check content script origin
   - Validate tab IDs

3. **Permission Checks**
   - Respect extension permissions
   - Isolate extensions from each other
   - Prevent unauthorized cross-extension communication

4. **Resource Management**
   - Limit number of open ports
   - Clean up disconnected ports
   - Prevent memory leaks from callbacks

## Testing Strategy

1. **Unit Tests**
   - Test each API method
   - Test message serialization
   - Test error conditions

2. **Integration Tests**
   - Test actual message flow
   - Test with the custom-user-agent extension
   - Test multiple extensions

3. **Performance Tests**
   - Message throughput
   - Large message handling
   - Multiple simultaneous connections

4. **Security Tests**
   - Attempt cross-extension attacks
   - Test permission enforcement
   - Verify message isolation