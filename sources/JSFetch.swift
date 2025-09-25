//
//  JSFetch.swift
//  iTerm2
//
//  Created by George Nachman on 6/1/24.
//

import Foundation
import JavaScriptCore

class PluginClient {
    static let instance = PluginClient()
    private var session: URLSession?
    private let task = MutableAtomicObject<URLSessionDataTask?>(nil)

    private class HTTPStreamDelegate: NSObject, URLSessionDataDelegate {
        var receivedData = Data()
        // First argument is content (streaming update or document body)
        // Second argument is nil for streaming updates. Otherwise, it will be an empty string on success or an error message otherwise.
        let callback: (String, String?) -> Void
        var streaming = false

        init(callback: @escaping (String?, String?) -> Void) {
            self.callback = callback
        }

        deinit {
            DLog("HTTPStreamDelegate \(it_addressString): Deinit")
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            // Handle the response here if needed, and decide how to proceed
            completionHandler(.allow) // Allow to continue receiving data
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            DLog("HTTP append data")
            DLog("HTTPStreamDelegate \(it_addressString): append")
            for line in data.lossyString.components(separatedBy: "\n") {
                DLog(line)
            }
            DLog("---end---")
            receivedData.append(data)
            if streaming, let chunk = String(data: data, encoding: .utf8) {
                // Immediately send the chunk down the pipeline.
                callback(chunk, nil)
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            DLog("HTTPStreamDelegate \(it_addressString): complete. error=\(error.d)")
            if let error = error {
                DLog("URLSession error: \(error)")
                callback(receivedData.lossyString, "HTTP request failed with \(error.localizedDescription)")
            } else if let httpResponse = task.response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                DLog("Got response\n\(httpResponse.statusCode)\n\(httpResponse.allHeaderFields)\n\n\(receivedData.lossyString)\n\n")
                callback(receivedData.lossyString,
                         "HTTP request failed with status \(httpResponse.statusCode).")
            } else {
                DLog("Read \(receivedData.lossyString)")
                callback(receivedData.lossyString, "")
            }
        }
    }

    func cancel() {
        task.mutableAccess { currentTask in
            currentTask?.cancel()
            currentTask = nil
        }
    }

    func call<RequestType: Codable & CustomDebugStringConvertible,
              ResponseType: Codable>(code: String,
                                     functionName: String,
                                     request: RequestType?,
                                     async: Bool,
                                     stream: ((String) -> ())?) throws -> ResponseType {
        DLog("Call \(functionName) with \(request?.debugDescription ?? "(nil)"), async=\(async)")
        let args: [String]
        if let request {
            let jsonData: Data
            do {
                jsonData = try JSONEncoder().encode(request)
            } catch {
                throw PluginError(reason: "Could not encode request to plugin: \(error)")
            }
            let jsonString = String(data: jsonData, encoding: .utf8)!
            args = [jsonString]
        } else {
            args = []
        }
        do {
            if async {
                return try callAsync(code: code, functionName: functionName, arguments: args, stream: stream)
            } else {
                return try callSync(code: code, functionName: functionName, arguments: args, stream: stream)
            }
        } catch {
            DLog(error.localizedDescription)
            throw error
        }
    }

