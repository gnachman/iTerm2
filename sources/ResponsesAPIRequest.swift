//
//  ResponsesAPIRequest.swift
//  iTerm2
//
//  Created by George Nachman on 5/29/25.
//

import Foundation

/// A full‐featured request to OpenAI’s Responses API.
public struct ResponsesRequestBody: Codable {
    enum InputItemContent: Codable {
        struct InputText: Codable {
            var type = "input_text"
            var text: String
        }
        case inputText(InputText)

        struct InputImage: Codable {
            enum Detail: String, Codable {
                case low
                case high
                case auto
            }
            var detail: Detail
            var type = "input_image"
            var fileID: String?
            var imageURL: String?
            private enum CodingKeys: String, CodingKey {
                case detail
                case type
                case fileID = "file_id"
                case imageURL = "image_url"
            }
        }
        case inputImage(InputImage)

        struct InputFile: Codable {
            var type = "input_file"
            var fileData: String?
            var fileID: String?
            var filename: String?

            private enum CodingKeys: String, CodingKey {
                case type
                case fileData = "file_data"
                case fileID = "file_id"
                case filename
            }
        }
        case inputFile(InputFile)

        private enum CodingKeys: String, CodingKey {
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "input_text":
                let inputText = try InputText(from: decoder)
                self = .inputText(inputText)
            case "input_image":
                let inputImage = try InputImage(from: decoder)
                self = .inputImage(inputImage)
            case "input_file":
                let inputFile = try InputFile(from: decoder)
                self = .inputFile(inputFile)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown InputItemContent type: \(type)"
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .inputText(let inputText):
                try inputText.encode(to: encoder)
            case .inputImage(let inputImage):
                try inputImage.encode(to: encoder)
            case .inputFile(let inputFile):
                try inputFile.encode(to: encoder)
            }
        }
    }

    /// Text, image, or file inputs to the model, used to generate a response.
    enum Input: Codable {
        enum ItemListEntry: Codable {
            struct Message: Codable {
                enum Content: Codable {
                    case text(String)
                    case inputItemContentList([InputItemContent])
                    private enum CodingKeys: String, CodingKey {
                        case text
                        case inputItemContentList = "input_item_content_list"
                    }

                    init(from decoder: Decoder) throws {
                        // Try to decode as a string first
                        if let stringValue = try? decoder.singleValueContainer().decode(String.self) {
                            self = .text(stringValue)
                            return
                        }

                        // Try to decode as an array
                        if let arrayValue = try? decoder.singleValueContainer().decode([InputItemContent].self) {
                            self = .inputItemContentList(arrayValue)
                            return
                        }

                        throw DecodingError.dataCorrupted(
                            DecodingError.Context(
                                codingPath: decoder.codingPath,
                                debugDescription: "Cannot decode Content - expected String or [InputItemContent]"
                            )
                        )
                    }

                    func encode(to encoder: Encoder) throws {
                        var container = encoder.singleValueContainer()

                        switch self {
                        case .text(let stringValue):
                            try container.encode(stringValue)
                        case .inputItemContentList(let arrayValue):
                            try container.encode(arrayValue)
                        }
                    }
                }
                var content: Content

                enum Role: String, Codable {
                    case user
                    case assistant
                    case system
                    case developer
                }
                var role: Role
                var type = "message"
            } // Message
            case message(Message)

            enum Item: Codable {
                enum Status: String, Codable {
                    case inProgress = "in_progress"
                    case completed
                    case incomplete
                }

                struct InputMessage: Codable {
                    var content: [InputItemContent]
                    enum Role: String, Codable {
                        case user
                        case system
                        case developer
                    }
                    var role: Role
                    var status: Status?
                    var type = "message"
                }
                case inputMessage(InputMessage)

                struct OutputMessage: Codable {
                    enum OutputItemContent: Codable {
                        struct OutputText: Codable {
                            enum Annotation: Codable {
                                struct FileCitation: Codable {
                                    var fileID: String
                                    var index: Int
                                    var type = "file_citation"
                                    private enum CodingKeys: String, CodingKey {
                                        case fileID = "file_id"
                                        case index
                                        case type
                                    }
                                }
                                case fileCitation(FileCitation)

                                struct URLCitation: Codable {
                                    var endIndex: Int
                                    var startIndex: Int
                                    var title: String
                                    var type = "url_citation"
                                    var url: String

                                    private enum CodingKeys: String, CodingKey {
                                        case endIndex = "end_index"
                                        case startIndex = "start_index"
                                        case title
                                        case type
                                        case url
                                    }
                                }
                                case urlCitation(URLCitation)

                                struct FilePath: Codable {
                                    var fileID: String
                                    var index: Int
                                    var type = "file_path"
                                    private enum CodingKeys: String, CodingKey {
                                        case fileID = "file_id"
                                        case index
                                        case type
                                    }
                                }
                                case filePath(FilePath)

                                private enum CodingKeys: String, CodingKey { case type }

                                init(from decoder: Decoder) throws {
                                    let c = try decoder.container(keyedBy: CodingKeys.self)
                                    let t = try c.decode(String.self, forKey: .type)
                                    switch t {
                                    case "file_citation":
                                        self = .fileCitation(try FileCitation(from: decoder))
                                    case "url_citation":
                                        self = .urlCitation(try URLCitation(from: decoder))
                                    case "file_path":
                                        self = .filePath(try FilePath(from: decoder))
                                    default:
                                        throw DecodingError.dataCorruptedError(
                                            forKey: .type,
                                            in: c,
                                            debugDescription: "Unknown Annotation type: \(t)"
                                        )
                                    }
                                }

                                func encode(to encoder: Encoder) throws {
                                    switch self {
                                    case .fileCitation(let f):
                                        try f.encode(to: encoder)
                                    case .urlCitation(let u):
                                        try u.encode(to: encoder)
                                    case .filePath(let p):
                                        try p.encode(to: encoder)
                                    }
                                }
                            }
                            var annotations: [Annotation]
                            var text: String
                            var type = "output_text"
                            // logprobs omitted
                        }
                        case outputText(OutputText)

                        struct Refusal: Codable {
                            var refusal: String
                            var type = "refusal"
                        }
                        case refusal(Refusal)

                        private enum CodingKeys: String, CodingKey {
                            case type
                        }

                        init(from decoder: Decoder) throws {
                            let c = try decoder.container(keyedBy: CodingKeys.self)
                            let t = try c.decode(String.self, forKey: .type)
                            if t == "output_text" {
                                self = .outputText(try OutputText(from: decoder))
                                return
                            }
                            if t == "refusal" {
                                self = .refusal(try Refusal(from: decoder))
                                return
                            }
                            throw DecodingError.dataCorruptedError(
                                forKey: .type,
                                in: c,
                                debugDescription: "Unknown OutputItemContent type: \(t)"
                            )
                        }

                        func encode(to encoder: Encoder) throws {
                            switch self {
                            case .outputText(let o):
                                try o.encode(to: encoder)
                            case .refusal(let r):
                                try r.encode(to: encoder)
                            }
                        }
                    }
                    var content: [OutputItemContent]
                    var id: String
                    var role = "assistant"
                    var status: Status
                    var type = "message"
                }
                case outputMessage(OutputMessage)

                struct FileSearchToolCall: Codable {
                    var id: String
                    var queries: [String]
                    enum Status: String, Codable {
                        case inProgress = "in_progress"
                        case searching
                        case incomplete
                        case failed
                    }
                    var type = "file_search_call"
                    struct Result: Codable {
                        var attributes: [String: String]?
                        var fileID: String?
                        var filename: String?
                        var score: Double?
                        var text: String?

                        private enum CodingKeys: String, CodingKey {
                            case fileID = "file_id"
                            case attributes, filename, score, text
                        }
                    }
                }
                case fileSearchToolCall(FileSearchToolCall)

                struct ComputerToolCall: Codable {
                    var id: String
                    var type = "computer_use_call"

                    struct Input: Codable {
                        var action: String
                        var coordinate: [Int]?
                        var text: String?

                        private enum CodingKeys: String, CodingKey {
                            case action
                            case coordinate
                            case text
                        }
                    }
                    var input: Input

                    enum Status: String, Codable {
                        case inProgress = "in_progress"
                        case completed
                        case incomplete
                        case failed
                    }
                    var status: Status?

                    private enum CodingKeys: String, CodingKey {
                        case id
                        case type
                        case input
                        case status
                    }
                }
                case computerToolCall(ComputerToolCall)

                struct ComputerToolCallOutput: Codable {
                    var id: String
                    var type = "computer_use_call_output"

                    struct Output: Codable {
                        var text: String?
                        var imageURL: String?
                        var error: String?

                        private enum CodingKeys: String, CodingKey {
                            case text
                            case imageURL = "image_url"
                            case error
                        }
                    }
                    var output: Output

                    enum Status: String, Codable {
                        case inProgress = "in_progress"
                        case completed
                        case incomplete
                        case failed
                    }
                    var status: Status?

                    private enum CodingKeys: String, CodingKey {
                        case id
                        case type
                        case output
                        case status
                    }
                }
                case computerToolCallOutput(ComputerToolCallOutput)

                struct WebSearchToolCall: Codable {
                    var id: String
                    var status: String
                    var type = "web_search_call"
                }
                case webSearchToolCall(WebSearchToolCall)

                struct FunctionToolCall: Codable {
                    var arguments: String
                    var callID: String
                    var name: String
                    var type = "function_call"
                    var id: String?
                    enum Status: String, Codable {
                        case in_progress, completed, incomplete
                    }
                    var status: Status?

                    private enum CodingKeys: String, CodingKey {
                        case arguments, name, type, id, status
                        case callID = "call_id"
                    }
                }
                case functionToolCall(FunctionToolCall)

                struct FunctionToolCallOutput: Codable {
                    /// The unique ID of the function tool call generated by the model.
                    var callID: String

                    /// The unique ID of the function call tool output.
                    var id: String?

                    /// A JSON string of the output of the function tool call.
                    var output: String

                    var type = "function_call_output"

                    enum Status: String, Codable {
                        case in_progress, completed, incomplete
                    }
                    var status: Status?

                    private enum CodingKeys: String, CodingKey {
                        case callID = "call_id"
                        case output, type, id, status
                    }
                }
                case functionToolCallOutput(FunctionToolCallOutput)

                struct Reasoning: Codable {
                    var id: String
                    struct Summary: Codable {
                        var text: String
                        var type = "summary_text"
                    }
                    var type = "reasoning"
                    var encrypted_content: String?
                    enum Status: String, Codable {
                        case in_progress, completed, incomplete
                    }
                    var status: Status?
                }
                case reasoning(Reasoning)

                struct ImageGenerationCall: Codable {
                    var id: String
                    var type = "image_generation_call"
                    var prompt: String

                    struct Parameters: Codable {
                        var model: String?
                        var quality: String?
                        var size: String?
                        var style: String?
                        var responseFormat: String?

                        private enum CodingKeys: String, CodingKey {
                            case model
                            case quality
                            case size
                            case style
                            case responseFormat = "response_format"
                        }
                    }
                    var parameters: Parameters?

                    enum Status: String, Codable {
                        case inProgress = "in_progress"
                        case completed
                        case incomplete
                        case failed
                    }
                    var status: Status?

                    struct Result: Codable {
                        var imageURL: String?
                        var error: String?

                        private enum CodingKeys: String, CodingKey {
                            case imageURL = "image_url"
                            case error
                        }
                    }
                    var result: Result?

                    private enum CodingKeys: String, CodingKey {
                        case id
                        case type
                        case prompt
                        case parameters
                        case status
                        case result
                    }
                }
                case imageGenerationCall(ImageGenerationCall)

                struct CodeInterpreterToolCall: Codable {
                    var code: String
                    var id: String
                    enum Result: Codable {
                        struct TextOutput: Codable {
                            var logs: String
                            var type = "logs"
                        }
                        case textOutput(TextOutput)

                        struct FileOutput: Codable {
                            struct File: Codable {
                                var id: String
                                var mimeType: String

                                private enum CodingKeys: String, CodingKey {
                                    case id
                                    case mimeType = "mime_type"
                                }
                            }
                            var files: [File]
                            var type = "files"
                        }
                        case fileOutput(FileOutput)
                    }
                }
                case codeInterpreterToolCall(CodeInterpreterToolCall)

                struct LocalShellCall: Codable {
                    struct Action: Codable {
                        var command: [String]
                        var env: String
                        var type = "exec"
                        var timeoutMS: Int?
                        var user: String?
                        var workingDirectory: String?

                        private enum CodingKeys: String, CodingKey {
                            case command
                            case env
                            case type
                            case timeoutMS = "timeout_ms"
                            case user
                            case workingDirectory = "working_directory"
                        }
                    }
                    var action: Action
                    var callID: String
                    var id: String
                    var status: String
                    var type = "local_shell_call"

                    private enum CodingKeys: String, CodingKey {
                        case action
                        case callID = "call_id"
                        case id
                        case status
                        case type
                    }
                }
                case localShellCall(LocalShellCall)

                struct LocalShellCallOutput: Codable {
                    var id: String
                    var output: String
                    var type = "local_shell_call_output"
                    enum Status: String, Codable {
                        case in_progress, completed, incomplete
                    }
                    var status: Status?
                }
                case localShellCallOutput(LocalShellCallOutput)

                struct MCPListTools: Codable {
                    var id: String
                    var type = "mcp_list_tools"
                    var serverLabel: String

                    enum Status: String, Codable {
                        case inProgress = "in_progress"
                        case completed
                        case incomplete
                        case failed
                    }
                    var status: Status?

                    struct Tool: Codable {
                        var name: String
                        var description: String?
                        var inputSchema: [String: Any]?

                        private enum CodingKeys: String, CodingKey {
                            case name
                            case description
                            case inputSchema = "input_schema"
                        }

                        init(from decoder: Decoder) throws {
                            let container = try decoder.container(keyedBy: CodingKeys.self)
                            name = try container.decode(String.self, forKey: .name)
                            description = try container.decodeIfPresent(String.self, forKey: .description)
                            // Handle inputSchema as generic JSON
                            if container.contains(.inputSchema) {
                                let schemaData = try container.decode(Data.self, forKey: .inputSchema)
                                inputSchema = try JSONSerialization.jsonObject(with: schemaData) as? [String: Any]
                            }
                        }

                        func encode(to encoder: Encoder) throws {
                            var container = encoder.container(keyedBy: CodingKeys.self)
                            try container.encode(name, forKey: .name)
                            try container.encodeIfPresent(description, forKey: .description)
                            if let inputSchema = inputSchema {
                                let schemaData = try JSONSerialization.data(withJSONObject: inputSchema)
                                try container.encode(schemaData, forKey: .inputSchema)
                            }
                        }
                    }
                    var tools: [Tool]?

                    private enum CodingKeys: String, CodingKey {
                        case id
                        case type
                        case serverLabel = "server_label"
                        case status
                        case tools
                    }
                }
                case mcpListTools(MCPListTools)

                struct MCPApprovalRequest: Codable {
                    var id: String
                    var type = "mcp_approval_request"
                    var serverLabel: String
                    var toolName: String
                    var arguments: [String: Any]?
                    var message: String?

                    enum Status: String, Codable {
                        case pending
                        case approved
                        case denied
                    }
                    var status: Status?

                    private enum CodingKeys: String, CodingKey {
                        case id
                        case type
                        case serverLabel = "server_label"
                        case toolName = "tool_name"
                        case arguments
                        case message
                        case status
                    }

                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        id = try container.decode(String.self, forKey: .id)
                        serverLabel = try container.decode(String.self, forKey: .serverLabel)
                        toolName = try container.decode(String.self, forKey: .toolName)
                        message = try container.decodeIfPresent(String.self, forKey: .message)
                        status = try container.decodeIfPresent(Status.self, forKey: .status)

                        // Handle arguments as generic JSON
                        if container.contains(.arguments) {
                            let argsData = try container.decode(Data.self, forKey: .arguments)
                            arguments = try JSONSerialization.jsonObject(with: argsData) as? [String: Any]
                        }
                    }

                    func encode(to encoder: Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(id, forKey: .id)
                        try container.encode(type, forKey: .type)
                        try container.encode(serverLabel, forKey: .serverLabel)
                        try container.encode(toolName, forKey: .toolName)
                        try container.encodeIfPresent(message, forKey: .message)
                        try container.encodeIfPresent(status, forKey: .status)

                        if let arguments = arguments {
                            let argsData = try JSONSerialization.data(withJSONObject: arguments)
                            try container.encode(argsData, forKey: .arguments)
                        }
                    }
                }
                case mcpApprovalRequest(MCPApprovalRequest)

                struct MCPApprovalResponse: Codable {
                    var id: String
                    var type = "mcp_approval_response"
                    var approvalRequestId: String
                    var approved: Bool
                    var reason: String?

                    private enum CodingKeys: String, CodingKey {
                        case id
                        case type
                        case approvalRequestId = "approval_request_id"
                        case approved
                        case reason
                    }
                }
                case mcpApprovalResponse(MCPApprovalResponse)

                struct MCPToolCall: Codable {
                    var id: String
                    var type = "mcp_tool_call"
                    var serverLabel: String
                    var toolName: String
                    var arguments: [String: Any]?

                    enum Status: String, Codable {
                        case inProgress = "in_progress"
                        case completed
                        case incomplete
                        case failed
                        case pending_approval = "pending_approval"
                    }
                    var status: Status?

                    struct Result: Codable {
                        var content: String?
                        var isError: Bool?
                        var metadata: [String: Any]?

                        private enum CodingKeys: String, CodingKey {
                            case content
                            case isError = "is_error"
                            case metadata
                        }

                        init(from decoder: Decoder) throws {
                            let container = try decoder.container(keyedBy: CodingKeys.self)
                            content = try container.decodeIfPresent(String.self, forKey: .content)
                            isError = try container.decodeIfPresent(Bool.self, forKey: .isError)

                            // Handle metadata as generic JSON
                            if container.contains(.metadata) {
                                let metaData = try container.decode(Data.self, forKey: .metadata)
                                metadata = try JSONSerialization.jsonObject(with: metaData) as? [String: Any]
                            }
                        }

                        func encode(to encoder: Encoder) throws {
                            var container = encoder.container(keyedBy: CodingKeys.self)
                            try container.encodeIfPresent(content, forKey: .content)
                            try container.encodeIfPresent(isError, forKey: .isError)

                            if let metadata = metadata {
                                let metaData = try JSONSerialization.data(withJSONObject: metadata)
                                try container.encode(metaData, forKey: .metadata)
                            }
                        }
                    }
                    var result: Result?

                    private enum CodingKeys: String, CodingKey {
                        case id
                        case type
                        case serverLabel = "server_label"
                        case toolName = "tool_name"
                        case arguments
                        case status
                        case result
                    }

                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        id = try container.decode(String.self, forKey: .id)
                        serverLabel = try container.decode(String.self, forKey: .serverLabel)
                        toolName = try container.decode(String.self, forKey: .toolName)
                        status = try container.decodeIfPresent(Status.self, forKey: .status)
                        result = try container.decodeIfPresent(Result.self, forKey: .result)

                        // Handle arguments as generic JSON
                        if container.contains(.arguments) {
                            let argsData = try container.decode(Data.self, forKey: .arguments)
                            arguments = try JSONSerialization.jsonObject(with: argsData) as? [String: Any]
                        }
                    }

                    func encode(to encoder: Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(id, forKey: .id)
                        try container.encode(type, forKey: .type)
                        try container.encode(serverLabel, forKey: .serverLabel)
                        try container.encode(toolName, forKey: .toolName)
                        try container.encodeIfPresent(status, forKey: .status)
                        try container.encodeIfPresent(result, forKey: .result)

                        if let arguments = arguments {
                            let argsData = try JSONSerialization.data(withJSONObject: arguments)
                            try container.encode(argsData, forKey: .arguments)
                        }
                    }
                }
                case mcpToolCall(MCPToolCall)

                // MARK: - Custom Codable Implementation for Item Enum

                private enum CodingKeys: String, CodingKey {
                    case type
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    let type = try container.decode(String.self, forKey: .type)

                    switch type {
                    case "message":
                        // Need to determine if it's input or output message
                        let singleValueContainer = try decoder.singleValueContainer()
                        if let inputMessage = try? singleValueContainer.decode(InputMessage.self) {
                            self = .inputMessage(inputMessage)
                        } else {
                            let outputMessage = try singleValueContainer.decode(OutputMessage.self)
                            self = .outputMessage(outputMessage)
                        }
                    case "file_search_call":
                        self = .fileSearchToolCall(try FileSearchToolCall(from: decoder))
                    case "computer_use_call":
                        self = .computerToolCall(try ComputerToolCall(from: decoder))
                    case "computer_use_call_output":
                        self = .computerToolCallOutput(try ComputerToolCallOutput(from: decoder))
                    case "web_search_call":
                        self = .webSearchToolCall(try WebSearchToolCall(from: decoder))
                    case "function_call":
                        self = .functionToolCall(try FunctionToolCall(from: decoder))
                    case "function_call_output":
                        self = .functionToolCallOutput(try FunctionToolCallOutput(from: decoder))
                    case "reasoning":
                        self = .reasoning(try Reasoning(from: decoder))
                    case "image_generation_call":
                        self = .imageGenerationCall(try ImageGenerationCall(from: decoder))
                    case "code_interpreter_call":
                        self = .codeInterpreterToolCall(try CodeInterpreterToolCall(from: decoder))
                    case "local_shell_call":
                        self = .localShellCall(try LocalShellCall(from: decoder))
                    case "local_shell_call_output":
                        self = .localShellCallOutput(try LocalShellCallOutput(from: decoder))
                    case "mcp_list_tools":
                        self = .mcpListTools(try MCPListTools(from: decoder))
                    case "mcp_approval_request":
                        self = .mcpApprovalRequest(try MCPApprovalRequest(from: decoder))
                    case "mcp_approval_response":
                        self = .mcpApprovalResponse(try MCPApprovalResponse(from: decoder))
                    case "mcp_tool_call":
                        self = .mcpToolCall(try MCPToolCall(from: decoder))
                    default:
                        throw DecodingError.dataCorruptedError(
                            forKey: .type,
                            in: container,
                            debugDescription: "Unknown Item type: \(type)"
                        )
                    }
                }

                func encode(to encoder: Encoder) throws {
                    switch self {
                    case .inputMessage(let message):
                        try message.encode(to: encoder)
                    case .outputMessage(let message):
                        try message.encode(to: encoder)
                    case .fileSearchToolCall(let call):
                        try call.encode(to: encoder)
                    case .computerToolCall(let call):
                        try call.encode(to: encoder)
                    case .computerToolCallOutput(let output):
                        try output.encode(to: encoder)
                    case .webSearchToolCall(let call):
                        try call.encode(to: encoder)
                    case .functionToolCall(let call):
                        try call.encode(to: encoder)
                    case .functionToolCallOutput(let output):
                        try output.encode(to: encoder)
                    case .reasoning(let reasoning):
                        try reasoning.encode(to: encoder)
                    case .imageGenerationCall(let call):
                        try call.encode(to: encoder)
                    case .codeInterpreterToolCall(let call):
                        try call.encode(to: encoder)
                    case .localShellCall(let call):
                        try call.encode(to: encoder)
                    case .localShellCallOutput(let output):
                        try output.encode(to: encoder)
                    case .mcpListTools(let tools):
                        try tools.encode(to: encoder)
                    case .mcpApprovalRequest(let request):
                        try request.encode(to: encoder)
                    case .mcpApprovalResponse(let response):
                        try response.encode(to: encoder)
                    case .mcpToolCall(let call):
                        try call.encode(to: encoder)
                    }
                }
            }
            case item(Item)

            init(from decoder: Decoder) throws {
                 // Try to decode as Message first
                 if let messageValue = try? decoder.singleValueContainer().decode(Message.self) {
                     self = .message(messageValue)
                     return
                 }

                 // Try to decode as Item
                 if let itemValue = try? decoder.singleValueContainer().decode(Item.self) {
                     self = .item(itemValue)
                     return
                 }

                 throw DecodingError.dataCorrupted(
                     DecodingError.Context(
                         codingPath: decoder.codingPath,
                         debugDescription: "Cannot decode ItemListEntry - expected Message or Item"
                     )
                 )
             }

             func encode(to encoder: Encoder) throws {
                 var container = encoder.singleValueContainer()

                 switch self {
                 case .message(let messageValue):
                     try container.encode(messageValue)
                 case .item(let itemValue):
                     try container.encode(itemValue)
                 }
             }
        } // ItemListEntry

        case text(String)
        case itemList([ItemListEntry])


        private enum CodingKeys: String, CodingKey {
            case text
            case itemList = "item_list"
        }

        init(from decoder: Decoder) throws {
            // Try to decode as a string first
            if let stringValue = try? decoder.singleValueContainer().decode(String.self) {
                self = .text(stringValue)
                return
            }

            // Try to decode as an array
            if let arrayValue = try? decoder.singleValueContainer().decode([ItemListEntry].self) {
                self = .itemList(arrayValue)
                return
            }

            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Cannot decode Input - expected String or [ItemListEntry]"
                )
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()

            switch self {
            case .text(let stringValue):
                try container.encode(stringValue)
            case .itemList(let arrayValue):
                try container.encode(arrayValue)
            }
        }
    } // Input

    var input: Input
    /// The model to use for this request (e.g. "gpt-4o")
    var model: String

    /// Whether to run the model response in the background.
    var background: Bool?

    /// Specify additional output data to include in the model response.
    enum Includable: String, Codable {
        /// Include the search results of the file search tool call
        case fileSearchResults = "file_search_call.results"

        /// Include image urls from the input message
        case messageInputImage = "message.input_image.image_url"

        /// Include image urls from the computer call output.
        case computerImageOutput = "computer_call_output.output.image_url"

        /// Includes an encrypted version of reasoning tokens in reasoning item outputs.
        case reasoningEncryptedContent = "reasoning.encrypted_content"
    }
    var include: [Includable]?

    /// If true, the task will run on the server and you poll for a result.
    /// Useful if the model takes minutes to complete.
    var instructions: String?

    /// An upper bound for the number of tokens that can be generated for a response, including visible output tokens and reasoning tokens.
    var maxOutputTokens: Int?

    /// Arbitrary metadata for your own tracking (up to 16 key/value pairs).
    var metadata: [String: String]?

    /// Whether to allow the model to run tool calls in parallel.
    var parallelToolCalls: Bool?

    /// For multi‐turn: resume from a previous response.
    var previousResponseID: String?

    /// Controls reasoning summaries or encrypted reasoning content.
    public struct ReasoningOptions: Codable {
        enum Effort: String, Codable {
            case minimal
            case low
            case medium
            case high
        }
        var effort: Effort?

        /// e.g. ["summary": "auto"] or {"detailed": true}
        enum Summary: String, Codable {
            case auto
            case concise
            case detailed
        }
        var summary: Summary?
    }
    var reasoning: ReasoningOptions?

    /// Specifies the latency tier to use for processing the request. This parameter is relevant for customers subscribed to the scale tier service.
    enum ServiceTier: String, Codable {
        case auto
        case `default`
        case flex
    }
    var serviceTier: ServiceTier?

    /// Whether to store this response in the conversation history.
    var store: Bool?

    /// If set to true, the model response data will be streamed to the client as it is generated using server-sent events.
    var stream: Bool?

    /// Sampling temperature (0.0–2.0).
    var temperature: Double?

    /// Configuration options for a text response from the model. Can be plain text or structured JSON data. Learn more
    struct Text: Codable {
        struct Format: Codable {
            enum FormatType: String, Codable {
                /// enables Structured Outputs, which ensures the model will match your supplied JSON schema
                case jsonSchema

                /// Default
                case text

                /// enables the older JSON mode, which ensures the message the model generates is valid JSON. Prefer jsonSchema.
                case jsonObject
            }
            var type: FormatType
        }
    }
    var text: Text?

    /// Force or prefer a tool cal
    enum ToolChoice: Codable {
        case none, auto, required

        /// Indicates that the model should use a built-in tool to generate a response. Learn more about built-in tools.
        struct HostedTool: Codable {
            enum HostedToolType: String, Codable {
                case fileSearch = "file_search"
                case webSearchPreview = "web_search_preview"
                case computerUsePreview = "computer_use_preview"
                case codeInterpreter = "code_interpreter"
                case mcp = "mcp"
                case imageGeneration = "image_generation"
            }
            var type: HostedToolType
        }
        case hosted(HostedTool)

        /// Use this option to force the model to call a specific function.
        struct FunctionTool: Codable {
            var name: String
            var type = "function"
        }
        case function(FunctionTool)

        private enum CodingKeys: String, CodingKey {
            case type, name
        }

        init(from decoder: Decoder) throws {
            // Try decoding simple string cases first
            let single = try decoder.singleValueContainer()
            if let str = try? single.decode(String.self) {
                switch str {
                case "none":      self = .none
                case "auto":      self = .auto
                case "required":  self = .required
                default:
                    throw DecodingError.dataCorruptedError(
                        in: single,
                        debugDescription: "Invalid ToolChoice string: \(str)"
                    )
                }
                return
            }

            // Otherwise decode as object
            let keyed = try decoder.container(keyedBy: CodingKeys.self)
            let type = try keyed.decode(String.self, forKey: .type)

            if type == "function" {
                let name = try keyed.decode(String.self, forKey: .name)
                self = .function(.init(name: name))
            } else {
                // HostedTool has its own Codable conformance
                let hosted = try HostedTool(from: decoder)
                self = .hosted(hosted)
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .none, .auto, .required:
                var single = encoder.singleValueContainer()
                let str: String
                switch self {
                case .none:
                    str = "none"
                case .auto:
                    str = "auto"
                case .required:
                    str = "required"
                default:
                    it_fatalError()
                }
                try single.encode(str)

            case .hosted(let tool):
                try tool.encode(to: encoder)

            case .function(let tool):
                var keyed = encoder.container(keyedBy: CodingKeys.self)
                try keyed.encode(tool.type, forKey: .type)
                try keyed.encode(tool.name, forKey: .name)
            }
        }
    }
    var toolChoice: ToolChoice?

    /// Built‐in or custom tools (e.g. web_search, file_search).
    enum Tool: Codable {
        /// Function tool definition.
        struct FunctionTool: Codable {
            var name: String
            var parameters: JSONSchema
            var strict: Bool
            var type = "function"
            var description: String?
        }
        case function(FunctionTool)

        /// A tool that searches for relevant content from uploaded files. Learn more about the file search tool.
        struct FileSearchTool: Codable {
            var type = "file_search"

            /// The IDs of the vector stores to search.
            var vectorStoreIds: [String]

            enum Filter: Codable {
                struct ComparisonFilter: Codable {
                    var key: String

                    enum ComparisonFilterType: String, Codable {
                        case eq  /// equals
                        case ne  /// not equal
                        case gt  /// greater than
                        case gte  /// greater than or equal
                        case lt  /// less than
                        case lte  /// less than or equal
                    }
                    var type: ComparisonFilterType
                    var value: String
                }
                case comparison(ComparisonFilter)

                struct CompoundFilter: Codable {
                    var filters: [ComparisonFilter]
                    enum CompoundFilterType: String, Codable {
                        case and
                        case or
                    }
                    var type: CompoundFilterType
                }
                case compound(CompoundFilter)

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    if container.contains(.filters) {
                        let compound = try CompoundFilter(from: decoder)
                        self = .compound(compound)
                    } else {
                        let comparison = try ComparisonFilter(from: decoder)
                        self = .comparison(comparison)
                    }
                }

                func encode(to encoder: Encoder) throws {
                    switch self {
                    case .comparison(let comparison):
                        try comparison.encode(to: encoder)
                    case .compound(let compound):
                        try compound.encode(to: encoder)
                    }
                }

                private enum CodingKeys: String, CodingKey {
                    case filters
                }
            }

            /// A filter to apply.
            var filters: [Filter]
            private enum CodingKeys: String, CodingKey {
                case type
                case vectorStoreIds = "vector_store_ids"
                case filters
            }

        }
        case fileSearch(FileSearchTool)

        /// Web search preview tool definition.
        struct WebSearchPreviewTool: Codable {
            enum WebSearchType: String, Codable {
                case web_search_preview
                case web_search_preview_2025_03_11
            }
            var type: WebSearchType

            /// High level guidance for the amount of context window space to use for the search.
            enum SearchContextSize: String, Codable {
                case low
                case medium
                case high
            }
            var searchContextSize: SearchContextSize

            /// The user's location.
            struct UserLocation: Codable {
                /// The type of location approximation. Always approximate.
                var type = "approximate"

                /// Free text input for the city of the user, e.g. San Francisco.
                var city: String?

                /// The two-letter ISO country code of the user, e.g. US.
                var country: String?

                /// Free text input for the region of the user, e.g. California.
                var region: String?

                /// The IANA timezone of the user, e.g. America/Los_Angeles.
                var timezone: String?
            }
            var userLocation: UserLocation

            private enum CodingKeys: String, CodingKey {
                case type
                case searchContextSize = "search_context_size"
                case userLocation = "user_location"
            }
        }
        case webSearchPreview(WebSearchPreviewTool)

        /// Computer use preview tool definition.
        struct ComputerUsePreviewTool: Codable {
            var type = "computer_use_preview"
            var displayHeight: Int
            var displayWidth: Int
            var environment: String

            private enum CodingKeys: String, CodingKey {
                case type
                case displayHeight = "display_height"
                case displayWidth = "display_width"
                case environment
            }
        }
        case computerUsePreview(ComputerUsePreviewTool)

        /// MCP tool definition.
        struct MCPTool: Codable {
            ///A label for this MCP server, used to identify it in tool calls.
            let serverLabel: String

            /// The URL for the MCP server.
            var serverURL: String

            /// The type of the MCP tool. Always mcp.
            var type: String = "mcp"

            enum AllowedTools: Codable {
                // Encodes as an array of strings
                case mcpAllowedTools([String])

                struct MCPAllowedToolsFilter: Codable {
                    var toolNames: [String]
                    private enum CodingKeys: String, CodingKey {
                        case toolNames = "tool_names"
                    }
                }
                // Encodes as an object
                case mcpAllowedToolsFilter(MCPAllowedToolsFilter)

                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let array = try? container.decode([String].self) {
                        self = .mcpAllowedTools(array)
                    } else {
                        let filter = try container.decode(MCPAllowedToolsFilter.self)
                        self = .mcpAllowedToolsFilter(filter)
                    }
                }

                func encode(to encoder: Encoder) throws {
                    var container = encoder.singleValueContainer()
                    switch self {
                    case .mcpAllowedTools(let array):
                        try container.encode(array)
                    case .mcpAllowedToolsFilter(let filter):
                        try container.encode(filter)
                    }
                }
            }
            var allowedTools: AllowedTools

            /// Optional HTTP headers to send to the MCP server. Use for authentication or other purposes.
            var headers: [String: String]?

            /// Specify which of the MCP server's tools require approval.
            enum RequireApproval: Codable {
                struct MCPApprovalFilter: Codable {
                    struct ToolNameList: Codable {
                        var toolNames: [String]

                        private enum CodingKeys: String, CodingKey {
                            case toolNames = "tool_names"
                        }
                    }
                    var always: ToolNameList
                    var never: ToolNameList
                }
                case filter(MCPApprovalFilter)

                enum MCPApprovalSetting: String, Codable {
                    case always
                    case never
                }
                case setting(MCPApprovalSetting)

                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let setting = try? container.decode(MCPApprovalSetting.self) {
                        self = .setting(setting)
                        return
                    }
                    let filter = try container.decode(MCPApprovalFilter.self)
                    self = .filter(filter)
                }

                func encode(to encoder: Encoder) throws {
                    var container = encoder.singleValueContainer()
                    switch self {
                    case .setting(let setting):
                        try container.encode(setting)
                    case .filter(let filter):
                        try container.encode(filter)
                    }
                }
            }
            var requireApproval: RequireApproval?

            private enum CodingKeys: String, CodingKey {
                case type
                case serverLabel  = "server_label"
                case serverURL    = "server_url"
                case allowedTools = "allowed_tools"
                case headers
                case requireApproval = "require_approval"
            }
        }
        case mcp(MCPTool)

        /// Code interpreter tool definition.
        struct CodeInterpreterTool: Codable {
            var type = "code_interpreter"

            enum Container: Codable {
                case identifier(String)

                struct CodeInterpreterContainerAuto: Codable {
                    var type = "auto"
                    var fileIDs: [String]?

                    private enum CodingKeys: String, CodingKey {
                        case type
                        case fileIDs = "file_ids"
                    }
                }
                case auto(CodeInterpreterContainerAuto)

                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let id = try? container.decode(String.self) {
                        self = .identifier(id)
                    } else {
                        let autoContainer = try container.decode(CodeInterpreterContainerAuto.self)
                        self = .auto(autoContainer)
                    }
                }

                func encode(to encoder: Encoder) throws {
                    var container = encoder.singleValueContainer()
                    switch self {
                    case .identifier(let id):
                        try container.encode(id)
                    case .auto(let autoContainer):
                        try container.encode(autoContainer)
                    }
                }
            }
            var container: Container
        }
        case codeInterpreter(CodeInterpreterTool)

        /// Image generation tool definition.
        struct ImageGenerationTool: Codable {
            let type = "image_generation"

            /// Background type for the generated image
            enum Background: String, Codable {
                case transparent
                case opaque
                case auto
            }
            let background: Background?

            /// Optional mask for inpainting
            struct Mask: Codable {
                var fileID: String
                var imageURL: String

                private enum CodingKeys: String, CodingKey {
                    case fileID = "file_id"
                    case imageURL = "image_url"
                }
            }
            let inputImageMask: Mask?

            /// The image generation model to use
            let model: String?

            /// Moderation level for the generated image (legal values not documented)
            let moderation: String?

            /// Compression level for the output image
            let outputCompression: Int?

            /// The output format of the generated image
            enum Format: Codable {
                case png
                case webp
                case jpeg
            }
            let outputFormat: Format?

            /// Number of partial images to generate in streaming mode, from 0 (default value) to 3.
            let partialImages: Int?

            /// The quality of the generated image
            enum Quality: String, Codable {
                case low
                case medium
                case high
                case auto
            }
            let quality: Quality?

            enum Size: String, Codable {
                case small = "1024x1024"
                case medium = "1024x1536"
                case large = "1536x1024"
                case auto
            }
            let size: String?

            private enum CodingKeys: String, CodingKey {
                case type
                case background
                case inputImageMask = "input_image_mask"
                case model
                case moderation
                case outputCompression = "output_compression"
                case outputFormat = "output_format"
                case partialImages = "partial_images"
                case quality
                case size
            }
        }
        case imageGeneration(ImageGenerationTool)

        /// Local shell tool definition.
        struct LocalShellTool: Codable {
            let type: String = "local_shell"

            private enum CodingKeys: String, CodingKey {
                case type
            }
        }
        case localShell(LocalShellTool)

        private enum CodingKeys: String, CodingKey {
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "function":
                let tool = try FunctionTool(from: decoder)
                self = .function(tool)
            case "file_search":
                let tool = try FileSearchTool(from: decoder)
                self = .fileSearch(tool)
            case "web_search_preview":
                let tool = try WebSearchPreviewTool(from: decoder)
                self = .webSearchPreview(tool)
            case "computer_use_preview":
                let tool = try ComputerUsePreviewTool(from: decoder)
                self = .computerUsePreview(tool)
            case "mcp":
                let tool = try MCPTool(from: decoder)
                self = .mcp(tool)
            case "code_interpreter":
                let tool = try CodeInterpreterTool(from: decoder)
                self = .codeInterpreter(tool)
            case "image_generation":
                let tool = try ImageGenerationTool(from: decoder)
                self = .imageGeneration(tool)
            case "local_shell":
                let tool = try LocalShellTool(from: decoder)
                self = .localShell(tool)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown tool type: \(type)"
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .function(let tool):
                try tool.encode(to: encoder)
            case .fileSearch(let tool):
                try tool.encode(to: encoder)
            case .webSearchPreview(let tool):
                try tool.encode(to: encoder)
            case .computerUsePreview(let tool):
                try tool.encode(to: encoder)
            case .mcp(let tool):
                try tool.encode(to: encoder)
            case .codeInterpreter(let tool):
                try tool.encode(to: encoder)
            case .imageGeneration(let tool):
                try tool.encode(to: encoder)
            case .localShell(let tool):
                try tool.encode(to: encoder)
            }
        }
    }
    var tools: [Tool]?

    /// An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered.
    var topP: Double?

    enum Truncation: String, Codable {
        /// auto: If the context of this response and previous ones exceeds the model's context window size, the model will truncate the response to fit the context window by dropping input items in the middle of the conversation.
        case auto

        /// disabled (default): If a model response will exceed the context window size for a model, the request will fail with a 400 error.
        case disabled
    }
    var truncation: Truncation?

    /// A stable identifier for your end-users. Used to boost cache hit rates by better bucketing similar requests and to help OpenAI detect and prevent abuse. Learn more.
    var user: String?

    private enum CodingKeys: String, CodingKey {
        case input
        case model
        case background
        case include
        case instructions
        case maxOutputTokens = "max_output_tokens"
        case metadata
        case parallelToolCalls = "parallel_tool_calls"
        case previousResponseID = "previous_response_id"
        case reasoning
        case serviceTier = "service_tier"
        case store
        case stream
        case temperature
        case text
        case toolChoice = "tool_choice"
        case tools
        case topP = "top_p"
        case truncation
        case user
    }
}

