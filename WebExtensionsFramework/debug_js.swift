#!/usr/bin/env swift

import Foundation

// Add the current directory to the module search path
import BrowserExtensionShared

let result = generatedAPIJavascript(.init(extensionId: "test-id"))
print("Generated JS length: \(result.count)")
print("Generated JS:")
print(result)