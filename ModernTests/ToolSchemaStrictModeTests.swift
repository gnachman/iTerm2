//
//  ToolSchemaStrictModeTests.swift
//  iTerm2 ModernTests
//
//  Hermetic guard for the class of bug that shipped a 400 from OpenAI:
//  a tool whose JSON schema listed a property in `properties` but left it
//  out of `required`. OpenAI's Responses API runs function schemas in
//  strict mode, which requires that `required` include EVERY key in
//  `properties` (optionality is expressed by widening the type to include
//  "null", not by omitting the key), and that every object sets
//  `additionalProperties: false`.
//
//  Nothing in the live harness caught the original break because its
//  tool-call tests only ever send schemas generated from all-required
//  structs, where the failure mode is unreachable. These tests validate
//  the tool schemas AS THEY GO ON THE WIRE: they build the real OpenAI
//  Responses request body (ResponsesBodyRequestBuilder, the same code the
//  app ships) for the ACTUAL production tools from both code paths:
//    1. The hand-authored orchestrator schemas (OrchestratorToolDefinitions).
//    2. The reflection-generated schemas (JSONSchema(for:)) used by the
//       single-session RemoteCommand tools.
//  Validating the serialized body (rather than the in-memory JSONSchema)
//  is deliberate: the serializer injects strict=true and the root
//  additionalProperties=false, so only the wire form reflects what the
//  vendor actually validates. These run on every build; no network.
//

import XCTest
@testable import iTerm2SharedARC

final class ToolSchemaStrictModeTests: XCTestCase {

    // MARK: - Recursive strict-mode validator

    // Walks a JSON-schema dictionary and collects every strict-mode
    // violation (so one run reports them all rather than failing on the
    // first). Recurses into nested object properties and array `items`.
    private func strictViolations(in schema: [String: Any],
                                  path: String) -> [String] {
        var problems: [String] = []

        let types = Self.typeStrings(schema["type"])
        let hasProperties = schema["properties"] != nil
        let isObject = types.contains("object") || hasProperties
        guard isObject else {
            // Non-object leaf (string/number/etc.): nothing to check here.
            return problems
        }

        if (schema["additionalProperties"] as? Bool) != false {
            problems.append("\(path): object schema must set additionalProperties=false")
        }

        let properties = (schema["properties"] as? [String: Any]) ?? [:]
        let required = Set((schema["required"] as? [String]) ?? [])

        for key in properties.keys.sorted() where !required.contains(key) {
            problems.append("\(path).\(key): property is missing from `required` "
                            + "(OpenAI strict mode rejects this)")
        }
        for key in required.sorted() where properties[key] == nil {
            problems.append("\(path): `required` lists \(key) which is not in `properties`")
        }

        // Recurse into sub-schemas.
        for (key, value) in properties {
            guard let sub = value as? [String: Any] else { continue }
            problems += strictViolations(in: sub, path: "\(path).\(key)")
            if let items = sub["items"] as? [String: Any] {
                problems += strictViolations(in: items, path: "\(path).\(key)[]")
            }
        }
        return problems
    }

    // `type` may be a String ("object"), an array of strings
    // (["string","null"]), or an array of AnyCodable-decoded values.
    private static func typeStrings(_ raw: Any?) -> Set<String> {
        if let s = raw as? String { return [s] }
        if let arr = raw as? [String] { return Set(arr) }
        if let arr = raw as? [Any] { return Set(arr.compactMap { $0 as? String }) }
        return []
    }

    // MARK: - Wire serialization

    private func model(named name: String) throws -> AIMetadata.Model {
        guard let m = AIMetadata.instance.models.first(where: { $0.name == name }) else {
            throw XCTSkip("Model \(name) not in AIMetadata; test skipped")
        }
        return m
    }

    private func noopFunction(_ decl: ChatGPTFunctionDeclaration) -> LLM.AnyFunction {
        LLM.Function<AnyCodable>(
            decl: decl,
            call: { _, _, completion in try? completion(.success("{}")) },
            parameterType: AnyCodable.self)
    }

    // Serialize the declarations through the real OpenAI Responses request
    // builder and return each function tool's on-the-wire (name, parameters)
    // schema, exactly as the vendor receives it.
    private func openAIWireToolSchemas(
        _ decls: [ChatGPTFunctionDeclaration]
    ) throws -> [(name: String, parameters: [String: Any])] {
        let model = try model(named: "gpt-4o-mini")
        let bodyData = try ResponsesBodyRequestBuilder(
            messages: [LLM.Message(responseID: nil, role: .user, body: .text("hi"))],
            provider: LLMProvider(model: model),
            functions: decls.map(noopFunction),
            stream: false,
            hostedTools: HostedTools(),
            previousResponseID: nil,
            shouldThink: nil).body()
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let tools = (root["tools"] as? [[String: Any]]) ?? []
        var result: [(String, [String: Any])] = []
        for tool in tools where (tool["type"] as? String) == "function" {
            let name = (tool["name"] as? String) ?? "<unnamed>"
            let params = (tool["parameters"] as? [String: Any]) ?? [:]
            result.append((name, params))
            // Every function tool must be sent strict; that is what makes the
            // required/additionalProperties rules load-bearing in the first place.
            XCTAssertEqual(tool["strict"] as? Bool, true,
                           "tool \(name) was not sent with strict=true")
        }
        return result
    }

