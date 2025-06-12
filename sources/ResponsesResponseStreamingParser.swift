//
//  ResponsesResponseStreamingParser.swift
//  iTerm2
//
//  Created by George Nachman on 5/30/25.
//

struct ResponsesResponseStreamingParser: LLMStreamingResponseParser {
    // MARK: - Base Event Protocol
    protocol ResponseEvent: Codable {
        var type: String { get }
        var sequenceNumber: Int { get }
    }

    // MARK: - Common Supporting Types

    struct Tool: Codable {
        let type: String
        let description: String?
        let name: String?
        let parameters: [String: AnyCodable]?
        let strict: Bool?
        let container: Container?

        struct Container: Codable {
            let type: String
        }
    }

    struct Reasoning: Codable {
        let effort: String?
        let summary: String?
    }

    struct TextFormat: Codable {
        let format: Format

        struct Format: Codable {
            let type: String
        }
    }

    // MARK: - Response Object (used in multiple events)

    struct ResponseObject: Codable {
        var id: String
        var object: String
        var status: String
        var background: Bool
        var error: String?
        var incompleteDetails: String?
        var instructions: String?
        var output: [AnyCodable]
        var parallelToolCalls: Bool
        var previousResponseId: String?
        var reasoning: Reasoning?
        var text: TextFormat?
        var toolChoice: String?
        var tools: [Tool]?
        var truncation: String?

        enum CodingKeys: String, CodingKey {
            case id, object, status, background, error, instructions, output, reasoning, text, tools
            case incompleteDetails = "incomplete_details"
            case parallelToolCalls = "parallel_tool_calls"
            case previousResponseId = "previous_response_id"
            case toolChoice = "tool_choice"
            case truncation
        }
    }

    // MARK: - Event Types

    // 1. Response Created
    struct ResponseCreatedEvent: ResponseEvent {
        let type: String = "response.created"
        var sequenceNumber: Int
        var response: ResponseObject

        enum CodingKeys: String, CodingKey {
            case type
            case sequenceNumber = "sequence_number"
            case response
        }
    }

    struct ResponseWebSearchCallInProgressEvent: ResponseEvent {
        let type = "response.web_search_call.in_progress"
        let sequenceNumber: Int
        let outputIndex: Int
        let itemID: String

        enum CodingKeys: String, CodingKey {
            case type
            case sequenceNumber = "sequence_number"
            case outputIndex = "output_index"
            case itemID = "item_id"
        }
    }

    struct ResponseWebSearchCallCompletedEvent: ResponseEvent {
        let type = "response.web_search_call.completed"
        let sequenceNumber: Int
        let outputIndex: Int
        let itemID: String

        enum CodingKeys: String, CodingKey {
            case type
            case sequenceNumber = "sequence_number"
            case outputIndex = "output_index"
            case itemID = "item_id"
        }
    }

    struct ResponseCodeInterpreterInProgressEvent: ResponseEvent {
        let type = "response.code_interpreter_call.in_progress"
        let sequenceNumber: Int
        let outputIndex: Int
        let itemID: String

        enum CodingKeys: String, CodingKey {
            case type
            case sequenceNumber = "sequence_number"
            case outputIndex = "output_index"
            case itemID = "item_id"
        }
    }

    struct ResponseCodeInterpreterDeltaEvent: ResponseEvent {
        let type = "response.code_interpreter_call_code.delta"
        let sequenceNumber: Int
        let outputIndex: Int
        let itemID: String
        var delta: String
        enum CodingKeys: String, CodingKey {
            case type
            case sequenceNumber = "sequence_number"
            case outputIndex = "output_index"
            case itemID = "item_id"
            case delta
        }
    }
    struct ResponseCodeInterpeterCallInterpretingEvent: ResponseEvent {
        let type = "response.code_interpreter_call.interpreting"
        let sequenceNumber: Int
        let outputIndex: Int
        let itemID: String

        enum CodingKeys: String, CodingKey {
            case type
            case sequenceNumber = "sequence_number"
            case outputIndex = "output_index"
            case itemID = "item_id"
        }
    }

    struct ResponseCodeInterpeterCallCompletedEvent: ResponseEvent {
        let type = "response.code_interpreter_call.completed"
        let sequenceNumber: Int
        let outputIndex: Int
        let itemID: String

