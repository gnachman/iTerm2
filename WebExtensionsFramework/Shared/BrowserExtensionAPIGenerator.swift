import Foundation

internal protocol StringConvertible {
    func js(indent: Int) -> String
    func swiftProtocols(indent: Int) -> String
    func swiftDispatch(indent: Int) -> String?
}

extension String: StringConvertible {
    func js(indent: Int) -> String {
        return indentingLines(by: indent)
    }
    func swiftProtocols(indent: Int) -> String {
        String(repeating: " ", count: indent) + self
    }
    func swiftDispatch(indent: Int) -> String? {
        String(repeating: " ", count: indent) + self
    }
}

// MARK: – The result builder

@resultBuilder
internal struct APIBuilder {
    static func buildBlock(_ components: StringConvertible...) -> [StringConvertible] {
        return components
    }

    static func buildOptional(_ components: [StringConvertible]?) -> [StringConvertible] {
        return components ?? []
    }

    static func buildEither(first components: [StringConvertible]) -> [StringConvertible] {
        return components
    }

    static func buildEither(second components: [StringConvertible]) -> [StringConvertible] {
        return components
    }
}

// MARK: – The top-level program

// A string with extra indentation.
internal struct StringConvertibleIndented: StringConvertible {
    let content: StringConvertible
    let indent: Int
    
    func js(indent: Int) -> String {
        content.js(indent: self.indent + indent)
    }
    func swiftProtocols(indent: Int) -> String {
        content.swiftProtocols(indent: self.indent + indent)
    }
    func swiftDispatch(indent: Int) -> String? {
        content.swiftDispatch(indent: self.indent + indent)
    }
}

// A namespace in which other values may live.
internal struct Namespace: StringConvertible {
    let statements: [StringConvertibleIndented]
    let all: [StringConvertible]
    private let name: String
    private let isTopLevel: Bool

    init(_ name: String, freeze: Bool = true, preventExtensions: Bool = false, isTopLevel: Bool = true, @APIBuilder _ builder: () -> [StringConvertible]) {
        self.name = name
        self.isTopLevel = isTopLevel
        all = builder()

        // split out different types of items
        let constants = all.compactMap { $0 as? Constant }
        let configurableProperties = all.compactMap { $0 as? ConfigurableProperty }
        let others = all.filter { !($0 is Constant) && !($0 is ConfigurableProperty) }

        // normal members get 4-space indent with comma separation
        let inner = others.enumerated().map { (index, item) in
            let content = item.js(indent: 4)
            let needsComma = index < others.count - 1
            return StringConvertibleIndented(content: content + (needsComma ? "," : ""), indent: 0)
        }

        // wrap each constant in a new Constant with its namespace baked in
        let outerConstants = constants
            .map { $0.enclosed(in: name) }
            .map { StringConvertibleIndented(content: $0, indent: 0) }

        // wrap each configurable property with its namespace baked in (before freeze)
        let preFreeze = configurableProperties
            .map { $0.enclosed(in: name) }
            .map { StringConvertibleIndented(content: $0, indent: 0) }

        var allStatements: [StringConvertibleIndented] = []
        if isTopLevel {
            allStatements.append(.init(content: "const \(name) = {", indent: 0))
        } else {
            allStatements.append(.init(content: "\(name): {", indent: 0))
        }
        allStatements.append(.init(content: "// Normal members", indent: 0))
        allStatements.append(contentsOf: inner)
        allStatements.append(.init(content: "}", indent: 0))
        allStatements.append(.init(content: "// Constants", indent: 0))
        allStatements.append(contentsOf: outerConstants)
        allStatements.append(.init(content: "// Configurable properties", indent: 0))
        allStatements.append(contentsOf: preFreeze)
        
        if freeze {
            allStatements.append(.init(content: "Object.freeze(\(name));", indent: 0))
        } else if preventExtensions && isTopLevel {
            // Lock down immutable properties (only for top-level namespaces)
            for obj in all {
                let key: String
                if obj is ConfigurableProperty || obj is Constant || obj is Namespace {
                    continue
                } else if let value = obj as? VariableArgsFunction {
                    key = value.name
                } else if let value = obj as? AsyncFunction {
                    key = value.name
                } else if let value = obj as? PureJSFunction {
                    key = value.name
                } else {
                    fatalError("Unexpected type for child: \(type(of: obj))")
                }

                let desc = "desc_\(key)"
                let lockdown = """
                const \(desc) = Object.getOwnPropertyDescriptor(\(name), "\(key)")
                Object.defineProperty(\(name), "\(key)", {
                  value: \(desc).value,
                  writable: false,
                  configurable: false,
                  enumerable: \(desc).enumerable
                })
                """.components(separatedBy: "\n").map {
                    StringConvertibleIndented(content: $0, indent: 0)
                }
                allStatements.append(contentsOf: lockdown)
            }
            allStatements.append(.init(content: "Object.preventExtensions(\(name));", indent: 0))
        } else if preventExtensions && !isTopLevel {
            // For nested namespaces, don't generate external calls since we don't have the qualified path
            // The parent namespace should handle this
        }
        
        statements = allStatements
    }

