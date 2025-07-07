import Foundation
import BrowserExtensionShared

if CommandLine.arguments.contains("--dumpjs") {
    // To see the JS we would generate run:
    // swift run APIGenerator -- --dumpjs
    print(generatedAPIJavascript(.init(extensionId: "extension id goes here")))
} else {
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
        let outputPath = "Sources/BrowserExtensionDispatcher.swift"
        try content.write(toFile: outputPath, atomically: true, encoding: .utf8)
        print("Successfully generated \(outputPath)")
    } catch {
        print("Error writing to file: \(error)")
        exit(1)
    }

}