struct ResponsesBodyRequestBuilder {
    var messages: [LLM.Message]
    var provider: LLMProvider
    var functions = [LLM.AnyFunction]()
    var stream: Bool
    var hostedTools: HostedTools
    var previousResponseID: String?
    var shouldThink: Bool?

    private func transform(message: LLM.Message) -> ResponsesRequestBody.Input.ItemListEntry? {
        switch message.role {
        case .assistant:
            if let content = message.content {
                return .message(.init(content: .text(content), role: .assistant))
            }
            return nil

        case .function:
            if let call = message.function_call {
                // Function call request
                guard let args = call.arguments, let id = message.functionCallID, let name = call.name else {
                    return nil
                }
                return .item(.functionToolCall(.init(arguments: args,
                                                     callID: id.callID,
                                                     name: name,
                                                     id: id.itemID)))
            }
            if let callID = message.functionCallID,
               let content = message.content {
                // Function call response
                return .item(.functionToolCallOutput(.init(callID: callID.callID,
                                                           id: nil,
                                                           output: content,
                                                           status: nil /*.completed*/)))
            }
            return nil
        case .system:
            guard let content = message.content else {
                return nil
            }
            return .message(.init(content: .text(content), role: .system))
        case .user:
            switch message.body {
            case .uninitialized:
                return nil
            case .text(let text):
                return .message(.init(content: .text(text), role: .user))
            case .functionCall, .functionOutput, .attachment:
                DLog("Unexpected user message body \(message.body)")
                return nil
            case .multipart(let subparts):
                let inputItemContents = subparts.compactMap { subpart -> ResponsesRequestBody.InputItemContent? in
                    switch subpart {
                    case .uninitialized:
                        return nil
                    case .text(let text):
                        return .inputText(.init(text: text))
                    case .functionCall, .functionOutput:
                        return nil
                    case .attachment(let attachment):
                        switch attachment.type {
                        case .code(let code):
                            return .inputFile(.init(fileData: "data:text/plain;base64," + code.base64Encoded))
                        case .statusUpdate:
                            return nil
                        case .file(let file):
                            if mimeTypeIsTextual(file.mimeType) {
                                return .inputText(.init(text: file.content.lossyString))
                            }
                            return .inputFile(.init(fileData: "data:\(file.mimeType);base64," +  file.content.base64EncodedString(),
                                                    filename: file.name))
                        case .fileID(let fileID, _):
                            if hostedTools.codeInterpreter {
                                // For code interpreter file IDs are shared through
                                // tools: {
                                //   type="code_interpreter",
                                //   container: {
                                //     file_ids: [ "file id", … ]
                                //   }
                                // }
                                return nil
                            } else {
                                // This is only valid for PDFs currently.
                                return .inputFile(.init(fileID: fileID))
                            }
                        }
                    case .multipart(_):
                        return nil
                    }
                }
                return .message(.init(content: .inputItemContentList(inputItemContents),
                                      role: .user))
            }
        case .none:
            return nil
        }
    }

