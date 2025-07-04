# background

## Type
Object

## Required
No

## Description
Defines the background script or service worker for the extension. Background scripts run in the background and can handle events and perform long-running operations independent of web pages.

## Object Properties

### Required
At least one of the following must be specified:

- `service_worker`: String (file path)
  - Path to a JavaScript file acting as the extension's service worker
  - Preferred approach for Manifest V3
  - Runs in a service worker context with event-driven lifecycle

- `scripts`: Array of strings (file paths)
  - JavaScript files to be executed in the background context
  - Legacy approach (Manifest V2 compatibility)
  - Scripts share the same window global context
  - Loaded in the order they appear in the array

### Optional
- `persistent`: Boolean (default: false in V3, true in V2)
  - Whether the background page remains in memory
  - Deprecated in Manifest V3 (service workers are inherently non-persistent)
  - Only relevant for legacy `scripts` approach

- `type`: String (default: "classic")
  - Determines module loading behavior
  - Options: "classic", "module"
  - "module" enables ES6 import/export syntax

## Examples

### Service Worker (Manifest V3)
```json
"background": {
  "service_worker": "background.js"
}
```

### Legacy Background Scripts (Manifest V2 compatibility)
```json
"background": {
  "scripts": ["jquery.js", "background.js"],
  "persistent": false
}
```

### Module Support
```json
"background": {
  "service_worker": "background.js",
  "type": "module"
}
```

## Notes
- Background scripts have access to all WebExtension APIs (with appropriate permissions)
- Service workers are the preferred approach for new extensions
- Background scripts are loaded when the extension starts and handle extension lifecycle events
- Can communicate with content scripts via message passing
- Useful for handling browser events, network requests, and maintaining extension state

## Implementation Notes
- This WebExtensions framework implements background scripts as native Swift services
- Avoids WKWebView limitations by running background logic in native code
- Provides 10x faster API calls compared to JavaScript service workers
- Always-on background processing without service worker idle timeouts

## Sources
- https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/background