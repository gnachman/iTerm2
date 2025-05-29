//
//  ResponsesAPI.swift
//  iTerm2
//
//  Created by George Nachman on 5/29/25.
//

import Foundation

// MARK: - Main Response Object
struct ResponsesResponseBody: Codable {
    let background: Bool?
    let createdAt: Int
    let error: ResponseError?
    let id: String
    let incompleteDetails: IncompleteDetails?
    let instructions: String?
    let maxOutputTokens: Int?
    let metadata: [String: String]
    let model: String
    let object: String
    let output: [OutputItem]
    let outputText: String?
    let parallelToolCalls: Bool
    let previousResponseID: String?
    let reasoning: ReasoningConfig?
    let serviceTier: String?
    let status: ResponseStatus
    let temperature: Double?
    let text: TextConfig
    let toolChoice: ToolChoice
    let tools: [Tool]
    let topP: Double?
    let truncation: String?
    let usage: Usage
    let user: String?

    enum CodingKeys: String, CodingKey {
        case background
        case createdAt = "created_at"
        case error
        case id
        case incompleteDetails = "incomplete_details"
        case instructions
        case maxOutputTokens = "max_output_tokens"
        case metadata
        case model
        case object
        case output
        case outputText = "output_text"
        case parallelToolCalls = "parallel_tool_calls"
        case previousResponseID = "previous_response_id"
        case reasoning
        case serviceTier = "service_tier"
        case status
        case temperature
        case text
        case toolChoice = "tool_choice"
        case tools
        case topP = "top_p"
        case truncation
        case usage
        case user
    }

    // MARK: - Response Status
    enum ResponseStatus: String, Codable {
        case completed
        case failed
        case inProgress = "in_progress"
        case cancelled
        case queued
        case incomplete
    }

    // MARK: - Error Object
    struct ResponseError: Codable {
        let code: String
        let message: String
    }

    // MARK: - Incomplete Details
    struct IncompleteDetails: Codable {
        let reason: String
    }

    // MARK: - Reasoning Config
    struct ReasoningConfig: Codable {
        let effort: String?
        let generateSummary: String?
        let summary: String?

        enum CodingKeys: String, CodingKey {
            case effort
            case generateSummary = "generate_summary"
            case summary
        }
    }

    // MARK: - Text Config
    struct TextConfig: Codable {
        let format: TextFormat
    }

    // MARK: - Text Format (Polymorphic)
    enum TextFormat: Codable {
        case text(TextFormatObject)
        case jsonSchema(JSONSchemaFormatObject)
        case jsonObject(JSONObjectFormatObject)