        enum CodingKeys: String, CodingKey {
            case type
            case sequenceNumber = "sequence_number"
            case outputIndex = "output_index"
            case itemID = "item_id"
        }
    }

    // 2. Output Text Delta
    struct ResponseOutputTextDeltaEvent: ResponseEvent {
        let type: String = "response.output_text.delta"
        let sequenceNumber: Int
        let delta: String

        enum CodingKeys: String, CodingKey {
            case type
            case sequenceNumber = "sequence_number"
            case delta
        }
    }

    struct ResponseOutputItemAddedEvent: ResponseEvent {
        let type: String = "response.output_item.added"
        var sequenceNumber: Int
        let output_index: Int
        let item: OutputItem

        enum CodingKeys: String, CodingKey {
            case type, output_index, item
            case sequenceNumber = "sequence_number"
        }

        struct OutputItem: Codable {
            let id: String  // e.g., fc_xxx. Use this when responding.
            enum OutputItemType: String, Codable {
                case message
                case fileSearchCall = "file_search_call"
                case functionCall = "function_call"
                case webSearchCall = "web_search_call"
                case computerCall = "computer_call"
                case reasoning
                case imageGenerationCall = "image_generation_call"
                case codeInterpreterCall = "code_interpreter_call"
                case localShellCall = "local_shell_call"
                case mcpCall = "mcp_call"
                case mcpListTools = "mcp_list_tools"
                case mcpApprovalRequest = "mcp_approval_request"
            }

            // There are per-type payloads but I generally don't care about them.
            let type: OutputItemType
            let status: String  // in_progress
            let arguments: String?
            let call_id: String?  // e.g., call_xxx. Purpose unclear.
            let name: String?  // function name
        }
    }

    // 3. Output Text Done
    struct ResponseOutputTextDoneEvent: ResponseEvent {
        let type: String = "response.output_text.done"
        let sequenceNumber: Int

        enum CodingKeys: String, CodingKey {
            case type
            case sequenceNumber = "sequence_number"
        }
    }

    // 4. Function Call Arguments Delta
    struct ResponseFunctionCallArgumentsDeltaEvent: ResponseEvent {
        let type: String = "response.function_call_arguments.delta"
        let sequenceNumber: Int
        let itemId: String
        let delta: String

        enum CodingKeys: String, CodingKey {
            case type
            case sequenceNumber = "sequence_number"
            case itemId = "item_id"
            case delta
        }
    }

    // 5. Function Call Arguments Done
    struct ResponseFunctionCallArgumentsDoneEvent: ResponseEvent {
        let type: String = "response.function_call_arguments.done"
        let sequenceNumber: Int
        let itemID: String
        let outputIndex: Int
        let arguments: String

        enum CodingKeys: String, CodingKey {
            case type
            case sequenceNumber = "sequence_number"
            case itemID = "item_id"
            case outputIndex = "output_index"
            case arguments
        }
    }

    // 6. Response Done
    struct ResponseDoneEvent: ResponseEvent {
        let type: String = "response.done"
        let sequenceNumber: Int
        let response: ResponseObject

        enum CodingKeys: String, CodingKey {
            case type
            case sequenceNumber = "sequence_number"
            case response
        }
    }

    // MARK: - Event Wrapper for Parsing

    enum ResponseEventType: String, CaseIterable {
        case responseCreated = "response.created"
        case outputTextDelta = "response.output_text.delta"
        case outputTextDone = "response.output_text.done"
        case functionCallArgumentsDelta = "response.function_call_arguments.delta"
        case functionCallArgumentsDone = "response.function_call_arguments.done"
        case outputItemAdded = "response.output_item.added"
        case responseDone = "response.done"
        case webSearchCallInProgress = "response.web_search_call.in_progress"
        case webSearchCallCompletedEvent = "response.web_search_call.completed"
        case codeInterpreterCallInProgress = "response.code_interpreter_call.in_progress"
        case codeInterpreterCallCompleted = "response.code_interpreter_call.completed"
        case codeInterpreterCallInterpreting = "response.code_interpreter_call.interpreting"
        case codeInterpreterDelta = "response.code_interpreter_call_code.delta"
    }

    // MARK: - Universal Event Parser

