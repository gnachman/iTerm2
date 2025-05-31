//
//  ResponsesResponseStreamingParser.swift
//  iTerm2
//
//  Created by George Nachman on 5/30/25.
//

struct ResponsesResponseStreamingParser: LLMResponseParser {
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
        let id: String
        let object: String
        let status: String
        let background: Bool
        let error: String?
        let incompleteDetails: String?
        let instructions: String?
        let output: [AnyCodable]
        let parallelToolCalls: Bool
        let previousResponseId: String?
        let reasoning: Reasoning?
        let text: TextFormat?
        let toolChoice: String?
        let tools: [Tool]?
        let truncation: String?

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
        let sequenceNumber: Int
        let response: ResponseObject

        enum CodingKeys: String, CodingKey {
            case type
            case sequenceNumber = "sequence_number"
            case response
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
        let name: String
        let callId: String
        let delta: String

        enum CodingKeys: String, CodingKey {
            case type
            case sequenceNumber = "sequence_number"
            case name
            case callId = "call_id"
            case delta
        }
    }

    // 5. Function Call Arguments Done
    struct ResponseFunctionCallArgumentsDoneEvent: ResponseEvent {
        let type: String = "response.function_call_arguments.done"
        let sequenceNumber: Int
        let name: String
        let callId: String
        let arguments: String

        enum CodingKeys: String, CodingKey {
            case type
            case sequenceNumber = "sequence_number"
            case name
            case callId = "call_id"
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
        case responseDone = "response.done"
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
            case .none:
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

    struct Response: Codable, LLM.AnyResponse {
        var isStreamingResponse: Bool { true }

        var choiceMessages = [LLM.Message]()
    }
    var parsedResponse: Response?

    mutating func parse(data: Data) throws -> (any LLM.AnyResponse)? {
        do {
            print("-- BEGIN PARSE --")
            print(data.lossyString)
            print("-- END PARSE --")

            let jsonString = data.lossyString
            let event = try ResponseEventParser.parseEvent(from: jsonString)
            var choiceMessages = [LLM.Message]()
            switch event {
            case let deltaEvent as ResponseOutputTextDeltaEvent:
                choiceMessages.append(LLM.Message(role: .assistant,
                                                  content: deltaEvent.delta))
                print(deltaEvent.delta, terminator: "")

            case let createdEvent as ResponseCreatedEvent:
                print("Response started: \(createdEvent.response.id)")

            case let doneEvent as ResponseDoneEvent:
                print("\nResponse completed. Status: \(doneEvent.response.status)")

            case let funcArgsEvent as ResponseFunctionCallArgumentsDoneEvent:
                choiceMessages.append(LLM.Message(role: .assistant,
                                                  content: nil,
                                                  function_call: LLM.FunctionCall(name: funcArgsEvent.name,
                                                                                  arguments: funcArgsEvent.arguments)))
                print("Function call: \(funcArgsEvent.name)(\(funcArgsEvent.arguments))")

            default:
                print("Other event: \(event.type)")
            }
            parsedResponse = Response(choiceMessages: choiceMessages)
        } catch {
            print("Failed to parse event: \(error)")
        }
        return parsedResponse
    }

    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return SplitServerSentEvents(from: rawInput)
    }
}
