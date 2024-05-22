//
//  main.swift
//  iTermAIPlugin
//
//  Created by George Nachman on 5/22/24.
//

import Foundation

func readRequest() throws -> WebRequest {
    let stdin = FileHandle.standardInput
    let inputData = stdin.readDataToEndOfFile()

    let decoder = JSONDecoder()
    return try decoder.decode(WebRequest.self, from: inputData)
}

func makeHTTPRequest(_ webRequest: WebRequest,
                     completion: @escaping (WebResponse) -> ()) {
    guard let url = URL(string: webRequest.url) else {
        completion(WebResponse(data: Data(),
                               error: "Bad url \(webRequest.url)"))
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = webRequest.method
    request.httpBody = webRequest.body
    webRequest.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

    let session = URLSession.shared
    let task = session.dataTask(with: request) { data, response, error in
        if let error = error {
            completion(WebResponse(data: Data(), error: error.localizedDescription))
            return
        }

        let responseData = data ?? Data()
        completion(WebResponse(data: responseData, error: nil))
    }
    task.resume()
}

func run(_ completion: @escaping (WebResponse) -> ()) {
    let request: WebRequest
    do {
        request = try readRequest()
    } catch {
        let response = WebResponse(data: Data(),
                                   error: "While reading request: \(error.localizedDescription)")
        completion(response)
        return
    }

    makeHTTPRequest(request, completion: completion)
}

func doWebRequest() {
    let sema = DispatchSemaphore(value: 0)
    run { response in
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(response)
            if let string = String(data: data, encoding: .utf8) {
                print(string)
                exit(0)
            } else {
                print(#"{ "data": "", "error": "UTF-8 Encoding failed"}"#)
                exit(1)
            }
        } catch {
            print(#"{ "data": "", "error": "JSON Encoding failed"}"#)
            exit(1)
        }
    }
    sema.wait()
}

func doVersion() {
    print("1")
    exit(0)
}

if CommandLine.arguments.count != 2 {
    print("missing argument")
    exit(1)
}
let command = CommandLine.arguments[1]
switch command {
case "request":
    doWebRequest()
case "v":
    doVersion()
default:
    print("Unknown command")
    exit(1)
}