    struct ResponseEventParser {
        static func parseEvent(from jsonString: String) throws -> any ResponseEvent {
            guard let data = jsonString.data(using: .utf8) else {
                throw ResponseEventError.invalidJSON
            }

            // First, decode just the type to determine which struct to use
            let typeContainer = try JSONDecoder().decode(EventTypeContainer.self, from: data)

            switch ResponseEventType(rawValue: typeContainer.type) {
            case .responseCreated:
                return try JSONDecoder().decode(ResponseCreatedEvent.self, from: data)
            case .outputTextDelta:
                return try JSONDecoder().decode(ResponseOutputTextDeltaEvent.self, from: data)
            case .outputTextDone:
                return try JSONDecoder().decode(ResponseOutputTextDoneEvent.self, from: data)
            case .functionCallArgumentsDelta:
                return try JSONDecoder().decode(ResponseFunctionCallArgumentsDeltaEvent.self, from: data)
            case .functionCallArgumentsDone:
                return try JSONDecoder().decode(ResponseFunctionCallArgumentsDoneEvent.self, from: data)
            case .responseDone:
                return try JSONDecoder().decode(ResponseDoneEvent.self, from: data)
            case .outputItemAdded:
                return try JSONDecoder().decode(ResponseOutputItemAddedEvent.self, from: data)
            case .webSearchCallInProgress:
                return try JSONDecoder().decode(ResponseWebSearchCallInProgressEvent.self, from: data)
            case .webSearchCallCompletedEvent:
                return try JSONDecoder().decode(ResponseWebSearchCallCompletedEvent.self, from: data)
            case .codeInterpreterCallInProgress:
                return try JSONDecoder().decode(ResponseCodeInterpreterInProgressEvent.self, from: data)
            case .codeInterpreterCallInterpreting:
                return try JSONDecoder().decode(ResponseCodeInterpeterCallInterpretingEvent.self, from: data)
            case .codeInterpreterCallCompleted:
                return try JSONDecoder().decode(ResponseCodeInterpeterCallCompletedEvent.self, from: data)
            case .codeInterpreterDelta:
                return try JSONDecoder().decode(ResponseCodeInterpreterDeltaEvent.self, from: data)
            case .none:
                DLog("Unrecognized event \(jsonString)")
                throw ResponseEventError.unknownEventType(typeContainer.type)
            }
        }
    }

    // MARK: - Helper Types

    private struct EventTypeContainer: Codable {
        let type: String
    }

    enum ResponseEventError: Error, LocalizedError {
        case invalidJSON
        case unknownEventType(String)

        var errorDescription: String? {
            switch self {
            case .invalidJSON:
                return "Invalid JSON data"
            case .unknownEventType(let type):
                return "Unknown event type: \(type)"
            }
        }
    }

    // MARK: - AnyCodable for handling dynamic JSON

    struct AnyCodable: Codable {
        let value: Any

        init<T>(_ value: T?) {
            self.value = value ?? ()
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            if container.decodeNil() {
                self.init(())
            } else if let bool = try? container.decode(Bool.self) {
                self.init(bool)
            } else if let int = try? container.decode(Int.self) {
                self.init(int)
            } else if let double = try? container.decode(Double.self) {
                self.init(double)
            } else if let string = try? container.decode(String.self) {
                self.init(string)
            } else if let array = try? container.decode([AnyCodable].self) {
                self.init(array.map { $0.value })
            } else if let dictionary = try? container.decode([String: AnyCodable].self) {
                self.init(dictionary.mapValues { $0.value })
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()

            switch value {
            case is Void:
                try container.encodeNil()
            case let bool as Bool:
                try container.encode(bool)
            case let int as Int:
                try container.encode(int)
            case let double as Double:
                try container.encode(double)
            case let string as String:
                try container.encode(string)
            case let array as [Any]:
                try container.encode(array.map { AnyCodable($0) })
            case let dictionary as [String: Any]:
                try container.encode(dictionary.mapValues { AnyCodable($0) })
            default:
                let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded")
                throw EncodingError.invalidValue(value, context)
            }
        }
    }

    struct Response: LLM.AnyStreamingResponse {
        var ignore = true
        // When a response is created, this is set to the response ID. You can use
        // this in previous_response_id to continue the conversation.
        var newlyCreatedResponseID: String?
        var isStreamingResponse: Bool { true }
        var choiceMessages = [LLM.Message]()
    }
    var parsedResponse: Response?

