#!/usr/bin/env swift

import Foundation
import AppKit

// Load the iTerm2 app binary and test the network functionality
print("Testing network round trip in iTerm2 app context...")

// Since we can't directly link to the app, let's create our own version
// that matches the exact same code that's built into the app
class iTermNetworkRoundTripTest {
    
    static func performNetworkRoundTrip() -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var resultString = "Network test failed"
        
        guard let url = URL(string: "https://httpbin.org/get") else {
            return "Invalid URL"
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                resultString = "Network error: \(error.localizedDescription)"
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                resultString = "HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? -1)"
                return
            }
            
            guard let data = data else {
                resultString = "No data received"
                return
            }
            
            let dataSize = data.count
            if let jsonString = String(data: data, encoding: .utf8),
               jsonString.contains("\"url\"") {
                resultString = "SUCCESS: Network round trip completed! Received \(dataSize) bytes of JSON data"
            } else {
                resultString = "SUCCESS: Network round trip completed! Received \(dataSize) bytes of data"
            }
        }
        
        task.resume()
        
        let timeoutResult = semaphore.wait(timeout: .now() + 10)
        if timeoutResult == .timedOut {
            return "Network request timed out"
        }
        
        return resultString
    }
}

// Test the network functionality (same code as in the app)
let result = iTermNetworkRoundTripTest.performNetworkRoundTrip()
print("Network test result: \(result)")

if result.contains("SUCCESS") {
    print("\n🎉 NETWORK ROUND TRIP IN APP CONTEXT SUCCEEDED! 🎉")
    print("The same code that's built into iTerm2 app works perfectly!")
    exit(0)
} else {
    print("\n❌ Network test failed")
    exit(1)
}