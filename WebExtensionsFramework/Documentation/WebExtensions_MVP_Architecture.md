# WebExtensions MVP Architecture

## Goal
Implement minimal extension system to load and run the red-box extension (adds red box to top of every page).

## Core Class Architecture

### 1. **ExtensionRegistry**
- Holds collection of installed extensions
- For MVP: hard-coded list pointing to `test-extensions/red-box/`
- Later: discovery, loading, enable/disable management

### 2. **Extension** 
- Represents a single loaded extension
- Contains manifest data, content scripts, file paths
- Immutable data structure once loaded

### 3. **ExtensionManifest** (struct)
- Parsed representation of manifest.json contents
- Contains: name, version, content_scripts array, permissions, etc.
- Validation rules embedded

### 4. **ManifestParser**
- Parses manifest.json files
- Validates Manifest V3 compliance
- Returns `ExtensionManifest` struct or throws errors

### 5. **ExtensionNavigationHandler** 
- Public APIs that mirror `WKNavigationDelegate` methods
- Browser's real delegate calls into this
- Methods like: `didFinishNavigation(webView:navigation:)`
- Coordinates with other managers

### 6. **ContentScriptInjector**
- Handles actual `WKUserScript` creation and injection
- Reads JavaScript files from extension bundles
- Manages injection timing (`document_end`, etc.)

### 7. **ContentWorldManager**
- Creates and manages `WKContentWorld` instances
- One world per extension for isolation
- Handles cleanup when extensions unload

## Call Flow
```
Browser WKNavigationDelegate
  ↓
ExtensionNavigationHandler.didFinishNavigation()
  ↓  
ContentScriptInjector.injectMatchingScripts()
  ↓
ContentWorldManager.getOrCreateWorld(for: extension)
  ↓
WKWebView.evaluateJavaScript(in: contentWorld)
```

## Implementation Strategy

### Architecture Principles
- **Clean Separation**: Extension system is separate component from browser core
- **Browser Integration**: Browser's WKNavigationDelegate calls into extension system
- **Isolation**: Each extension gets its own WKContentWorld
- **Hard-coded MVP**: Extensions discovered via hard-coded paths initially

### Sample Integration Point
```swift
// Browser's existing WKNavigationDelegate
class BrowserNavigationDelegate: NSObject, WKNavigationDelegate {
    private let extensionHandler = ExtensionNavigationHandler()
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Browser's existing logic...
        
        // Call into extension system
        extensionHandler.didFinishNavigation(webView: webView, navigation: navigation)
    }
}
```

### ExtensionRegistry (Hard-coded MVP)
```swift
class ExtensionRegistry {
    private let extensions: [Extension]
    
    init() {
        // Hard-coded for MVP
        let redBoxPath = "test-extensions/red-box/"
        self.extensions = [try! loadExtension(at: redBoxPath)]
    }
    
    func extensionsForURL(_ url: URL) -> [Extension]
}
```

### ExtensionNavigationHandler (Browser Integration Point)
```swift
class ExtensionNavigationHandler {
    func didFinishNavigation(webView: WKWebView, navigation: WKNavigation!)
    func didStartProvisionalNavigation(webView: WKWebView, navigation: WKNavigation!)
}
```

## Implementation Order

### Week 1: Core Data Structures
1. **ExtensionManifest** (struct) - Parse manifest.json into typed structure
2. **ManifestParser** - Validate and parse manifest files  
3. **Extension** - Immutable representation of loaded extension
4. **ExtensionRegistry** - Collection manager (hard-coded red-box for MVP)

### Week 1: Integration Layer
5. **ExtensionNavigationHandler** - Public APIs that browser calls into
6. **ContentWorldManager** - Manage WKContentWorld lifecycle per extension
7. **ContentScriptInjector** - Handle actual script injection into webviews

## Success Criteria
- ✅ Parse red-box manifest.json successfully
- ✅ Create Extension object with content script info
- ✅ Browser navigation calls trigger extension handler
- ✅ Content script injected in isolated WKContentWorld
- ✅ Red box appears on all pages

## Test Strategy
- Unit tests for each class before implementation
- Test-driven development approach
- Integration tests for end-to-end flow
- Manual testing with red-box extension