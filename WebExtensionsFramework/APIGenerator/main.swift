import Foundation
import BrowserExtensionShared

// Generate the API protocols
do {
    let content = generatedAPISwift()
    let outputPath = "Sources/BrowserExtensionAPIProtocols.swift"
    try content.write(toFile: outputPath, atomically: true, encoding: .utf8)
    print("Successfully generated \(outputPath)")
} catch {
    print("Error writing to file: \(error)")
    exit(1)
}

// Generate the dispatch function
do {
    let content = generatedDispatchSwift()
    let outputPath = "Sources/BrowserExtensionAPIDispatch.swift"
    try content.write(toFile: outputPath, atomically: true, encoding: .utf8)
    print("Successfully generated \(outputPath)")
} catch {
    print("Error writing to file: \(error)")
    exit(1)
}


