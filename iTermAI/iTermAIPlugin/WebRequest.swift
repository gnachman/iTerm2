//
//  WebRequest.swift
//  iTermAIPlugin
//
//  Created by George Nachman on 5/22/24.
//

import Foundation

struct WebRequest: Codable {
    var headers: [String: String]
    var method: String
    var body: Data?
    var url: String
}

struct WebResponse: Codable {
    var data: Data
    var error: String?
}