    mutating func parse(data: Data) throws -> (any LLM.AnyStreamingResponse)? {
        parsedResponse = Response()
        do {
            DLog("RESPONSE:\n\(data.lossyString)")

            let jsonString = data.lossyString
            let event = try ResponseEventParser.parseEvent(from: jsonString)
            var choiceMessages = [LLM.Message]()
            switch event {
            case let deltaEvent as ResponseOutputTextDeltaEvent:
                choiceMessages.append(LLM.Message(role: .assistant,
                                                  content: deltaEvent.delta))
                parsedResponse?.ignore = false

            case let callEvent as ResponseOutputItemAddedEvent:
                switch callEvent.item.type {
                case .functionCall:
                    choiceMessages.append(LLM.Message(role: .function, body: .functionCall(
                        .init(
                            name: callEvent.item.name,
                            arguments: callEvent.item.arguments),
                        id: .init(callID: callEvent.item.call_id ?? "",
                                  itemID: callEvent.item.id))))
                    parsedResponse?.ignore = false
                case .codeInterpreterCall:
                    break
                case .webSearchCall:
                    choiceMessages.append(
                        LLM.Message(role: .assistant,
                                    body: .attachment(.init(
                                        inline: true,
                                        id: UUID().uuidString,
                                        type: .statusUpdate(.webSearchStarted)))))
                    parsedResponse?.ignore = false

                default:
                    break
                }

            case let argumentsDeltaEvent as ResponseFunctionCallArgumentsDeltaEvent:
                choiceMessages.append(LLM.Message(
                    role: .function,
                    body: .functionCall(.init(name: nil,
                                              arguments: argumentsDeltaEvent.delta),
                                        id: .init(callID: "",
                                                  itemID: argumentsDeltaEvent.itemId) )))
                parsedResponse?.ignore = false

            case let createdEvent as ResponseCreatedEvent:
                DLog("Response started: \(createdEvent.response.id)")
                parsedResponse?.newlyCreatedResponseID = createdEvent.response.id
                parsedResponse?.ignore = false

            case let doneEvent as ResponseDoneEvent:
                DLog("\nResponse completed. Status: \(doneEvent.response.status)")
                parsedResponse = nil

            case let funcArgsEvent as ResponseFunctionCallArgumentsDoneEvent:
                DLog("Function call done: \(funcArgsEvent)")

            case let webSearch as ResponseWebSearchCallInProgressEvent:
                DLog("\(webSearch)")

            case let webSearch as ResponseWebSearchCallCompletedEvent:
                DLog("\(webSearch)")
                choiceMessages.append(
                    LLM.Message(role: .assistant,
                                body: .attachment(.init(
                                    inline: true,
                                    id: UUID().uuidString,
                                    type: .statusUpdate(.webSearchFinished)))))
                parsedResponse?.ignore = false

            case let codeInterpreter as ResponseCodeInterpreterInProgressEvent:
                DLog("\(codeInterpreter)")

            case let codeInterpreter as ResponseCodeInterpeterCallInterpretingEvent:
                DLog("\(codeInterpreter)")
                choiceMessages.append(
                    LLM.Message(role: .assistant,
                                body: .attachment(.init(
                                    inline: true,
                                    id: UUID().uuidString,
                                    type: .statusUpdate(.codeInterpreterStarted)))))
                parsedResponse?.ignore = false

            case let codeInterpreter as ResponseCodeInterpeterCallCompletedEvent:
                DLog("\(codeInterpreter)")
                choiceMessages.append(
                    LLM.Message(role: .assistant,
                                body: .attachment(.init(
                                    inline: true,
                                    id: UUID().uuidString,
                                    type: .statusUpdate(.codeInterpreterFinished)))))
                parsedResponse?.ignore = false

            case let deltaEvent as ResponseCodeInterpreterDeltaEvent:
                choiceMessages.append(LLM.Message(role: .assistant,
                                                  body: .attachment(.init(inline: true,
                                                                          id: deltaEvent.itemID,
                                                                          type: .code(deltaEvent.delta)))))

                parsedResponse?.ignore = false

            default:
                DLog("Other event: \(event.type)")
            }
            parsedResponse?.choiceMessages = choiceMessages
        } catch {
            DLog("Failed to parse event: \(error)")
        }
        return parsedResponse
    }

    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return SplitServerSentEvents(from: rawInput)
    }
}
