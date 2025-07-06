import Foundation

internal protocol StringConvertible {
    func js(indent: Int) -> String
    func swiftProtocols(indent: Int) -> String
    func swiftDispatch(indent: Int) -> String
}

extension String: StringConvertible {
    func js(indent: Int) -> String {
        String(repeating: " ", count: indent) + self
    }
    func swiftProtocols(indent: Int) -> String {
        String(repeating: " ", count: indent) + self
    }
    func swiftDispatch(indent: Int) -> String {
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
    func swiftDispatch(indent: Int) -> String {
        content.swiftDispatch(indent: self.indent + indent)
    }
}

// A namespace in which other values may live.
internal struct Namespace: StringConvertible {
    let statements: [StringConvertibleIndented]
    let all: [StringConvertible]

    init(_ name: String, freeze: Bool = true, preventExtensions: Bool = false, @APIBuilder _ builder: () -> [StringConvertible]) {
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
        allStatements.append(.init(content: "const \(name) = {", indent: 0))
        allStatements.append(contentsOf: inner)
        allStatements.append(.init(content: "}", indent: 0))
        allStatements.append(contentsOf: outerConstants)
        allStatements.append(contentsOf: preFreeze)
        
        if freeze {
            allStatements.append(.init(content: "Object.freeze(\(name));", indent: 0))
        } else if preventExtensions {
            // Lock down immutable properties
            for obj in all {
                let key: String
                if obj is ConfigurableProperty || obj is Constant {
                    continue
                } else if let value = obj as? VariableArgsFunction {
                    key = value.name
                } else if let value = obj as? AsyncFunction {
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
    func swiftDispatch(indent: Int) -> String {
        let s = String(repeating: " ", count: indent)
        return ([s + "func dispatch(api: String, requestId: String, body: [String: Any]) async throws -> [String: Any] {",
                 s + "    let jsonData = try JSONSerialization.data(withJSONObject: body)",
                 s + "    switch api {"] +
                all.map { $0.swiftDispatch(indent: indent + 4) } +
                [s + "    default:",
                 s + "        throw NSError(domain: \"BrowserExtension\", code: 1, userInfo: [NSLocalizedDescriptionKey: \"Unknown API: \\(api)\"])",
                 s + "    }",
                 s + "}"]).joined(separator: "\n")
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
                 s2 + "func handle(request: \(capitalizedName)Request) async throws -> \(returnType)",
                 s + "}"
                ]).joined(separator: "\n")
    }
    func swiftDispatch(indent: Int) -> String {
        let s = String(repeating: " ", count: indent)
        return [s + "case \"\(name)\":",
                s + "    let decoder = JSONDecoder()",
                s + "    let request = try decoder.decode(\(capitalizedName)RequestImpl.self, from: jsonData)",
                s + "    let handler = \(capitalizedName)Handler()",
                s + "    let response = try await handler.handle(request: request)",
                s + "    let encodedResponse = try JSONEncoder().encode(response)",
                s + "    return try JSONSerialization.jsonObject(with: encodedResponse) as! [String: Any]"].joined(separator: "\n")
    }
    init<T: Codable>(_ name: String, returns: T.Type, @APIBuilder _ builder: () -> [StringConvertible]) {
        self.name = name
        returnType = "\(returns)"
        args = builder()
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
    func swiftDispatch(indent: Int) -> String {
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
    func swiftDispatch(indent: Int) -> String {
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
            func handle(request: \(capitalizedName)Request) async throws -> \(returnType)
        }
        """.indentingLines(by: indent)
    }

    func swiftDispatch(indent: Int) -> String {
        return """
        case "\(name)":
            let decoder = JSONDecoder()
            let request = try decoder.decode(\(capitalizedName)RequestImpl.self, from: jsonData)
            let handler = \(capitalizedName)Handler()
            let response = try await handler.handle(request: request)
            let encodedResponse = try JSONEncoder().encode(response)
            return try JSONSerialization.jsonObject(with: encodedResponse) as! [String: Any]
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
    func swiftDispatch(indent: Int) -> String {
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
    return makeChromeRuntime(inputs: inputs).js(indent: 0)
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
    let swiftCode = makeChromeRuntime(inputs: .init(extensionId: "")).swiftDispatch(indent: 0)
    return """
    // Generated file - do not edit
    import Foundation
    import BrowserExtensionShared
    
    \(swiftCode)
    """
}