    func js(indent: Int) -> String {
        return statements
            .map { $0.js(indent: indent) }
            .joined(separator: "\n")
    }
    func swiftProtocols(indent: Int) -> String {
        return all
            .map { $0.swiftProtocols(indent: indent) }
            .joined(separator: "\n")
    }
    func swiftDispatch(indent: Int) -> String? {
        let cases = all.compactMap { $0.swiftDispatch(indent: indent + 4) }
        if cases.isEmpty {
            return nil
        }
        let s = String(repeating: " ", count: indent)
        return ([
            s + "func dispatch(api: String, requestId: String, body: [String: Any], context: BrowserExtensionContext) async throws -> [String: Any] {",
            s + "    let jsonData = try JSONSerialization.data(withJSONObject: body)",
            s + "    switch api {"] +
           cases +
           [s + "    default:",
            s + "        throw NSError(domain: \"BrowserExtension\", code: 1, userInfo: [NSLocalizedDescriptionKey: \"Unknown API: \\(api)\"])",
            s + "    }",
            s + "}"
           ]).joined(separator: "\n")
    }
}

internal extension String {
    var jsonEncoded: String {
        String(data: try! JSONEncoder().encode(self), encoding: .utf8)!
    }
}

// An asynchronous API function taking a completion callback as its last argument.
internal struct AsyncFunction: StringConvertible {
    let name: String
    let args: [StringConvertible]
    let returnType: String
    private var capitalizedName: String {
        name.first!.uppercased() + String(name.dropFirst())
    }

    func js(indent: Int) -> String {
        let commaDelimitedArgs = (args.map { $0.js(indent: 0) } + ["callback"]).joined(separator: ", ")
        var params: [(String, String)] = [("requestId", "id"), ("api", name.jsonEncoded)]
        for arg in args {
            let tuple = (arg.js(indent: 0), arg.js(indent: 0))
            params.append(tuple)
        }
        let s8 = String(repeating: " ", count: 8)
        let s14 = String(repeating: " ", count: 14)
        let obj = s8 + "{" + params.enumerated().map { i, tuple in
            (i == 0 ? " " : s14) + "\(tuple.0): \(tuple.1)"
        }.joined(separator: ",\n") + " }"
        let lines = [
            "\(name)(\(commaDelimitedArgs)) {",
            "    const id = __ext_randomString();",
            "    __ext_callbackMap.set(id, callback);",
            "    __ext_post.requestBrowserExtension.postMessage(",
            obj,
            "    )",
            "}"
        ]
        return lines.map { String(repeating: " ", count: indent) + $0 }.joined(separator: "\n")
    }
    func swiftProtocols(indent: Int) -> String {
        let s = String(repeating: " ", count: indent)
        let s2 = String(repeating: " ", count: indent + 4)
        return ([s + "struct \(capitalizedName)RequestImpl: Codable {",
                 s + "    let requestId: String"] +
                args.map { $0.swiftProtocols(indent: indent + 4).replacingOccurrences(of: "var ", with: "let ").replacingOccurrences(of: " { get }", with: "") } +
                [s + "}",
                s + "protocol \(capitalizedName)Request {",
                 s + "    var requestId: String { get }"] +
                args.map { $0.swiftProtocols(indent: indent + 4) } +
                [s + "}",
                s + "extension \(capitalizedName)RequestImpl: \(capitalizedName)Request {}",
                s + "protocol \(capitalizedName)HandlerProtocol {",
                 s2 + "var requiredPermissions: [BrowserExtensionAPIPermission] { get }",
                 s2 + "@MainActor func handle(request: \(capitalizedName)Request, context: BrowserExtensionContext) async throws -> \(returnType)",
                 s + "}"
                ]).joined(separator: "\n")
    }
    func swiftDispatch(indent: Int) -> String? {
        let s = String(repeating: " ", count: indent)
        return [s + "case \"\(name)\":",
                s + "    let handler = \(capitalizedName)Handler()",
                s + "    try context.requirePermissions(handler.requiredPermissions)",
                s + "    let decoder = JSONDecoder()",
                s + "    let request = try decoder.decode(\(capitalizedName)RequestImpl.self, from: jsonData)",
                s + "    let response = try await handler.handle(request: request, context: context)",
                s + "    context.logger.debug(\"Dispatcher got response: \\(response) type: \\(type(of: response))\")",
                s + "    let encodedValue = response.browserExtensionEncodedValue",
                s + "    context.logger.debug(\"Dispatcher encoded value: \\(encodedValue)\")",
                s + "    let encoder = JSONEncoder()",
                s + "    let data = try encoder.encode(encodedValue)",
                s + "    let jsonObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]",
                s + "    context.logger.debug(\"Dispatcher returning: \\(jsonObject)\")",
                s + "    return jsonObject"].joined(separator: "\n")
    }
    init<T: Codable>(_ name: String, returns: T.Type, @APIBuilder _ builder: () -> [StringConvertible]) {
        self.name = name
        returnType = "\(returns)"
        args = builder()
    }
}

