#!/usr/bin/env swift 
import Foundation

func parseMimeTypes() {
    guard let url = URL(string: "https://raw.githubusercontent.com/apache/httpd/refs/heads/trunk/docs/conf/mime.types") else {
        print("Invalid URL")
        return
    }
    
    let task = URLSession.shared.dataTask(with: url) { data, response, error in
        if let error = error {
            print("Error fetching data: \(error)")
            return
        }
        
        guard let data = data,
              let content = String(data: data, encoding: .utf8) else {
            print("Failed to convert data to string")
            return
        }
        
        var mimeTypesDict: [String: String] = [:]
        
        // Split into lines and process each one
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }
            
            // Split by whitespace (tabs/spaces)
            let components = trimmedLine.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            
            // Need at least mime type and one extension
            if components.count >= 2 {
                let mimeType = components[0]
                let extensions = Array(components[1...])
                
                // Add each extension to the dictionary
                for ext in extensions {
                    mimeTypesDict[ext] = mimeType
                }
            }
        }
        
        // Output as Swift dictionary format
        print("let mimeTypes: [String: String] = [")
        
        // Sort keys for consistent output
        let sortedKeys = mimeTypesDict.keys.sorted()
        
        for (index, key) in sortedKeys.enumerated() {
            let value = mimeTypesDict[key]!
            let comma = index < sortedKeys.count - 1 ? "," : ""
            print("    \"\(key)\": \"\(value)\"\(comma)")
        }
        
        print("]")
        
        print("\n// Total extensions: \(mimeTypesDict.count)")
        
        // Exit the program
        exit(0)
    }
    
    task.resume()
    
    // Keep the main thread alive
    RunLoop.main.run()
}

// Run the parser
parseMimeTypes()
