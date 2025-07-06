# Browser Extension Error Handling Design

## Overview

This document outlines the design for error handling in the WebExtensions framework, based on Firefox's implementation patterns. The system must handle both synchronous and asynchronous errors, provide clear error messages, and maintain compatibility with the Chrome Extensions API.

## Key Requirements

1. **Chrome API Compatibility**: Errors must be reported via `chrome.runtime.lastError` for callback-based APIs
2. **Browser API Compatibility**: Promise-based APIs should reject with appropriate errors
3. **Parameter Validation**: Detect and report incorrect argument counts and types
4. **Serialization Safety**: Detect non-serializable values before attempting to pass them
5. **Security**: Sanitize error information when crossing process boundaries
6. **Developer Experience**: Provide clear error messages and warn about unchecked errors

## Error Types

### 1. JavaScript Standard Errors

#### TypeError
Thrown when:
- Wrong type of argument is passed
- Attempting to access properties on null/undefined
- Calling non-callable values

Examples:
```javascript
chrome.runtime.sendMessage(null); // TypeError: Argument 1 is not valid
chrome.runtime.sendMessage(123, "not-a-function"); // TypeError: Argument 2 must be a function
```

#### DataCloneError (DOMException)
Thrown when:
- Attempting to pass non-serializable values through message passing
- Objects with circular references
- DOM nodes, functions, symbols, or other non-cloneable types

Examples:
```javascript
chrome.runtime.sendMessage(window.location); // DataCloneError: Location object could not be cloned
chrome.runtime.sendMessage(() => {}); // DataCloneError: Function object could not be cloned
```

### 2. Extension-Specific Errors

#### Runtime Errors
- `Could not establish connection. Receiving end does not exist.`
- `The message port closed before a response was received.`
- `Extension context invalidated.`

#### Permission Errors
- `Missing required permission: <permission>`

## API Behavior Patterns

### 1. sendMessage Behavior

#### With Callback (Chrome API style)
```javascript
chrome.runtime.sendMessage(message, function(response) {
    if (chrome.runtime.lastError) {
        // Error available here
    }
    // response may be undefined if error occurred
});
```

#### Without Callback (Browser API style)
```javascript
// Returns a Promise
browser.runtime.sendMessage(message)
    .then(response => {
        // Success
    })
    .catch(error => {
        // Error is thrown/rejected, NOT in lastError
    });
```

#### Special Cases for sendMessage
- Supports multiple argument signatures
- Can return a Promise if no callback provided
- Handles extensionId as optional first parameter
- Options object as optional parameter

### 2. Other Runtime Methods

#### getPlatformInfo
- Simple async method with single callback
- No special argument parsing
- Returns fixed structure

```javascript
chrome.runtime.getPlatformInfo(function(info) {
    if (chrome.runtime.lastError) {
        // Unlikely but possible
    }
    // info contains {os, arch, nacl_arch}
});
```

#### getManifest
- Synchronous method
- No callback or promise
- No error handling needed

```javascript
const manifest = chrome.runtime.getManifest(); // Direct return
```

#### connect/connectNative
- Returns Port object immediately
- Errors occur on port operations
- Port has its own error events

```javascript
const port = chrome.runtime.connect();
port.onDisconnect.addListener(() => {
    if (chrome.runtime.lastError) {
        // Connection error
    }
});
```

## Error Handling Implementation

### 1. JavaScript Error Detection

```javascript
// Argument validation with proper TypeError
function validateSendMessageArgs(args) {
    if (args.length === 0) {
        throw new TypeError("At least 1 argument required, but only 0 passed");
    }
    
    const lastArg = args[args.length - 1];
    const hasCallback = typeof lastArg === 'function';
    
    // Parse based on argument count and types
    let extensionId, message, options, callback;
    
    // Validation logic...
    
    if (message === null || message === undefined) {
        throw new TypeError("Argument 1 is not valid");
    }
    
    if (hasCallback && typeof callback !== 'function') {
        throw new TypeError(`Argument ${args.length} must be a function`);
    }
    
    return { extensionId, message, options, callback };
}
```

### 2. Serialization Validation

```javascript
// Check if value can be structured cloned
function canBeCloned(value) {
    try {
        // Use structured clone algorithm check
        if (value === null || value === undefined) return true;
        if (typeof value === 'boolean' || typeof value === 'number' || typeof value === 'string') return true;
        if (value instanceof Date || value instanceof RegExp) return true;
        if (value instanceof ArrayBuffer || ArrayBuffer.isView(value)) return true;
        
        // Check for non-cloneable types
        if (typeof value === 'function') {
            throw new DOMException('Function object could not be cloned.', 'DataCloneError');
        }
        if (typeof value === 'symbol') {
            throw new DOMException('Symbol object could not be cloned.', 'DataCloneError');
        }
        if (value instanceof Node) {
            throw new DOMException('DOM object could not be cloned.', 'DataCloneError');
        }
        if (value instanceof Window || value instanceof Location) {
            throw new DOMException(`${value.constructor.name} object could not be cloned.`, 'DataCloneError');
        }
        
        // Recursively check object properties
        if (typeof value === 'object') {
            const seen = new WeakSet();
            return checkObject(value, seen);
        }
        
        return true;
    } catch (e) {
        throw e;
    }
}
```