    private func mimeTypeIsTextual(_ mimeType: String) -> Bool {
        return MIMETypeIsTextual(mimeType)
    }

    private func fileIDsForCodeInterpreter() -> [String] {
        return switch messages.last?.body {
        case .multipart(let parts):
            parts.compactMap { part in
                switch part {
                case .attachment(let attachment):
                    switch attachment.type {
                    case .fileID(id: let id, _):
                        return id
                    default:
                        return nil
                    }
                default:
                    return nil
                }
            }
        default:
            []
        }
    }
    private var transformedHostedTools: [ResponsesRequestBody.Tool] {
        var result = [ResponsesRequestBody.Tool]()
        if let fileSearch = hostedTools.fileSearch {
            result.append(.fileSearch(.init(vectorStoreIds: fileSearch.vectorstoreIDs, filters: [])))
        }
        if hostedTools.webSearch {
            result.append(.webSearchPreview(.init(type: .web_search_preview,
                                                  searchContextSize: .medium,
                                                  userLocation: .init())))
        }
        if hostedTools.codeInterpreter {
            let fileIDs = fileIDsForCodeInterpreter()
            result.append(.codeInterpreter(.init(container: .auto(.init(fileIDs: fileIDs)))))
        }
        return result
    }

    private func transform(function: LLM.AnyFunction) -> ResponsesRequestBody.Tool {
        var schema = function.decl.parameters
        schema.additionalProperties = false
        return .function(.init(name: function.decl.name,
                               parameters: schema,
                               strict: true,
                               description: function.decl.description))
    }

    func body() throws -> Data {
        // Tokens are about 4 letters each. Allow enough tokens to include both the query and an
        // answer the same length as the query.
        var itemList = messages.compactMap { transform(message: $0) }
        if previousResponseID != nil && !itemList.isEmpty {
            itemList.removeFirst(itemList.count - 1)
        }
        let tools = functions.map { transform(function: $0) } + transformedHostedTools
        var body = ResponsesRequestBody(
            input: .itemList(itemList),
            model: provider.model.name,
            maxOutputTokens: provider.maxTokens(functions: functions, messages: messages),
            parallelToolCalls: false,
            previousResponseID: previousResponseID,
            stream: stream,
            toolChoice: tools.isEmpty ? ResponsesRequestBody.ToolChoice.none : .auto,
            tools: tools)
        if let shouldThink {
            if shouldThink {
                body.reasoning = .init(effort: .medium, summary: .auto)
            } else {
                body.reasoning = .init(effort: .low)
            }
        }
        let bodyEncoder = JSONEncoder()
        let bodyData = try! bodyEncoder.encode(body)
        DLog("REQUEST:\n\(bodyData.lossyString)")
//        print(bodyData.lossyString)
        return bodyData

    }
}