    private func assertWireStrict(_ decls: [ChatGPTFunctionDeclaration],
                                  label: String,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) throws {
        let tools = try openAIWireToolSchemas(decls)
        XCTAssertFalse(tools.isEmpty, "\(label): no function tools were serialized",
                       file: file, line: line)
        for tool in tools {
            let problems = strictViolations(in: tool.parameters,
                                            path: "\(label).\(tool.name)")
            XCTAssertTrue(problems.isEmpty,
                          "strict-mode violations:\n" + problems.joined(separator: "\n"),
                          file: file, line: line)
        }
    }

    // MARK: - Hand-authored orchestrator schemas

    private func orchestratorDecls(_ definitions: [ToolDefinition]) -> [ChatGPTFunctionDeclaration] {
        definitions.map {
            ChatGPTFunctionDeclaration(name: $0.name,
                                       description: $0.description,
                                       parameters: JSONSchema(rawJSON: $0.inputSchema))
        }
    }

    func test_orchestratorWireSchemas_areStrictModeValid() throws {
        // Validate in BOTH companion-pairing states, because register_watch
        // conditionally adds the notify_user property (and must add it to
        // `required` in lockstep) only when a device is paired.
        try withDevicePaired(false) {
            try assertWireStrict(orchestratorDecls(OrchestratorCommand.allToolDefinitions),
                                 label: "orchestration")
            try assertWireStrict(orchestratorDecls(OrchestratorCommand.sessionBoundWatchToolDefinitions),
                                 label: "sessionBound")
        }
        try withDevicePaired(true) {
            try assertWireStrict(orchestratorDecls(OrchestratorCommand.allToolDefinitions),
                                 label: "orchestration")
            try assertWireStrict(orchestratorDecls(OrchestratorCommand.sessionBoundWatchToolDefinitions),
                                 label: "sessionBound")
        }
    }

    // MARK: - Reflection-generated schemas (real production prototypes)

    func test_remoteCommandWireSchemas_areStrictModeValid() throws {
        var decls: [ChatGPTFunctionDeclaration] = []
        for content in RemoteCommand.Content.allCases {
            // Each Content case wraps exactly one prototype value; reflect it
            // out and run it through the same generator the tool provider uses.
            guard let prototype = Mirror(reflecting: content).children.first?.value else {
                continue
            }
            decls.append(ChatGPTFunctionDeclaration(
                name: content.functionName,
                description: content.functionDescription,
                parameters: JSONSchema(for: prototype, descriptions: content.argDescriptions)))
        }
        try assertWireStrict(decls, label: "remoteCommand")
    }

    // MARK: - Generator contract for optional fields (guards the root fix)

    private struct OptionalBearing: Codable {
        var requiredString: String = ""
        var optionalString: String? = nil
        var optionalInt: Int? = nil
        var optionalBool: Bool? = nil
    }

    func test_generator_optionalFields_areNullableAndRequired() throws {
        let schema = JSONSchema(for: OptionalBearing(), descriptions: [:])
        let data = try JSONEncoder().encode(schema)
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Every field, optional or not, is in `required` (strict-mode rule).
        let required = Set((dict["required"] as? [String]) ?? [])
        XCTAssertEqual(required,
                       ["requiredString", "optionalString", "optionalInt", "optionalBool"])

        // The optional fields carry a nullable type; the required one does not.
        let props = try XCTUnwrap(dict["properties"] as? [String: Any])
        XCTAssertFalse(Self.typeStrings((props["requiredString"] as? [String: Any])?["type"]).contains("null"))
        for optional in ["optionalString", "optionalInt", "optionalBool"] {
            let types = Self.typeStrings((props[optional] as? [String: Any])?["type"])
            XCTAssertTrue(types.contains("null"),
                          "\(optional) is optional but its type does not include null: \(types)")
        }
    }

    // MARK: - Helpers

    // Toggle CompanionPushRegistry.devicePaired by writing the pairing key it
    // reads, restoring the prior value afterward.
    private func withDevicePaired(_ paired: Bool, _ body: () throws -> Void) rethrows {
        let defaults = iTermUserDefaults.userDefaults()
        let key = CompanionPairingController.pairedPIDKey
        let saved = defaults.string(forKey: key)
        if paired {
            defaults.set("test-pid", forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        XCTAssertEqual(CompanionPushRegistry.devicePaired, paired)
        defer {
            if let saved {
                defaults.set(saved, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        try body()
    }
}