// An synchronous API function implemented entirely in javascript.
internal struct PureJSFunction: StringConvertible {
    let name: String
    private let body: String
    init(_ name: String, _ body: String) {
        self.name = name
        self.body = body
    }
    func js(indent: Int) -> String {
        return body.indentingLines(by: indent)
    }
    func swiftProtocols(indent: Int) -> String {
        ""
    }
    func swiftDispatch(indent: Int) -> String? {
        nil
    }
}

// The argument to an AsyncFunction
internal struct Argument: StringConvertible {
    let name: String
    let type: String
    func js(indent: Int) -> String {
        return String(repeating: " ", count: indent) + name
    }
    func swiftProtocols(indent: Int) -> String {
        String(repeating: " ", count: indent) + "var \(name): \(type) { get }"
    }
    func swiftDispatch(indent: Int) -> String? {
        ""
    }
    init<T>(_ name: String, type: T.Type) {
        self.name = name
        self.type = "\(type)"
    }
}

// A constant value.
internal struct Constant: StringConvertible {
    let name: String
    let value: String
    private let enclosure: String?

    init(_ name: String, _ value: String, enclosure: String? = nil) {
        self.name = name
        self.value = value
        self.enclosure = enclosure
    }

    func enclosed(in namespace: String) -> Constant {
        Constant(name, value, enclosure: namespace)
    }

    func js(indent: Int) -> String {
        let pad = String(repeating: " ", count: indent)
        guard let e = enclosure else {
            return pad + "const \(name) = \(value.jsonEncoded);"
        }
        return """
        Object.defineProperty(\(e), \(name.jsonEncoded), {
           value: \(value.jsonEncoded),
           writable: false,
           configurable: false,
           enumerable: true
        });
        """.components(separatedBy: "\n")
            .map { pad + $0 }
            .joined(separator: "\n")
    }

    func swiftProtocols(indent: Int) -> String {
        ""
    }
    func swiftDispatch(indent: Int) -> String? {
        ""
    }
}

// A function with variable arguments and optional callback support
internal struct VariableArgsFunction: StringConvertible {
    let name: String
    let returnType: String
    private var capitalizedName: String {
        name.first!.uppercased() + String(name.dropFirst())
    }

    init<T: Codable>(_ name: String, returns: T.Type) {
        self.name = name
        self.returnType = "\(returns)"
    }

    func js(indent: Int) -> String {
        return """
        \(name)(...args) {
            const hasCallback = args.length > 0 && typeof args[args.length - 1] === 'function';
            const callback = hasCallback ? args.pop() : null;
            
            const id = __ext_randomString();
            
            // Always set up a callback to handle responses
            // If no callback was provided, we create a no-op to consume the response
            // This prepares for Promise support via webextension-polyfill
            const effectiveCallback = callback || (() => {
                // No-op callback for fire-and-forget calls
                // In the future, this will be replaced by Promise resolution
            });
            
            __ext_callbackMap.set(id, effectiveCallback);
            
            __ext_post.requestBrowserExtension.postMessage({
                requestId: id,
                api: \(name.jsonEncoded),
                args: args
            });
        }
        """.indentingLines(by: indent)
    }

