# WebExtensions MVP Design

## Goal
Build a minimal proof-of-concept to validate the core browser-proxy context correlation system and native background service architecture.

## Test Extension: Custom User Agent Modifier

Our MVP will implement a simple extension that modifies the User-Agent header for requests from specific tabs. This tests the most challenging aspect of our architecture - correlating browser context with proxy network requests.

**Extension Functionality:**
- Background script monitors tab updates via `chrome.tabs.onUpdated`
- When user navigates to `example.com`, extension flags that tab for User-Agent modification
- Content script injected on `example.com` displays current User-Agent in page
- All HTTP requests from flagged tabs get modified User-Agent: `"CustomBrowser/1.0"`

## MVP Components

### 1. Minimal Extension Framework
- **WebExtensionManager**: Load single test extension from local directory
- **XPCController**: Spawn one extension process for test extension
- **Basic manifest.json parser**: Support minimal Manifest V3 fields

### 2. Native Background Service
- Replace service worker entirely with native Swift process
- Implement minimal `chrome.tabs` API (onUpdated event only)
- Implement basic storage for tracking flagged tabs

### 3. Browser-Proxy Context Correlation (Core Test)
- **RequestTracker**: Monitor WKWebView navigation, generate correlation IDs
- **ProxyBridge**: Send tab context to proxy before requests
- **Context Matching**: Proxy correlates incoming requests with browser context
- **Header Modification**: Modify User-Agent for requests from specific tabs

### 4. Content Script System
- **WKContentWorld isolation**: Inject test script in isolated context
- **Message passing**: Content script ↔ background service communication
- **DOM access**: Display modified User-Agent on test page

## Success Criteria

1. **Extension loads** successfully from local manifest.json
2. **Context correlation works**: Proxy receives tab context for requests
3. **Request modification succeeds**: User-Agent header changes for specific tabs only
4. **Content script functions**: Displays modified User-Agent on page
5. **Performance acceptable**: <100ms overhead for request processing

## Implementation Order

1. **Week 1**: Basic extension loading and XPC process spawning
2. **Week 2**: Native background service with minimal `chrome.tabs` API
3. **Week 3**: Browser-proxy context correlation system
4. **Week 4**: Content script injection and header modification

This MVP validates our core architectural assumptions while keeping scope minimal. If context correlation works reliably for User-Agent modification, the same system will support more complex extension features.