    private func performHTTPRequest(method: String,
                                    url: String,
                                    headers: [String: String],
                                    body: Data,
                                    streaming: Bool,
                                    callback: @escaping (String?, String?) -> Void) {
        DLog("performHTTPRequest(\(method), \(url), \(headers), \(body.lossyString), \(streaming)")
        guard let url = URL(string: url) else {
            DLog("Invalid url \(url)")
            callback(nil, "Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        if !body.isEmpty {
            let data = body
            request.httpBodyStream = InputStream(data: data)
            request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = iTermPreferences.double(forKey: kPreferenceKeyAITimeout)
        config.timeoutIntervalForResource =  iTermPreferences.double(forKey: kPreferenceKeyAITimeout)
        let delegate = HTTPStreamDelegate { [weak self] first, second in
            if second != nil {
                self?.task.mutableAccess { currentTask in
                    currentTask = nil
                }
            }
            callback(first, second)
        }
        let proxyString = iTermAdvancedSettingsModel.aiProxy()
        if let proxyString, !proxyString.isEmpty {
            let parts = proxyString.split(separator: ":", maxSplits: 1)
            if parts.count == 2, let port = Int(parts[1]) {
                let host = String(parts[0])
                config.connectionProxyDictionary = [
                    kCFNetworkProxiesHTTPSEnable as String: true,
                    kCFNetworkProxiesHTTPSProxy as String: host,
                    kCFNetworkProxiesHTTPSPort as String: port
                ]
            }
        }

        delegate.streaming = streaming
        DLog("Request with delegate \(delegate.it_addressString):\n\(body)")
        session = URLSession(configuration: config,
                             delegate: delegate,
                             delegateQueue: nil)
        let newTask = session?.dataTask(with: request)
        task.mutableAccess { currentTask in
            currentTask = newTask
        }
        DLog("resume session")
        newTask?.resume()
    }

    private func registerFunctions(context: JSContext, stream: ((String) -> ())?) {
        DLog("registerFunctions")
        let performRequest: @convention(block) (String, String, [String: String], Any, JSValue) -> Void = { [weak self]
            method, url, headers, body, callback in
            guard let self else {
                let noError: String? = nil
                callback.call(withArguments: [noError as Any, "Plugin client deallocated"])
                return
            }
            let bodyData: Data? = switch body {
            case let string as String:
                string.lossyData
            case let byteArray as [NSNumber]:
                Data(byteArray.map { UInt8(truncating: $0) })
            default:
                nil
            }
            guard let bodyData else {
                let noError: String? = nil
                callback.call(withArguments: [noError as Any, "Invalid body"])
                return
            }
            self.performHTTPRequest(method: method,
                                    url: url,
                                    headers: headers,
                                    body: bodyData,
                                    streaming: stream != nil) { string, error in
                if error == nil, let string, stream != nil {
                    if let streamCallback = context.objectForKeyedSubscript("onStream"), !streamCallback.isUndefined {
                        streamCallback.call(withArguments: [string as Any])
                    }
                    return
                }
                let callbackArguments = [string as Any, error as Any]
                callback.call(withArguments: callbackArguments)
            }
        }
        context.setObject(performRequest, forKeyedSubscript: "performHTTPRequest" as (NSCopying & NSObjectProtocol))

        if let stream {
            let streamFunction: @convention(block) (String) -> Void = { string in
                DispatchQueue.main.async {
                    stream(string)
                }
            }
            context.setObject(streamFunction, forKeyedSubscript: "onStream" as (NSCopying & NSObjectProtocol))
        }
        let logMessage: @convention(block) (JSValue) -> Void = { message in
            DLog("JS: \(message.toString() ?? "(nil)")")
        }
        context.setObject(logMessage, forKeyedSubscript: "log" as (NSCopying & NSObjectProtocol))
    }

    private func callSync<ResponseType: Codable>(code: String,
                                                 functionName: String,
                                                 arguments: [String],
                                                 stream: ((String) -> ())?) throws -> ResponseType {
        DLog("callSync \(functionName)")
        // Create a JSContext
        guard let context = JSContext() else {
            throw PluginError(reason: "Could not create context for plugin")
        }
        registerFunctions(context: context, stream: stream)
        context.evaluateScript(code)
        var exc: String?
        context.exceptionHandler = { context, exception in
            DLog("JS EXCEPTION: \(exception?.toString() ?? "nil exception")")
            exc = exception?.toString()
        }
        if let exc {
            throw PluginError(reason: "Javascript exception: \(exc)")
        }

        // Call the JavaScript function with the JSON string
        let result = context.objectForKeyedSubscript(functionName).call(withArguments: arguments)
        guard let result else {
            throw PluginError(reason: "Plugin unexpectedly returned null")
        }
        // Get JSON string from result
        guard let jsonResponse = result.toString() else {
            throw PluginError(reason: "Unexpected output from plugin: \(result)")
        }
        // Convert JSON string back to WebResponse
        guard let responseData = jsonResponse.data(using: .utf8) else {
            throw PluginError(reason: "Non-UTF-8 result from plugin: \(jsonResponse)")
        }
        do {
            return try JSONDecoder().decode(ResponseType.self, from: responseData)
        } catch {
            throw PluginError(reason: "Error running plugin: \(error)")
        }
    }

    private func callAsync<ResponseType: Codable>(code: String,
                                                  functionName: String,
                                                  arguments: [String],
                                                  stream: ((String) -> ())?) throws -> ResponseType {
        DLog("callAsync \(functionName)")
        // Create a JSContext
        guard let context = JSContext() else {
            throw PluginError(reason: "Could not create context for plugin")
        }

        // Register performHTTPRequest or any other required function
        registerFunctions(context: context, stream: stream)

        // Handle JavaScript errors
        context.exceptionHandler = { context, exception in
            DLog("JS Error: \(exception?.toString() ?? "unknown error")")
        }

        // Evaluate the provided JavaScript code
        context.evaluateScript(code)

        // Retrieve the JavaScript function
        guard let function = context.objectForKeyedSubscript(functionName) else {
            throw PluginError(reason: "Function \(functionName) not found")
        }

        // Call the JavaScript function which returns a Promise
        DLog("Call with arguments: \(arguments)")
        guard let result = function.call(withArguments: arguments) else {
            throw PluginError(reason: "JavaScript function call failed")
        }

        // Initialize semaphore for waiting on the asynchronous JavaScript call
        let semaphore = DispatchSemaphore(value: 0)
        var response: ResponseType?
        var error: Error?

        let handleWebResponse = { responseBody in
            guard let jsonResponse = JSValue(object: responseBody, in: context).toString() else {
                error = PluginError(reason: "Unexpected output from plugin")
                semaphore.signal()
                return
            }
            do {
                if let responseData = jsonResponse.data(using: .utf8) {
                    response = try JSONDecoder().decode(ResponseType.self, from: responseData)
                } else {
                    error = PluginError(reason: "Non-UTF-8 result from plugin: \(jsonResponse)")
                }
            } catch let decodeError {
                DLog("Response is:")
                DLog(jsonResponse)
                error = PluginError(reason: "Error decoding response: \(decodeError)")
            }
            semaphore.signal()
        }
        // Prepare to handle the promise
        let thenClosure: @convention(block) (Any?) -> Void = { responseBody in
            handleWebResponse(responseBody)
        }

        let catchClosure: @convention(block) (Any?) -> Void = { responseBody in
            handleWebResponse(responseBody)
        }

        // Handle the promise returned by the JavaScript function
        result.invokeMethod("then", withArguments: [JSValue(object: thenClosure, in: context)!])
        result.invokeMethod("catch", withArguments: [JSValue(object: catchClosure, in: context)!])

        DLog("wait for completion")
        // Wait for the semaphore
        semaphore.wait()

        DLog("API call complete")
        // Return the response or throw the captured error
        if let response = response {
            return response
        } else if let error = error {
            throw error
        } else {
            throw PluginError(reason: "Unknown error occurred")
        }
    }
}


extension Optional where Wrapped: Error {
    var d: String {
        switch self {
        case .none:
            "(nil)"
        case .some(let error):
            error.localizedDescription
        }
    }
}