    func swiftProtocols(indent: Int) -> String {
        return """
        struct \(capitalizedName)RequestImpl: Codable {
            let requestId: String
            let args: [AnyJSONCodable]
        }
        protocol \(capitalizedName)Request {
            var requestId: String { get }
            var args: [AnyJSONCodable] { get }
        }
        extension \(capitalizedName)RequestImpl: \(capitalizedName)Request {}
        protocol \(capitalizedName)HandlerProtocol {
            var requiredPermissions: [BrowserExtensionAPIPermission] { get }
            func handle(request: \(capitalizedName)Request, context: BrowserExtensionContext) async throws -> \(returnType)
        }
        """.indentingLines(by: indent)
    }

    func swiftDispatch(indent: Int) -> String? {
        return """
        case "\(name)":
            let handler = \(capitalizedName)Handler()
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(\(capitalizedName)RequestImpl.self, from: jsonData)
            let response = try await handler.handle(request: request, context: context)
            context.logger.debug("Dispatcher got response: \\(response) type: \\(type(of: response))")
            let encodedValue = response.browserExtensionEncodedValue
            context.logger.debug("Dispatcher encoded value: \\(encodedValue)")
            let encoder = JSONEncoder()
            let data = try encoder.encode(encodedValue)
            let jsonObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            context.logger.debug("Dispatcher returning: \\(jsonObject)")
            return jsonObject
        """.indentingLines(by: indent)
    }
}

// A configurable property that needs to be added before freeze.
internal struct ConfigurableProperty: StringConvertible, Equatable {
    let name: String
    let getter: String
    private let enclosure: String?

    init(_ name: String, getter: String, enclosure: String? = nil) {
        self.name = name
        self.getter = getter
        self.enclosure = enclosure
    }

    func enclosed(in namespace: String) -> ConfigurableProperty {
        ConfigurableProperty(name, getter: getter, enclosure: namespace)
    }

    func js(indent: Int) -> String {
        let pad = String(repeating: " ", count: indent)
        guard let e = enclosure else {
            return ""  // Only works when enclosed in a namespace
        }
        return """
        Object.defineProperty(\(e), \(name.jsonEncoded), {
            get() { \(getter) },
            configurable: true,
            enumerable: true
        });
        """.components(separatedBy: "\n")
            .map { pad + $0 }
            .joined(separator: "\n")
    }

    func swiftProtocols(indent: Int) -> String {
        ""
    }
    func swiftDispatch(indent: Int) -> String? {
        ""
    }
}

extension String {
    func indentingLines(by indent: Int) -> String {
        return self
            .components(separatedBy: "\n")
            .map {
                String(repeating: " ", count: indent) + $0
            }
            .joined(separator: "\n")
    }
}

// MARK: - Public interface

public struct APIInputs {
    public var extensionId: String
    
    public init(extensionId: String) {
        self.extensionId = extensionId
    }
}

public func generatedAPIJavascript(_ inputs: APIInputs) -> String {
    let body = makeChromeRuntime(inputs: inputs).js(indent: 0)
    
    // Load the template and inject the runtime body
    return BrowserExtensionTemplateLoader.loadTemplate(
        named: "chrome-runtime-api",
        type: "js",
        substitutions: [
            "RUNTIME_BODY": body
        ]
    )
}

public func generatedAPISwift() -> String {
    let swiftCode = makeChromeRuntime(inputs: .init(extensionId: "")).swiftProtocols(indent: 0)
    return """
    // Generated file - do not edit
    import Foundation
    import BrowserExtensionShared
    
    \(swiftCode)
    """
}
public func generatedDispatchSwift() -> String {
    let swiftCode = makeChromeRuntime(inputs: .init(extensionId: "")).swiftDispatch(indent: 4) ?? ""
    return """
    // Generated file - do not edit
    import Foundation
    import BrowserExtensionShared

    @MainActor
    class BrowserExtensionDispatcher {
    \(swiftCode)
    }
    """
}