### 3. Promise vs Callback Handling

```javascript
function sendMessage(...args) {
    try {
        const { extensionId, message, options, callback } = validateSendMessageArgs(args);
        
        // Validate message can be cloned
        canBeCloned(message);
        
        if (callback) {
            // Chrome API style - use callback with lastError
            performSendMessage(extensionId, message, options, (response, error) => {
                if (error) {
                    injectLastError(error, callback, response);
                } else {
                    callback(response);
                }
            });
        } else {
            // Browser API style - return Promise
            return new Promise((resolve, reject) => {
                performSendMessage(extensionId, message, options, (response, error) => {
                    if (error) {
                        reject(error);
                    } else {
                        resolve(response);
                    }
                });
            });
        }
    } catch (e) {
        if (callback) {
            // Async error via lastError
            setTimeout(() => injectLastError(e, callback), 0);
        } else {
            // Sync error via rejected Promise
            return Promise.reject(e);
        }
    }
}
```

### 4. lastError Injection

```javascript
function injectLastError(error, callback, response) {
    const context = {
        lastError: normalizeError(error),
        checked: false
    };
    
    // Temporarily override lastError
    const descriptor = Object.getOwnPropertyDescriptor(chrome.runtime, 'lastError');
    Object.defineProperty(chrome.runtime, 'lastError', {
        get() {
            context.checked = true;
            return context.lastError;
        },
        configurable: true
    });
    
    try {
        callback(response);
    } finally {
        // Restore original descriptor
        if (descriptor) {
            Object.defineProperty(chrome.runtime, 'lastError', descriptor);
        } else {
            delete chrome.runtime.lastError;
        }
        
        // Warn if unchecked
        if (!context.checked && context.lastError) {
            console.warn('Unchecked runtime.lastError:', context.lastError.message);
        }
    }
}
```

## Error Response Format

### Success Response
```json
{
    "result": 0,
    "data": { /* actual response data */ }
}
```

### Error Response
```json
{
    "result": 4,
    "error": {
        "message": "Could not establish connection. Receiving end does not exist.",
        "type": "RuntimeError",
        "stack": "...",
        "fileName": "...",
        "lineNumber": 42
    }
}
```

## Swift Implementation

### Error Types
```swift
enum BrowserExtensionError: Error {
    // Type errors
    case invalidArgumentType(position: Int, expected: String, actual: String)
    case missingRequiredArgument(position: Int)
    case tooManyArguments(expected: Int, actual: Int)
    
    // Data clone errors
    case dataCloneError(type: String)
    case circularReference
    
    // Runtime errors
    case noMessageReceiver
    case connectionClosed
    case extensionContextInvalidated
    
    // Generic
    case unknownError(String)
}
```

### Type Validation
```swift
protocol ArgumentValidator {
    func validate(_ args: [Any]) throws -> ParsedArguments
}

struct SendMessageValidator: ArgumentValidator {
    func validate(_ args: [Any]) throws -> ParsedArguments {
        guard args.count >= 1 else {
            throw BrowserExtensionError.missingRequiredArgument(position: 1)
        }
        
        // Type checking logic...
    }
}
```

## Testing Strategy

### Error Type Tests
1. **TypeError Tests**
   - Wrong argument types
   - Missing required arguments
   - Non-function callbacks

2. **DataCloneError Tests**
   - Functions
   - DOM nodes
   - Circular references
   - Symbols
   - Native objects (Location, Window)

3. **Runtime Error Tests**
   - No listener registered
   - Extension context invalidated
   - Port disconnected

### Promise vs Callback Tests
1. **Promise Rejection**
   - Verify errors reject the promise
   - No lastError set

2. **Callback with lastError**
   - Verify lastError is set
   - Verify unchecked warning

### Method-Specific Tests
1. **sendMessage**
   - All argument combinations
   - Promise/callback modes
   
2. **getPlatformInfo**
   - Simple success case
   - Error handling

3. **connect**
   - Port error events
   - Disconnection handling

## Security Considerations

1. **Error Message Sanitization**
   - Remove file paths from production
   - Limit stack trace information
   - No internal state exposure

2. **Cross-Context Safety**
   - Errors must be serializable
   - No reference leaks

## Implementation Phases

### Phase 1: Core Error Types
- JavaScript error types (TypeError, DataCloneError)
- Swift error enumeration
- Error serialization

### Phase 2: Argument Validation
- sendMessage parser
- Type validators
- Serialization checks

### Phase 3: Promise/Callback Handling
- Dual-mode support for sendMessage
- lastError injection
- Unchecked warnings

### Phase 4: Method Implementation
- Update all runtime methods
- Add appropriate error handling
- Comprehensive testing