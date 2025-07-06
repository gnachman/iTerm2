# Background Scripts Implementation Plan

## Overview

This document describes the implementation plan for WebExtensions background script support using hidden WKWebView instances with DOM API restrictions. This approach provides full web platform API compatibility (fetch, IndexedDB, WebSocket, etc.) while preventing DOM access and ensuring proper isolation between extensions.

## Architecture Decision

**Background scripts run in hidden WKWebView instances** with injected JavaScript to remove DOM globals. This provides:
- ✅ Full web platform APIs (fetch, IndexedDB, WebSocket, Crypto, etc.)
- ✅ No implementation burden for web APIs 
- ✅ Process isolation (each WKWebView runs in separate process)
- ✅ Ephemeral data stores (no persistence between sessions)
- ✅ Clean extension lifecycle (disable = complete removal)

**One hidden WKWebView per extension background script** (not shared):
- Extension A → Hidden WKWebView A (with background.js)
- Extension B → Hidden WKWebView B (with background.js)
- Complete isolation and independent lifecycle management

## Implementation Components

### 1. Background Script Loading (Already Implemented)

**ExtensionManifest.swift** - COMPLETED
- BackgroundScript struct with service_worker, scripts, persistent, type fields
- Integrated into ExtensionManifest with proper validation
- Comprehensive tests for manifest parsing and validation

**BrowserExtension.swift** - NEEDS COMPLETION
- BackgroundScriptResource struct (already added)
- loadBackgroundScript() method (needs implementation)
- backgroundScriptResource property (already added)

### 2. Core Background Service

**BrowserExtensionBackgroundService.swift** - TO IMPLEMENT
```swift
@MainActor
public protocol BrowserExtensionBackgroundServiceProtocol {
    func startBackgroundScript(for extension: BrowserExtension) throws
    func stopBackgroundScript(for extensionId: String)
    func stopAllBackgroundScripts()
    func isBackgroundScriptActive(for extensionId: String) -> Bool
    var activeBackgroundScripts: [String: WKWebView] { get }
}

@MainActor
public class BrowserExtensionBackgroundService: BrowserExtensionBackgroundServiceProtocol {
    private var backgroundWebViews: [String: WKWebView] = [:]
    private let hiddenContainer: UIView
    
    public init(hiddenContainer: UIView)
    public func startBackgroundScript(for extension: BrowserExtension) throws
    public func stopBackgroundScript(for extensionId: String)
    // ... other methods
}
```

**Key Implementation Details:**
- Each extension gets separate WKWebView with ephemeral data store
- WebViews added to hidden container (must be in view hierarchy for full functionality)
- DOM nuke script injected at document start
- Background script loaded via evaluateJavaScript
- Clean teardown removes WebView from hierarchy and deallocates

### 3. DOM Nuke Script Generator

**Function: generateDOMNukeScript() -> String**
```javascript
(function() {
    'use strict';
    
    const DOM_GLOBALS = [
        // Core DOM
        'document', 'window', 'Document', 'Window',
        'HTMLElement', 'Element', 'Node', 'Text', 'Comment',
        
        // HTML Elements (comprehensive list)
        'HTMLDivElement', 'HTMLSpanElement', 'HTMLButtonElement',
        // ... all HTML element types
        
        // DOM manipulation
        'querySelector', 'querySelectorAll', 'getElementById',
        'getElementsByClassName', 'getElementsByTagName',
        'createElement', 'createTextNode', 'appendChild', 'removeChild',
        
        // Events
        'Event', 'MouseEvent', 'KeyboardEvent', 'CustomEvent',
        'addEventListener', 'removeEventListener', 'dispatchEvent',
        
        // Browser/Navigation
        'location', 'history', 'navigator',
        
        // UI
        'alert', 'confirm', 'prompt',
        
        // Legacy storage (force chrome.storage usage)
        'localStorage', 'sessionStorage',
        
        // Legacy HTTP (force fetch usage)
        'XMLHttpRequest'
    ];
    
    const global = this;
    
    // Nuke DOM globals using Object.defineProperty for robustness
    DOM_GLOBALS.forEach(name => {
        if (name in global) {
            Object.defineProperty(global, name, {
                get() { return null },
                set(v) {}, // Silently ignore attempts to set
                configurable: true
            });
        }
    });
    
    // Set up service worker environment
    global.self = global;
    global.registration = {
        scope: '/',
        updateViaCache: 'none'
    };
    
    // Preserve essential service worker APIs:
    // fetch, Request, Response, Headers, indexedDB, caches, 
    // crypto, WebSocket, setTimeout, setInterval, Promise, URL
    
})();
```

### 4. Integration with Existing Framework

**BrowserExtension.swift Updates** - TO IMPLEMENT
```swift
/// Load background script from the extension directory
public func loadBackgroundScript() throws {
    guard let background = manifest.background else {
        backgroundScriptResource = nil
        return
    }
    
    backgroundScriptResource = try loadBackgroundScriptResource(background)
}

private func loadBackgroundScriptResource(_ background: BackgroundScript) throws -> BackgroundScriptResource {
    var jsContent: String = ""
    var isServiceWorker: Bool = false
    
    if let serviceWorker = background.serviceWorker {
        jsContent = try loadFileContent(serviceWorker)
        isServiceWorker = true
    } else if let scripts = background.scripts {
        // Concatenate legacy background scripts
        var combinedScripts: [String] = []
        for script in scripts {
            let content = try loadFileContent(script)
            combinedScripts.append(content)
        }
        jsContent = combinedScripts.joined(separator: "\n\n")
        isServiceWorker = false
    }
    
    return BackgroundScriptResource(
        config: background,
        jsContent: jsContent,
        isServiceWorker: isServiceWorker
    )
}
```