        enum CodingKeys: String, CodingKey {
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "text":
                self = .text(try TextFormatObject(from: decoder))
            case "json_schema":
                self = .jsonSchema(try JSONSchemaFormatObject(from: decoder))
            case "json_object":
                self = .jsonObject(try JSONObjectFormatObject(from: decoder))
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown text format type: \(type)"))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .text(let format):
                try format.encode(to: encoder)
            case .jsonSchema(let format):
                try format.encode(to: encoder)
            case .jsonObject(let format):
                try format.encode(to: encoder)
            }
        }
    }

    struct TextFormatObject: Codable {
        let type: String
    }

    struct JSONSchemaFormatObject: Codable {
        let name: String
        let schema: [String: Any]
        let type: String
        let description: String?
        let strict: Bool?

        enum CodingKeys: String, CodingKey {
            case name, schema, type, description, strict
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            type = try container.decode(String.self, forKey: .type)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            strict = try container.decodeIfPresent(Bool.self, forKey: .strict)

            // Handle schema as generic JSON
            let schemaData = try container.decode([String: Any].self, forKey: .schema)
            schema = schemaData
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(strict, forKey: .strict)
            // Note: Encoding [String: Any] requires custom implementation
        }
    }

    struct JSONObjectFormatObject: Codable {
        let type: String
    }

    // MARK: - Tool Choice (Polymorphic)
    enum ToolChoice: Codable {
        case string(String)
        case hostedTool(HostedToolChoice)
        case functionTool(FunctionToolChoice)

        init(from decoder: Decoder) throws {
            if let stringValue = try? decoder.singleValueContainer().decode(String.self) {
                self = .string(stringValue)
            } else if let hostedTool = try? HostedToolChoice(from: decoder) {
                self = .hostedTool(hostedTool)
            } else {
                self = .functionTool(try FunctionToolChoice(from: decoder))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .string(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case .hostedTool(let tool):
                try tool.encode(to: encoder)
            case .functionTool(let tool):
                try tool.encode(to: encoder)
            }
        }
    }

    struct HostedToolChoice: Codable {
        let type: String
    }

    struct FunctionToolChoice: Codable {
        let name: String
        let type: String
    }

    // MARK: - Output Item (Polymorphic)
    enum OutputItem: Codable {
        case message(OutputMessage)
        case fileSearchToolCall(FileSearchToolCall)
        case functionToolCall(FunctionToolCall)
        case webSearchToolCall(WebSearchToolCall)
        case computerToolCall(ComputerToolCall)
        case reasoning(ReasoningItem)
        case imageGenerationCall(ImageGenerationCall)
        case codeInterpreterToolCall(CodeInterpreterToolCall)
        case localShellCall(LocalShellCall)
        case mcpToolCall(MCPToolCall)
        case mcpListTools(MCPListTools)
        case mcpApprovalRequest(MCPApprovalRequest)

        enum CodingKeys: String, CodingKey {
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "message":
                self = .message(try OutputMessage(from: decoder))
            case "file_search_call":
                self = .fileSearchToolCall(try FileSearchToolCall(from: decoder))
            case "function_call":
                self = .functionToolCall(try FunctionToolCall(from: decoder))
            case "web_search_call":
                self = .webSearchToolCall(try WebSearchToolCall(from: decoder))
            case "computer_call":
                self = .computerToolCall(try ComputerToolCall(from: decoder))
            case "reasoning":
                self = .reasoning(try ReasoningItem(from: decoder))
            case "image_generation_call":
                self = .imageGenerationCall(try ImageGenerationCall(from: decoder))
            case "code_interpreter_call":
                self = .codeInterpreterToolCall(try CodeInterpreterToolCall(from: decoder))
            case "local_shell_call":
                self = .localShellCall(try LocalShellCall(from: decoder))
            case "mcp_call":
                self = .mcpToolCall(try MCPToolCall(from: decoder))
            case "mcp_list_tools":
                self = .mcpListTools(try MCPListTools(from: decoder))
            case "mcp_approval_request":
                self = .mcpApprovalRequest(try MCPApprovalRequest(from: decoder))
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown output item type: \(type)"))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .message(let item):
                try item.encode(to: encoder)
            case .fileSearchToolCall(let item):
                try item.encode(to: encoder)
            case .functionToolCall(let item):
                try item.encode(to: encoder)
            case .webSearchToolCall(let item):
                try item.encode(to: encoder)
            case .computerToolCall(let item):
                try item.encode(to: encoder)
            case .reasoning(let item):
                try item.encode(to: encoder)
            case .imageGenerationCall(let item):
                try item.encode(to: encoder)
            case .codeInterpreterToolCall(let item):
                try item.encode(to: encoder)
            case .localShellCall(let item):
                try item.encode(to: encoder)
            case .mcpToolCall(let item):
                try item.encode(to: encoder)
            case .mcpListTools(let item):
                try item.encode(to: encoder)
            case .mcpApprovalRequest(let item):
                try item.encode(to: encoder)
            }
        }
    }

    // MARK: - Output Message
    struct OutputMessage: Codable {
        let content: [MessageContent]
        let id: String
        let role: String
        let status: String?
        let type: String
    }

    // MARK: - Message Content (Polymorphic)
    enum MessageContent: Codable {
        case outputText(OutputText)
        case refusal(RefusalContent)

        enum CodingKeys: String, CodingKey {
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "output_text":
                self = .outputText(try OutputText(from: decoder))
            case "refusal":
                self = .refusal(try RefusalContent(from: decoder))
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown message content type: \(type)"))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .outputText(let content):
                try content.encode(to: encoder)
            case .refusal(let content):
                try content.encode(to: encoder)
            }
        }
    }

    // MARK: - Output Text
    struct OutputText: Codable {
        let annotations: [TextAnnotation]
        let logprobs: LogprobsData?
        let text: String
        let topLogprobs: [TopLogprob]?
        let type: String

        enum CodingKeys: String, CodingKey {
            case annotations
            case logprobs
            case text
            case topLogprobs = "top_logprobs"
            case type
        }
    }

    // MARK: - Text Annotation (Polymorphic)
    enum TextAnnotation: Codable {
        case fileCitation(FileCitation)
        case urlCitation(URLCitation)
        case filePath(FilePath)

        enum CodingKeys: String, CodingKey {
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "file_citation":
                self = .fileCitation(try FileCitation(from: decoder))
            case "url_citation":
                self = .urlCitation(try URLCitation(from: decoder))
            case "file_path":
                self = .filePath(try FilePath(from: decoder))
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown annotation type: \(type)"))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .fileCitation(let annotation):
                try annotation.encode(to: encoder)
            case .urlCitation(let annotation):
                try annotation.encode(to: encoder)
            case .filePath(let annotation):
                try annotation.encode(to: encoder)
            }
        }
    }

    struct FileCitation: Codable {
        let fileID: String
        let index: Int
        let type: String

        enum CodingKeys: String, CodingKey {
            case fileID = "file_id"
            case index
            case type
        }
    }

    struct URLCitation: Codable {
        let endIndex: Int
        let startIndex: Int
        let title: String
        let type: String
        let url: String

        enum CodingKeys: String, CodingKey {
            case endIndex = "end_index"
            case startIndex = "start_index"
            case title
            case type
            case url
        }
    }

    struct FilePath: Codable {
        let fileID: String
        let index: Int
        let type: String

        enum CodingKeys: String, CodingKey {
            case fileID = "file_id"
            case index
            case type
        }
    }

    struct LogprobsData: Codable {
        let bytes: [Int]
        let logprob: Double
        let token: String
    }

    struct TopLogprob: Codable {
        let bytes: [Int]
        let logprob: Double
        let token: String
    }

    struct RefusalContent: Codable {
        let refusal: String
        let type: String
    }

    // MARK: - Tool Call Types
    struct FileSearchToolCall: Codable {
        let id: String
        let queries: [String]
        let status: String
        let type: String
        let results: [FileSearchResult]?
    }

    struct FileSearchResult: Codable {
        let attributes: [String: Any]
        let fileID: String
        let filename: String
        let score: Double
        let text: String

        enum CodingKeys: String, CodingKey {
            case attributes
            case fileID = "file_id"
            case filename
            case score
            case text
        }

        // Custom init/encode needed for [String: Any]
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fileID = try container.decode(String.self, forKey: .fileID)
            filename = try container.decode(String.self, forKey: .filename)
            score = try container.decode(Double.self, forKey: .score)
            text = try container.decode(String.self, forKey: .text)
            // Handle attributes as generic JSON
            attributes = try container.decode([String: Any].self, forKey: .attributes)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(fileID, forKey: .fileID)
            try container.encode(filename, forKey: .filename)
            try container.encode(score, forKey: .score)
            try container.encode(text, forKey: .text)
            // Note: Encoding [String: Any] requires custom implementation
        }
    }

    struct FunctionToolCall: Codable {
        let arguments: String
        let callID: String
        let name: String
        let type: String
        let id: String
        let status: String

        enum CodingKeys: String, CodingKey {
            case arguments
            case callID = "call_id"
            case name
            case type
            case id
            case status
        }
    }

    struct WebSearchToolCall: Codable {
        let id: String
        let status: String
        let type: String
    }

    // MARK: - Computer Tool Call
    struct ComputerToolCall: Codable {
        let action: ComputerAction
        let callID: String
        let id: String
        let pendingSafetyChecks: [PendingSafetyCheck]
        let status: String
        let type: String

        enum CodingKeys: String, CodingKey {
            case action
            case callID = "call_id"
            case id
            case pendingSafetyChecks = "pending_safety_checks"
            case status
            case type
        }
    }

    // MARK: - Computer Action (Polymorphic)
    enum ComputerAction: Codable {
        case click(ClickAction)
        case doubleClick(DoubleClickAction)
        case drag(DragAction)
        case keyPress(KeyPressAction)
        case move(MoveAction)
        case screenshot(ScreenshotAction)
        case scroll(ScrollAction)
        case type(TypeAction)
        case wait(WaitAction)

        enum CodingKeys: String, CodingKey {
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "click":
                self = .click(try ClickAction(from: decoder))
            case "double_click":
                self = .doubleClick(try DoubleClickAction(from: decoder))
            case "drag":
                self = .drag(try DragAction(from: decoder))
            case "keypress":
                self = .keyPress(try KeyPressAction(from: decoder))
            case "move":
                self = .move(try MoveAction(from: decoder))
            case "screenshot":
                self = .screenshot(try ScreenshotAction(from: decoder))
            case "scroll":
                self = .scroll(try ScrollAction(from: decoder))
            case "type":
                self = .type(try TypeAction(from: decoder))
            case "wait":
                self = .wait(try WaitAction(from: decoder))
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown computer action type: \(type)"))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .click(let action):
                try action.encode(to: encoder)
            case .doubleClick(let action):
                try action.encode(to: encoder)
            case .drag(let action):
                try action.encode(to: encoder)
            case .keyPress(let action):
                try action.encode(to: encoder)
            case .move(let action):
                try action.encode(to: encoder)
            case .screenshot(let action):
                try action.encode(to: encoder)
            case .scroll(let action):
                try action.encode(to: encoder)
            case .type(let action):
                try action.encode(to: encoder)
            case .wait(let action):
                try action.encode(to: encoder)
            }
        }
    }

    // MARK: - Computer Action Types
    enum MouseButton: String, Codable {
        case left
        case right
        case wheel
        case back
        case forward
    }

    struct ClickAction: Codable {
        let button: MouseButton
        let type: String
        let x: Int
        let y: Int
    }

    struct DoubleClickAction: Codable {
        let type: String
        let x: Int
        let y: Int
    }

    struct DragAction: Codable {
        let path: [Coordinate]
        let type: String
    }

    struct Coordinate: Codable {
        let x: Int
        let y: Int
    }

    struct KeyPressAction: Codable {
        let keys: [String]
        let type: String
    }

    struct MoveAction: Codable {
        let type: String
        let x: Int
        let y: Int
    }

    struct ScreenshotAction: Codable {
        let type: String
    }

    struct ScrollAction: Codable {
        let scrollX: Int
        let scrollY: Int
        let type: String
        let x: Int
        let y: Int

        enum CodingKeys: String, CodingKey {
            case scrollX = "scroll_x"
            case scrollY = "scroll_y"
            case type
            case x
            case y
        }
    }

    struct TypeAction: Codable {
        let text: String
        let type: String
    }

    struct WaitAction: Codable {
        let type: String
    }

    struct PendingSafetyCheck: Codable {
        let code: String
        let id: String
        let message: String
    }

    // MARK: - Reasoning Item
    struct ReasoningItem: Codable {
        let id: String
        let summary: [ReasoningSummary]
        let type: String
        let encryptedContent: String?
        let status: String

        enum CodingKeys: String, CodingKey {
            case id
            case summary
            case type
            case encryptedContent = "encrypted_content"
            case status
        }
    }

    struct ReasoningSummary: Codable {
        let text: String
        let type: String
    }

    // MARK: - Image Generation Call
    struct ImageGenerationCall: Codable {
        let id: String
        let result: String?
        let status: String
        let type: String
    }

    // MARK: - Code Interpreter Tool Call
    struct CodeInterpreterToolCall: Codable {
        let code: String
        let id: String
        let results: [CodeInterpreterResult]
        let status: String
        let type: String
        let containerID: String

        enum CodingKeys: String, CodingKey {
            case code
            case id
            case results
            case status
            case type
            case containerID = "container_id"
        }
    }

    // MARK: - Code Interpreter Result (Polymorphic)
    enum CodeInterpreterResult: Codable {
        case textOutput(CodeInterpreterTextOutput)
        case fileOutput(CodeInterpreterFileOutput)

        enum CodingKeys: String, CodingKey {
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "logs":
                self = .textOutput(try CodeInterpreterTextOutput(from: decoder))
            case "files":
                self = .fileOutput(try CodeInterpreterFileOutput(from: decoder))
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown code interpreter result type: \(type)"))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .textOutput(let output):
                try output.encode(to: encoder)
            case .fileOutput(let output):
                try output.encode(to: encoder)
            }
        }
    }

    struct CodeInterpreterTextOutput: Codable {
        let logs: String
        let type: String
    }

    struct CodeInterpreterFileOutput: Codable {
        let files: [CodeInterpreterFile]
        let type: String
    }

    struct CodeInterpreterFile: Codable {
        let fileID: String
        let mimeType: String

        enum CodingKeys: String, CodingKey {
            case fileID = "file_id"
            case mimeType = "mime_type"
        }
    }

    // MARK: - Local Shell Call
    struct LocalShellCall: Codable {
        let action: LocalShellAction
        let callID: String
        let id: String
        let status: String
        let type: String

        enum CodingKeys: String, CodingKey {
            case action
            case callID = "call_id"
            case id
            case status
            case type
        }
    }

    struct LocalShellAction: Codable {
        let command: [String]
        let env: [String: String]
        let type: String
        let timeoutMs: Int?
        let user: String?
        let workingDirectory: String?

        enum CodingKeys: String, CodingKey {
            case command
            case env
            case type
            case timeoutMs = "timeout_ms"
            case user
            case workingDirectory = "working_directory"
        }
    }

    // MARK: - MCP Tool Call
    struct MCPToolCall: Codable {
        let arguments: String
        let id: String
        let name: String
        let serverLabel: String
        let type: String
        let error: String?
        let output: String?

        enum CodingKeys: String, CodingKey {
            case arguments
            case id
            case name
            case serverLabel = "server_label"
            case type
            case error
            case output
        }
    }

    // MARK: - MCP List Tools
    struct MCPListTools: Codable {
        let id: String
        let serverLabel: String
        let tools: [MCPTool]
        let type: String
        let error: String?

        enum CodingKeys: String, CodingKey {
            case id
            case serverLabel = "server_label"
            case tools
            case type
            case error
        }
    }

    struct MCPTool: Codable {
        let inputSchema: [String: Any]
        let name: String
        let annotations: [String: Any]?
        let description: String?
        let type: String

        enum CodingKeys: String, CodingKey {
            case inputSchema = "input_schema"
            case name
            case annotations
            case description
            case type
        }

        // Custom init/encode needed for [String: Any]
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            type = try container.decode(String.self, forKey: .type)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            inputSchema = try container.decode([String: Any].self, forKey: .inputSchema)
            annotations = try container.decodeIfPresent([String: Any].self, forKey: .annotations)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
            // Note: Encoding [String: Any] requires custom implementation
        }
    }

    // MARK: - MCP Approval Request
    struct MCPApprovalRequest: Codable {
        let arguments: String
        let id: String
        let name: String
        let serverLabel: String
        let type: String

        enum CodingKeys: String, CodingKey {
            case arguments
            case id
            case name
            case serverLabel = "server_label"
            case type
        }
    }

    // MARK: - Tool Definitions (for tools array)
    enum Tool: Codable {
        case function(FunctionTool)
        case fileSearch(FileSearchTool)
        case webSearchPreview(WebSearchPreviewTool)
        case computerUsePreview(ComputerUsePreviewTool)
        case mcp(MCPToolDefinition)
        case codeInterpreter(CodeInterpreterTool)
        case imageGeneration(ImageGenerationTool)
        case localShell(LocalShellTool)

        enum CodingKeys: String, CodingKey {
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "function":
                self = .function(try FunctionTool(from: decoder))
            case "file_search":
                self = .fileSearch(try FileSearchTool(from: decoder))
            case "web_search_preview":
                self = .webSearchPreview(try WebSearchPreviewTool(from: decoder))
            case "computer_use_preview":
                self = .computerUsePreview(try ComputerUsePreviewTool(from: decoder))
            case "mcp":
                self = .mcp(try MCPToolDefinition(from: decoder))
            case "code_interpreter":
                self = .codeInterpreter(try CodeInterpreterTool(from: decoder))
            case "image_generation":
                self = .imageGeneration(try ImageGenerationTool(from: decoder))
            case "local_shell":
                self = .localShell(try LocalShellTool(from: decoder))
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown tool type: \(type)"))
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

    // MARK: - Tool Definitions
    struct FunctionTool: Codable {
        let name: String
        let parameters: [String: Any]
        let strict: Bool
        let type: String
        let description: String?

        // Custom init/encode needed for [String: Any]
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            strict = try container.decode(Bool.self, forKey: .strict)
            type = try container.decode(String.self, forKey: .type)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            parameters = try container.decode([String: Any].self, forKey: .parameters)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(strict, forKey: .strict)
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
            // Note: Encoding [String: Any] requires custom implementation
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case strict
            case type
            case description
            case parameters
        }
    }

    struct FileSearchTool: Codable {
        let type: String
        let vectorStoreIds: [String]
        let filters: FileSearchFilter?
        let maxNumResults: Int?
        let rankingOptions: RankingOptions?

        enum CodingKeys: String, CodingKey {
            case type
            case vectorStoreIds = "vector_store_ids"
            case filters
            case maxNumResults = "max_num_results"
            case rankingOptions = "ranking_options"
        }
    }

    // MARK: - File Search Filter (Polymorphic)
    enum FileSearchFilter: Codable {
        case comparison(ComparisonFilter)
        case compound(CompoundFilter)

        enum CodingKeys: String, CodingKey {
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "and", "or":
                self = .compound(try CompoundFilter(from: decoder))
            default:
                self = .comparison(try ComparisonFilter(from: decoder))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .comparison(let filter):
                try filter.encode(to: encoder)
            case .compound(let filter):
                try filter.encode(to: encoder)
            }
        }
    }

    struct ComparisonFilter: Codable {
        let key: String
        let type: String
        let value: FilterValue
    }

    // MARK: - Filter Value (Polymorphic for string/number/boolean)
    enum FilterValue: Codable {
        case string(String)
        case number(Double)
        case boolean(Bool)

        init(from decoder: Decoder) throws {
            if let stringValue = try? decoder.singleValueContainer().decode(String.self) {
                self = .string(stringValue)
            } else if let numberValue = try? decoder.singleValueContainer().decode(Double.self) {
                self = .number(numberValue)
            } else {
                self = .boolean(try decoder.singleValueContainer().decode(Bool.self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value):
                try container.encode(value)
            case .number(let value):
                try container.encode(value)
            case .boolean(let value):
                try container.encode(value)
            }
        }
    }

    struct CompoundFilter: Codable {
        let filters: [FileSearchFilter]
        let type: String
    }

    struct RankingOptions: Codable {
        let ranker: String
        let scoreThreshold: Double

        enum CodingKeys: String, CodingKey {
            case ranker
            case scoreThreshold = "score_threshold"
        }
    }

    struct WebSearchPreviewTool: Codable {
        let type: String
        let searchContextSize: String?
        let userLocation: UserLocation?

        enum CodingKeys: String, CodingKey {
            case type
            case searchContextSize = "search_context_size"
            case userLocation = "user_location"
        }
    }

    struct UserLocation: Codable {
        let type: String
        let city: String?
        let country: String?
        let region: String?
        let timezone: String?
    }

    struct ComputerUsePreviewTool: Codable {
        let displayHeight: Int
        let displayWidth: Int
        let environment: String
        let type: String

        enum CodingKeys: String, CodingKey {
            case displayHeight = "display_height"
            case displayWidth = "display_width"
            case environment
            case type
        }
    }

    struct MCPToolDefinition: Codable {
        let serverLabel: String
        let serverUrl: String
        let type: String
        let allowedTools: MCPAllowedTools?
        let headers: [String: String]?
        let requireApproval: MCPApprovalConfig?

        enum CodingKeys: String, CodingKey {
            case serverLabel = "server_label"
            case serverUrl = "server_url"
            case type
            case allowedTools = "allowed_tools"
            case headers
            case requireApproval = "require_approval"
        }
    }

    // MARK: - MCP Allowed Tools (Polymorphic)
    enum MCPAllowedTools: Codable {
        case array([String])
        case filter(MCPAllowedToolsFilter)

        init(from decoder: Decoder) throws {
            if let arrayValue = try? decoder.singleValueContainer().decode([String].self) {
                self = .array(arrayValue)
            } else {
                self = .filter(try MCPAllowedToolsFilter(from: decoder))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .array(let tools):
                var container = encoder.singleValueContainer()
                try container.encode(tools)
            case .filter(let filter):
                try filter.encode(to: encoder)
            }
        }
    }

    struct MCPAllowedToolsFilter: Codable {
        let toolNames: [String]

        enum CodingKeys: String, CodingKey {
            case toolNames = "tool_names"
        }
    }

    // MARK: - MCP Approval Config (Polymorphic)
    enum MCPApprovalConfig: Codable {
        case setting(String)
        case filter(MCPToolApprovalFilter)

        init(from decoder: Decoder) throws {
            if let stringValue = try? decoder.singleValueContainer().decode(String.self) {
                self = .setting(stringValue)
            } else {
                self = .filter(try MCPToolApprovalFilter(from: decoder))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .setting(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case .filter(let filter):
                try filter.encode(to: encoder)
            }
        }
    }

    struct MCPToolApprovalFilter: Codable {
        let always: MCPToolList?
        let never: MCPToolList?
    }

    struct MCPToolList: Codable {
        let toolNames: [String]

        enum CodingKeys: String, CodingKey {
            case toolNames = "tool_names"
        }
    }

    // MARK: - Code Interpreter Tool (Polymorphic container)
    struct CodeInterpreterTool: Codable {
        let container: CodeInterpreterContainer
        let type: String
    }

    enum CodeInterpreterContainer: Codable {
        case string(String)
        case auto(CodeInterpreterContainerAuto)

        init(from decoder: Decoder) throws {
            if let stringValue = try? decoder.singleValueContainer().decode(String.self) {
                self = .string(stringValue)
            } else {
                self = .auto(try CodeInterpreterContainerAuto(from: decoder))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .string(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case .auto(let container):
                try container.encode(to: encoder)
            }
        }
    }

    struct CodeInterpreterContainerAuto: Codable {
        let type: String
        let fileIds: [String]?

        enum CodingKeys: String, CodingKey {
            case type
            case fileIds = "file_ids"
        }
    }

    struct ImageGenerationTool: Codable {
        let type: String
        let background: String?
        let inputImageMask: InputImageMask?
        let model: String?
        let moderation: String?
        let outputCompression: Int?
        let outputFormat: String?
        let partialImages: Int?
        let quality: String?
        let size: String?

        enum CodingKeys: String, CodingKey {
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

    struct InputImageMask: Codable {
        let fileID: String?
        let imageUrl: String?

        enum CodingKeys: String, CodingKey {
            case fileID = "file_id"
            case imageUrl = "image_url"
        }
    }

    struct LocalShellTool: Codable {
        let type: String
    }

    // MARK: - Usage
    struct Usage: Codable {
        let inputTokens: Int
        let inputTokensDetails: InputTokensDetails?
        let outputTokens: Int
        let outputTokensDetails: OutputTokensDetails?
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case inputTokensDetails = "input_tokens_details"
            case outputTokens = "output_tokens"
            case outputTokensDetails = "output_tokens_details"
            case totalTokens = "total_tokens"
        }
    }

    struct InputTokensDetails: Codable {
        let cachedTokens: Int

        enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
        }
    }

    struct OutputTokensDetails: Codable {
        let reasoningTokens: Int

        enum CodingKeys: String, CodingKey {
            case reasoningTokens = "reasoning_tokens"
        }
    }
}

struct ResponsesResponse: LLM.AnyResponse {
    var body: ResponsesResponseBody
    var isStreamingResponse: Bool

    var choiceMessages: [LLM.Message] {
        body.output.flatMap { item -> [LLM.Message] in
            switch item {
            case .functionToolCall(let call):
                return [LLM.Message(role: .function,
                                    functionCallID: LLM.Message.FunctionCallID(callID: call.callID, itemID: call.id),
                                    function_call: LLM.FunctionCall(name: call.name,
                                                                    arguments: call.arguments))]
            case .message(let message):
                return message.content.map { content in
                    switch content {
                    case .outputText(let outputText):
                        LLM.Message(role: .assistant,
                                    content: outputText.text)
                    case .refusal(let refusal):
                        LLM.Message(role: .assistant,
                                    content:  "The request was refused: \(refusal.refusal)")
                    }
                }
            case .fileSearchToolCall,  .webSearchToolCall,  .computerToolCall,  .reasoning,
                    .imageGenerationCall,  .codeInterpreterToolCall,  .localShellCall,
                    .mcpToolCall,  .mcpListTools,  .mcpApprovalRequest:
                return []
            }
        }
    }
}

// MARK: - Helper extension for [String: Any] decoding
extension KeyedDecodingContainer {
    func decode(_ type: [String: Any].Type, forKey key: K) throws -> [String: Any] {
        let container = try self.nestedContainer(keyedBy: JSONCodingKeys.self, forKey: key)
        return try container.decode(type)
    }

    func decodeIfPresent(_ type: [String: Any].Type, forKey key: K) throws -> [String: Any]? {
        guard contains(key) else {
            return nil
        }
        guard try decodeNil(forKey: key) == false else {
            return nil
        }
        return try decode(type, forKey: key)
    }
}

extension KeyedDecodingContainer where K == JSONCodingKeys {
    func decode(_ type: [String: Any].Type) throws -> [String: Any] {
        var dictionary = [String: Any]()

        for key in allKeys {
            if let boolValue = try? decode(Bool.self, forKey: key) {
                dictionary[key.stringValue] = boolValue
            } else if let stringValue = try? decode(String.self, forKey: key) {
                dictionary[key.stringValue] = stringValue
            } else if let intValue = try? decode(Int.self, forKey: key) {
                dictionary[key.stringValue] = intValue
            } else if let doubleValue = try? decode(Double.self, forKey: key) {
                dictionary[key.stringValue] = doubleValue
            } else if let nestedDictionary = try? decode([String: Any].self, forKey: key) {
                dictionary[key.stringValue] = nestedDictionary
            } else if let nestedArray = try? decode([Any].self, forKey: key) {
                dictionary[key.stringValue] = nestedArray
            }
        }
        return dictionary
    }
}

extension KeyedDecodingContainer where K == JSONCodingKeys {
    func decode(_ type: [Any].Type, forKey key: JSONCodingKeys) throws -> [Any] {
        var container = try self.nestedUnkeyedContainer(forKey: key)
        return try container.decode(type)
    }
}

extension UnkeyedDecodingContainer {
    mutating func decode(_ type: [Any].Type) throws -> [Any] {
        var array: [Any] = []
        while isAtEnd == false {
            if let value = try? decode(Bool.self) {
                array.append(value)
            } else if let value = try? decode(Int.self) {
                array.append(value)
            } else if let value = try? decode(Double.self) {
                array.append(value)
            } else if let value = try? decode(String.self) {
                array.append(value)
            } else if let nestedDictionary = try? decode([String: Any].self) {
                array.append(nestedDictionary)
            } else if let nestedArray = try? decode([Any].self) {
                array.append(nestedArray)
            }
        }
        return array
    }

    mutating func decode(_ type: [String: Any].Type) throws -> [String: Any] {
        let nestedContainer = try self.nestedContainer(keyedBy: JSONCodingKeys.self)
        return try nestedContainer.decode(type)
    }
}

struct JSONCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.init(stringValue: "\(intValue)")
        self.intValue = intValue
    }
}
// TODO: Add a streaming parser

struct ResponsesResponseParser: LLMResponseParser {
    var parsedResponse: ResponsesResponse?

    mutating func parse(data: Data) throws -> (any LLM.AnyResponse)? {
        let decoder = JSONDecoder()
        DLog("RESPONSE:\n\(data.lossyString)")
        let response =  try decoder.decode(ResponsesResponseBody.self, from: data)
        parsedResponse = ResponsesResponse(body: response, isStreamingResponse: false)
        return parsedResponse
    }

    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return (nil, "")
    }
}

