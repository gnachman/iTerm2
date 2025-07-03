# WebExtensions Framework

A native Swift framework for implementing WebExtensions API support in macOS browsers.

## Project Structure

```
WebExtensionsFramework/
├── Package.swift                           # Swift Package Manager configuration
├── Sources/
│   └── WebExtensionsFramework/            # Framework source code
│       └── WebExtensionsFramework.swift   # Main framework entry point
└── Tests/
    └── WebExtensionsFrameworkTests/       # Unit tests
        └── WebExtensionsFrameworkTests.swift
```

## Requirements

- macOS 14.0+ (required for proxy support)
- Swift 5.9+

## Building and Testing

```bash
# Build the framework
swift build

# Run tests
swift test

# Run tests with verbose output
swift test --verbose
```

## Development Approach

We're using test-driven development (TDD):
1. Write tests for each class first
2. Implement the class to make tests pass
3. Refactor and improve

## Current Status

✅ Swift Package Manager setup complete
✅ Basic framework structure created
✅ Initial tests passing

## Next Steps

Implementing classes in order:
1. ExtensionManifest (struct)
2. ManifestParser 
3. Extension
4. ExtensionRegistry
5. ContentWorldManager
6. ContentScriptInjector
7. ExtensionNavigationHandler