**BrowserExtensionRegistry.swift Updates** - TO IMPLEMENT
Update registry to also load background scripts:
```swift
// In add(extensionPath:) method, after loading content scripts:
do {
    try browserExtension.loadBackgroundScript()
} catch {
    throw BrowserExtensionRegistryError.backgroundScriptLoadError(extensionPath, error)
}
```

**BrowserExtensionActiveManager.swift Integration** - TO IMPLEMENT
```swift
public class BrowserExtensionActiveManager: BrowserExtensionActiveManagerProtocol {
    private let backgroundService: BrowserExtensionBackgroundServiceProtocol
    
    public init(
        injectionScriptGenerator: BrowserExtensionContentScriptInjectionGeneratorProtocol,
        userScriptFactory: BrowserExtensionUserScriptFactoryProtocol,
        backgroundService: BrowserExtensionBackgroundServiceProtocol
    )
    
    public func activate(_ browserExtension: BrowserExtension) throws {
        // ... existing content script activation ...
        
        // Start background script if present
        if browserExtension.manifest.background != nil {
            try backgroundService.startBackgroundScript(for: browserExtension)
        }
    }
    
    public func deactivate(_ extensionId: String) {
        // Stop background script first
        backgroundService.stopBackgroundScript(for: extensionId)
        
        // ... existing content script deactivation ...
    }
    
    public func deactivateAll() {
        backgroundService.stopAllBackgroundScripts()
        // ... existing logic ...
    }
}
```

### 5. Test Extensions

**background-demo Extension** - TO CREATE
```
test-extensions/background-demo/
├── manifest.json
├── background.js
└── content.js
```

**manifest.json:**
```json
{
  "manifest_version": 3,
  "name": "Background Demo",
  "version": "1.0",
  "description": "Tests background script functionality",
  
  "background": {
    "service_worker": "background.js"
  },
  
  "content_scripts": [{
    "matches": ["<all_urls>"],
    "js": ["content.js"],
    "run_at": "document_end"
  }],
  
  "permissions": ["storage"]
}
```

**background.js:**
```javascript
// Test that DOM globals are removed
console.log('Background script loaded');
console.log('document:', typeof document); // Should be null
console.log('window:', typeof window);     // Should be null

// Test that web APIs are available
console.log('fetch:', typeof fetch);       // Should be function
console.log('indexedDB:', typeof indexedDB); // Should be object

// Test storage and messaging
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    console.log('Background received message:', message);
    sendResponse({reply: 'Hello from background!'});
});

// Test fetch API
fetch('https://httpbin.org/json')
    .then(response => response.json())
    .then(data => console.log('Fetch test successful:', data))
    .catch(error => console.error('Fetch test failed:', error));
```

**content.js:**
```javascript
// Test messaging with background script
chrome.runtime.sendMessage({type: 'test'}, (response) => {
    console.log('Content script received response:', response);
});

// Add indicator to page
const indicator = document.createElement('div');
indicator.style.cssText = `
    position: fixed; top: 10px; right: 10px; 
    background: blue; color: white; padding: 5px; 
    z-index: 10000; font-size: 12px;
`;
indicator.textContent = 'Background Demo Active';
document.body.appendChild(indicator);
```

## Implementation Order (TDD)

### Phase 1: Core Background Service
1. ✅ **Background script manifest support** (COMPLETED)
2. **Write tests for BrowserExtensionBackgroundService**
3. **Implement BrowserExtensionBackgroundService class**
4. **Implement DOM nuke script generator**
5. **Test DOM globals removal**

### Phase 2: Extension Integration  
6. **Complete background script loading in BrowserExtension**
7. **Update BrowserExtensionRegistry to load background scripts**
8. **Integrate background service with ActiveManager**
9. **Write integration tests**

### Phase 3: Test Extension & E2E
10. **Create background-demo test extension**
11. **Write E2E tests with real background script execution**
12. **Test extension lifecycle (activate/deactivate)**
13. **Test isolation between multiple background scripts**

### Phase 4: Chrome Runtime API Foundation
14. **Implement basic chrome.runtime.sendMessage() infrastructure**
15. **Add message passing between content scripts and background scripts**
16. **Test messaging in background-demo extension**

## Success Criteria

1. **Background scripts load and execute** in hidden WKWebView instances
2. **DOM globals are successfully removed** (document, window, etc. return null)
3. **Web platform APIs remain available** (fetch, IndexedDB, WebSocket work)
4. **Multiple extensions run independently** with separate WebView instances
5. **Clean lifecycle management** (deactivate completely removes WebView)
6. **Ephemeral data stores** (no persistence between sessions)
7. **Process isolation** between extensions and main app

## Architecture Benefits

- **No API implementation burden** - WKWebView provides all web APIs
- **Future-proof** - automatically gets new web standards as Safari updates
- **Strong isolation** - each extension in separate process
- **Security** - DOM access blocked, process boundaries enforced
- **Performance** - WKWebView's optimized JavaScript engine
- **Maintainability** - minimal custom code, leverages platform capabilities

## Testing Strategy

- **Unit tests** for each component before implementation
- **Mock objects** for WKWebView protocols during testing
- **Integration tests** for extension loading and activation
- **E2E tests** with real background script execution
- **Isolation tests** to verify DOM globals removal
- **Lifecycle tests** for extension activate/deactivate
