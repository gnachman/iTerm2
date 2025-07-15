import Foundation

internal protocol StringConvertible {
    func js(indent: Int) -> String
    func swiftProtocols(indent: Int) -> String
    func swiftDispatch(indent: Int) -> String?
    func js(indent: Int, context: String?) -> String
    func swiftProtocols(indent: Int, context: String?) -> String
    func swiftDispatch(indent: Int, context: String?) -> String?
}

extension StringConvertible {
    // Default implementations that delegate to the non-context versions
    func js(indent: Int, context: String?) -> String {
        return js(indent: indent)
    }
    
    func swiftProtocols(indent: Int, context: String?) -> String {
        return swiftProtocols(indent: indent)
    }
    
    func swiftDispatch(indent: Int, context: String?) -> String? {
        return swiftDispatch(indent: indent)
    }
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
    // 1) Wrap a single StringConvertible into an array
    static func buildExpression(_ expr: StringConvertible) -> [StringConvertible] {
        [expr]
    }

    // 2) (Optional) Accept an array of components directly
    static func buildExpression(_ expr: [StringConvertible]) -> [StringConvertible] {
        expr
    }

    // flatten variadic arrays into one array
    static func buildBlock(_ components: [StringConvertible]...) -> [StringConvertible] {
        components.flatMap { $0 }
    }

    static func buildOptional(_ components: [StringConvertible]?) -> [StringConvertible] {
        components ?? []
    }

    static func buildEither(first components: [StringConvertible]) -> [StringConvertible] {
        components
    }

    static func buildEither(second components: [StringConvertible]) -> [StringConvertible] {
        components
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
    
    func js(indent: Int, context: String?) -> String {
        content.js(indent: self.indent + indent, context: context)
    }
    func swiftProtocols(indent: Int, context: String?) -> String {
        content.swiftProtocols(indent: self.indent + indent, context: context)
    }
    func swiftDispatch(indent: Int, context: String?) -> String? {
        content.swiftDispatch(indent: self.indent + indent, context: context)
    }
}

internal struct APISequence: StringConvertible {
    let all: [StringConvertible]
    init(@APIBuilder _ builder: () -> [StringConvertible]) {
        all = builder()
    }
    func js(indent: Int) -> String {
        return all.map { $0.js(indent: indent) }.joined(separator: "\n")
    }
    func swiftProtocols(indent: Int) -> String {
        return all.map { $0.swiftProtocols(indent: indent) }.joined(separator: "\n")
    }
    func swiftDispatch(indent: Int) -> String? {
        return all.compactMap { $0.swiftDispatch(indent: indent) }.joined(separator: "\n")
    }
    func js(indent: Int, context: String?) -> String {
        return all.map { $0.js(indent: indent, context: context) }.joined(separator: "\n")
    }
    func swiftProtocols(indent: Int, context: String?) -> String {
        return all.map { $0.swiftProtocols(indent: indent, context: context) }.joined(separator: "\n")
    }
    func swiftDispatch(indent: Int, context: String?) -> String? {
        return all.compactMap { $0.swiftDispatch(indent: indent, context: context) }.joined(separator: "\n")
    }
}

// A namespace in which other values may live.
internal struct Namespace: StringConvertible {
    let statements: [StringConvertibleIndented]
    let all: [StringConvertible]
    let name: String
    private let isTopLevel: Bool
    private let jsname: String?

    init(_ name: String,
         freeze: Bool = true,
         preventExtensions: Bool = false,
         isTopLevel: Bool = true,
         jsname: String? = nil,
         @APIBuilder _ builder: () -> [StringConvertible]) {
        self.name = name
        self.isTopLevel = isTopLevel
        self.jsname = jsname
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
            allStatements.append(.init(content: "const \(jsname ?? name) = {", indent: 0))
        } else {
            allStatements.append(.init(content: "\(jsname ?? name): {", indent: 0))
        }
        allStatements.append(.init(content: "// Normal members", indent: 0))
        allStatements.append(contentsOf: inner)
        allStatements.append(.init(content: "}", indent: 0))
        
        if !outerConstants.isEmpty {
            allStatements.append(.init(content: "// Constants", indent: 0))
            allStatements.append(contentsOf: outerConstants)
        }
        
        if !preFreeze.isEmpty {
            allStatements.append(.init(content: "// Configurable properties", indent: 0))
            allStatements.append(contentsOf: preFreeze)
        }
        
        if freeze {
            allStatements.append(.init(content: "Object.freeze(\(name));", indent: 0))
        } else if preventExtensions && isTopLevel {
            // Lock down immutable properties (only for top-level namespaces)
            for obj in all {
                let key: String
                if obj is ConfigurableProperty || obj is Constant || obj is Namespace || obj is JSProxy || obj is InlineJavascript {
                    continue
                } else if let namedFunction = obj as? JavascriptNamedFunction {
                    key = namedFunction.name
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
        let cases = all.compactMap { $0.swiftDispatch(indent: indent) }
        if cases.isEmpty {
            return nil
        }
        return cases.joined(separator: "\n")
    }
    
    func js(indent: Int, context: String?) -> String {
        let newContext = context.map { "\($0).\(name)" } ?? name
        
        // Rebuild the statements with the correct context
        let constants = all.compactMap { $0 as? Constant }
        let configurableProperties = all.compactMap { $0 as? ConfigurableProperty }
        let others = all.filter { !($0 is Constant) && !($0 is ConfigurableProperty) && !($0 is JSProxy) }

        // normal members get 4-space indent with comma separation
        let inner = others.enumerated().map { (index, item) in
            let content = item.js(indent: 4, context: newContext)
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
            allStatements.append(.init(content: "const \(jsname ?? name) = {", indent: 0))
        } else {
            allStatements.append(.init(content: "\(jsname ?? name): {", indent: 0))
        }
        allStatements.append(.init(content: "// Normal members", indent: 0))
        allStatements.append(contentsOf: inner)
        allStatements.append(.init(content: "}", indent: 0))
        
        // Only add constants section if there are constants
        if !outerConstants.isEmpty {
            allStatements.append(.init(content: "// Constants", indent: 0))
            allStatements.append(contentsOf: outerConstants)
        }
        
        // Only add configurable properties section if there are configurable properties
        if !preFreeze.isEmpty {
            allStatements.append(.init(content: "// Configurable properties", indent: 0))
            allStatements.append(contentsOf: preFreeze)
        }
        
        // Rebuild freeze/preventExtensions logic
        // We need to look up the original constructor parameters to get freeze and preventExtensions
        // For now, let's check if any original statements had freeze/preventExtensions
        let hasFreeze = statements.contains { statement in
            statement.js(indent: 0).contains("Object.freeze(\(name))")
        }
        let hasPreventExtensions = statements.contains { statement in
            statement.js(indent: 0).contains("Object.preventExtensions(\(name))")
        }
        
        if hasFreeze {
            allStatements.append(.init(content: "Object.freeze(\(name));", indent: 0))
        } else if hasPreventExtensions && isTopLevel {
            // Lock down immutable properties (only for top-level namespaces)
            for obj in all {
                let key: String
                if obj is ConfigurableProperty || obj is Constant || obj is Namespace || obj is InlineJavascript {
                    continue
                } else if let value = obj as? JavascriptNamedFunction {
                    key = value.name
                } else if let proxy = obj as? JSProxy {
                    allStatements.append(.init(content: proxy.js(indent: 0), indent: 0))
                    continue
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
        
        return allStatements
            .map { $0.js(indent: indent, context: newContext) }
            .joined(separator: "\n")
    }
    func swiftProtocols(indent: Int, context: String?) -> String {
        let newContext = context.map { "\($0).\(name)" } ?? name
        return all
            .map { $0.swiftProtocols(indent: indent, context: newContext) }
            .joined(separator: "\n")
    }
    func swiftDispatch(indent: Int, context: String?) -> String? {
        let newContext = context.map { "\($0).\(name)" } ?? name
        let cases = all.compactMap { $0.swiftDispatch(indent: indent, context: newContext) }
        if cases.isEmpty {
            return nil
        }
        return cases.joined(separator: "\n")
    }
}

internal extension String {
    var jsonEncoded: String {
        String(data: try! JSONEncoder().encode(self), encoding: .utf8)!
    }
}

// Dependency specification for dependency injection
internal struct DependencySpec {
    let name: String
    let type: String
    
    init(_ name: String, _ type: String) {
        self.name = name
        self.type = type
    }
}

// Use a type conforming to this protocol as the return type of an AsyncFunction if you need to
// modify the value passed to its completion callback. This should return JS of a function expression
// taking a single argument which is the callback to run with a transformed value.
protocol JavascriptTransformableType {
    static func transform(_ varName: String) -> String
}

protocol JavascriptNamedFunction {
    var name: String { get }
}

protocol JavascriptDependentFunction {
    var dependencies: [DependencySpec] { get }
}

// Expects a String->String as input and invokes the callback after JSON decoding with a String->Object map.
public struct StringToJSONObject: Codable, JavascriptTransformableType, BrowserExtensionJSONRepresentable {
    static func transform(_ varName: String) -> String {
        """
        (arg) => {
            if (arg === undefined) {
                \(varName)(arg);
                return;
            }
            const decodedArg = Object.fromEntries(
                Object.entries(arg).map(([key, value]) => [key, JSON.parse(value)])
            );
            \(varName)(decodedArg);
        }
        """
    }

    let value: [String: String]
    public init(_ value: [String: String]) {
        self.value = value
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode([String: String].self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
    public var browserExtensionEncodedValue: BrowserExtensionEncodedValue {
        do {
            return try .json(value)
        } catch {
            return .undefined
        }
    }
}

// An asynchronous API function taking a completion callback as its last argument.
internal struct AsyncFunction<T>: StringConvertible, JavascriptNamedFunction, JavascriptDependentFunction {
    let name: String
    let args: [APIArgument]
    let returnType: String
    let dependencies: [DependencySpec]

    init(_ name: String, returns: T.Type, init: [(String, String)] = [], @APIBuilder _ builder: () -> [StringConvertible]) {
        self.name = name
        returnType = "\(returns)"
        self.dependencies = `init`.map { DependencySpec($0.0, $0.1) }
        args = builder().compactMap { $0 as? APIArgument }
    }

    private func capitalizedName(context: String?) -> String {
        let baseName = name.first!.uppercased() + String(name.dropFirst())
        if let context = context {
            // Convert "storage.local" to "StorageLocal"
            let contextParts = context.split(separator: ".").map { $0.capitalized }
            return contextParts.joined() + baseName
        }
        return baseName
    }
    
    private func apiName(context: String?) -> String {
        if let context = context {
            return "\(context).\(name)"
        }
        return name
    }

    func js(indent: Int) -> String {
        return js(indent: indent, context: nil)
    }
    
    func js(indent: Int, context: String?) -> String {
        let commaDelimitedArgs = (args.map { $0.jsParameterName() } + ["callback"]).joined(separator: ", ")
        var params: [(String, String)] = [("requestId", "id"), ("api", apiName(context: context).jsonEncoded)]
        for arg in args {
            let tuple = (arg.name, arg.jsMessageValue())
            params.append(tuple)
        }
        let s8 = String(repeating: " ", count: 8)
        let s14 = String(repeating: " ", count: 14)
        let obj = s8 + "{" + params.enumerated().map { i, tuple in
            let indentation = (i == 0 ? " " : s14)
            return indentation + "\(tuple.0): \(tuple.1)"
        }.joined(separator: ",\n") + " }"

        let callback: String
        if let transformableType = T.self as? JavascriptTransformableType.Type {
            callback = transformableType.transform("callback")
        } else {
            callback = "callback"
        }
        let lines = [
            "\(name)(\(commaDelimitedArgs)) {",
            "    const id = __ext_randomString();",
            "    __ext_checkCallback(callback);",
            "    __ext_callbackMap.set(id, \(callback));",
            "    __ext_post.requestBrowserExtension.postMessage(",
            obj,
            "    )",
            "}"
        ]
        return lines.map { String(repeating: " ", count: indent) + $0 }.joined(separator: "\n")
    }
    func swiftProtocols(indent: Int) -> String {
        return swiftProtocols(indent: indent, context: nil)
    }
    
    func swiftProtocols(indent: Int, context: String?) -> String {
        let s = String(repeating: " ", count: indent)
        let s2 = String(repeating: " ", count: indent + 4)
        
        // Generate init parameters for protocol
        let initParams = dependencies.map { "\($0.name): \($0.type)?" }.joined(separator: ", ")
        let initLine = dependencies.isEmpty ? "" : s2 + "init(\(initParams))"
        
        var protocolLines = [
            s + "struct \(capitalizedName(context: context))RequestImpl: Codable {",
            s + "    let requestId: String"
        ]
        
        protocolLines.append(contentsOf: args.map { 
            $0.swiftProtocols(indent: indent + 4).replacingOccurrences(of: "var ", with: "let ").replacingOccurrences(of: " { get }", with: "") 
        })
        
        protocolLines.append(contentsOf: [
            s + "}",
            s + "protocol \(capitalizedName(context: context))Request {",
            s + "    var requestId: String { get }"
        ])
        
        protocolLines.append(contentsOf: args.map { $0.swiftProtocols(indent: indent + 4) })
        
        protocolLines.append(contentsOf: [
            s + "}",
            s + "extension \(capitalizedName(context: context))RequestImpl: \(capitalizedName(context: context))Request {}",
            s + "protocol \(capitalizedName(context: context))HandlerProtocol {",
            s2 + "var requiredPermissions: [BrowserExtensionAPIPermission] { get }"
        ])
        
        if !dependencies.isEmpty {
            protocolLines.append(initLine)
        }
        
        protocolLines.append(contentsOf: [
            s2 + "@MainActor func handle(request: \(capitalizedName(context: context))Request, context: BrowserExtensionContext, namespace: String?) async throws -> \(returnType)",
            s + "}"
        ])
        
        return protocolLines.joined(separator: "\n")
    }
    func swiftDispatch(indent: Int) -> String? {
        return swiftDispatch(indent: indent, context: nil)
    }
    
    func swiftDispatch(indent: Int, context: String?) -> String? {
        let s = String(repeating: " ", count: indent)
        
        // Generate handler instantiation with dependencies
        let handlerInstantiation: String
        if dependencies.isEmpty {
            handlerInstantiation = s + "    let handler = \(capitalizedName(context: context))Handler()"
        } else {
            let depArgs = dependencies.map { $0.name }.joined(separator: ", ")
            handlerInstantiation = s + "    let handler = \(capitalizedName(context: context))Handler(\(depArgs): \(depArgs))"
        }
        
        var output: [String] = [
                s + "case \"\(apiName(context: context))\":",
                handlerInstantiation,
                s + "    try context.requirePermissions(handler.requiredPermissions)",
                s + "    let decoder = JSONDecoder()",
                s + "    let request = try decoder.decode(\(capitalizedName(context: context))RequestImpl.self, from: jsonData)"]

        if T.self is BrowserExtensionJSONRepresentable.Type {
            output += [
                s + "    let response = try await handler.handle(request: request, context: context, namespace: \(context?.jsonEncoded ?? "nil"))",
                s + "    context.logger.debug(\"Dispatcher got response: \\(response) type: \\(type(of: response))\")",
                s + "    let encodedValue = response.browserExtensionEncodedValue",
                s + "    context.logger.debug(\"Dispatcher encoded value: \\(encodedValue)\")",
                s + "    let encoder = JSONEncoder()",
                s + "    let data = try encoder.encode(encodedValue)",
                s + "    let jsonObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]",
                s + "    context.logger.debug(\"Dispatcher returning: \\(jsonObject)\")",
                s + "    return jsonObject"]
        } else {
            output += [
                s + "    try await handler.handle(request: request, context: context, namespace: \(context?.jsonEncoded ?? "nil"))",
                s + "    return [\"\": NoObjectPlaceholder.instance];"]
        }
        return output.joined(separator: "\n")
    }
}

// An synchronous API function implemented entirely in javascript.
internal struct PureJSFunction: StringConvertible, JavascriptNamedFunction {
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

internal struct JSProxy: StringConvertible {
    let code: String
    init(_ code: String) {
        self.code = code
    }
    func js(indent: Int) -> String {
        code.indentingLines(by: indent)
    }
    func swiftProtocols(indent: Int) -> String {
        ""
    }
    func swiftDispatch(indent: Int) -> String? {
        ""
    }
}

internal struct InlineJavascript: StringConvertible {
    let code: String
    init(_ code: String) {
        self.code = code
    }
    func js(indent: Int) -> String {
        code.indentingLines(by: indent)
    }
    func swiftProtocols(indent: Int) -> String {
        ""
    }
    func swiftDispatch(indent: Int) -> String? {
        ""
    }
}

// Protocol for function arguments
internal protocol APIArgument: StringConvertible {
    var name: String { get }
    var type: String { get }
    
    /// The parameter name in the JavaScript function signature
    func jsParameterName() -> String
    
    /// The value to send in the message (may be transformed)
    func jsMessageValue() -> String
}

let JSONEncodeDictionaryValuesTransform = { (obj: String) -> String in
    "window.__EXT_jsonEncodeValues(\(obj))"
}
let JSONNoTransform = { (obj: String) -> String in
    obj
}

protocol ArgumentTransforming {
    static var transform: (String) -> (String) { get }
}

extension Dictionary: ArgumentTransforming where Key == String, Value == String {
    static var transform: (String) -> (String) = { value in value }
}

// The argument to an AsyncFunction
internal struct Argument: APIArgument {
    let name: String
    let type: String
    let transform: ((String) -> (String))

    func jsParameterName() -> String {
        return name
    }
    
    func jsMessageValue() -> String {
        return transform(name)
    }
    
    func js(indent: Int) -> String {
        return String(repeating: " ", count: indent) + name
    }
    func swiftProtocols(indent: Int) -> String {
        String(repeating: " ", count: indent) + "var \(name): \(type) { get }"
    }
    func swiftDispatch(indent: Int) -> String? {
        ""
    }
    init<T>(_ name: String, type: T.Type, transform: ((String) -> (String))? = nil) {
        self.name = name
        self.type = "\(type)"
        self.transform = if let transform {
            transform
        } else if let transforming = type as? ArgumentTransforming.Type {
            transforming.transform
        } else {
            { "JSON.stringify(\($0))" }
        }
    }
}

// A dictionary argument where values are JSON that need to be stringified
internal struct JSONStringDictArgument: APIArgument {
    let name: String
    let type: String = "[String: String]"
    
    init(_ name: String) {
        self.name = name
    }
    
    func jsParameterName() -> String {
        return name
    }
    
    func jsMessageValue() -> String {
        return "window.__EXT_stringifyObjectValues(\(name))"
    }
    
    func js(indent: Int) -> String {
        return String(repeating: " ", count: indent) + jsMessageValue()
    }
    
    func swiftProtocols(indent: Int) -> String {
        String(repeating: " ", count: indent) + "var \(name): \(type) { get }"
    }
    
    func swiftDispatch(indent: Int) -> String? {
        ""
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
internal struct VariableArgsFunction: StringConvertible, JavascriptNamedFunction {
    let name: String
    let returnType: String
    
    private func capitalizedName(context: String?) -> String {
        let baseName = name.first!.uppercased() + String(name.dropFirst())
        if let context = context {
            // Convert "runtime" to "Runtime"
            let contextParts = context.split(separator: ".").map { $0.capitalized }
            return contextParts.joined() + baseName
        }
        return baseName
    }
    
    private func apiName(context: String?) -> String {
        if let context = context {
            return "\(context).\(name)"
        }
        return name
    }

    init<T: Codable>(_ name: String, returns: T.Type) {
        self.name = name
        self.returnType = "\(returns)"
    }

    func js(indent: Int) -> String {
        return js(indent: indent, context: nil)
    }
    
    func js(indent: Int, context: String?) -> String {
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
                api: \(apiName(context: context).jsonEncoded),
                args: args.map(arg => JSON.stringify(arg))
            });
        }
        """.indentingLines(by: indent)
    }

    func swiftProtocols(indent: Int) -> String {
        return swiftProtocols(indent: indent, context: nil)
    }
    
    func swiftProtocols(indent: Int, context: String?) -> String {
        return """
        struct \(capitalizedName(context: context))RequestImpl: Codable {
            let requestId: String
            let args: [AnyJSONCodable]
        }
        protocol \(capitalizedName(context: context))Request {
            var requestId: String { get }
            var args: [AnyJSONCodable] { get }
        }
        extension \(capitalizedName(context: context))RequestImpl: \(capitalizedName(context: context))Request {}
        protocol \(capitalizedName(context: context))HandlerProtocol {
            var requiredPermissions: [BrowserExtensionAPIPermission] { get }
            func handle(request: \(capitalizedName(context: context))Request, context: BrowserExtensionContext) async throws -> \(returnType)
        }
        """.indentingLines(by: indent)
    }

    func swiftDispatch(indent: Int) -> String? {
        return swiftDispatch(indent: indent, context: nil)
    }
    
    func swiftDispatch(indent: Int, context: String?) -> String? {
        return """
        case "\(apiName(context: context))":
            let handler = \(capitalizedName(context: context))Handler()
            try context.requirePermissions(handler.requiredPermissions)
            let decoder = JSONDecoder()
            let request = try decoder.decode(\(capitalizedName(context: context))RequestImpl.self, from: jsonData)
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
    public var trusted: Bool
    public var setAccessLevelToken: String

    public init(extensionId: String, trusted: Bool, setAccessLevelToken: String) {
        self.extensionId = extensionId
        self.trusted = trusted
        self.setAccessLevelToken = setAccessLevelToken
    }
}

// API Definition Structure
struct APIDefinition {
    let name: String
    let templateName: String
    let generator: (APIInputs) -> APISequence
}

public func generatedAPIJavascript(_ inputs: APIInputs) -> String {
    var allJavaScript = ""
    
    // First, add the chrome base script to create the chrome object
    allJavaScript += BrowserExtensionTemplateLoader.loadTemplate(named: "chrome-base", type: "js") + "\n"
    
    // Then add each API
    for apiDef in chromeAPIs {
        let body = apiDef.generator(inputs).js(indent: 0, context: nil)
        
        // Load the template and inject the body
        let apiJS = BrowserExtensionTemplateLoader.loadTemplate(
            named: apiDef.templateName,
            type: "js",
            substitutions: [
                "\(apiDef.name.uppercased())_BODY": body
            ]
        )
        
        allJavaScript += apiJS + "\n"
    }
    
    // Finally, add the chrome finalize script to freeze the chrome object
    allJavaScript += BrowserExtensionTemplateLoader.loadTemplate(named: "chrome-finalize", type: "js") + "\n"
    
    return allJavaScript
}

public func generatedAPISwift() -> String {
    var allSwiftCode = ""
    
    for apiDef in chromeAPIs {
        let swiftCode = apiDef.generator(.init(extensionId: "", trusted: true, setAccessLevelToken: "no token - this is generated Swift code")).swiftProtocols(indent: 0, context: nil)
        allSwiftCode += swiftCode + "\n"
    }
    
    return """
    // Generated file - do not edit
    import Foundation
    import BrowserExtensionShared
    
    \(allSwiftCode)
    """
}
public func generatedDispatchSwift() -> String {
    var allDispatchCode = ""
    var allDependencies: [String: String] = [:]
    
    for apiDef in chromeAPIs {
        let namespace = apiDef.generator(.init(extensionId: "", trusted: true, setAccessLevelToken: "no token - this is generated dispatch code"))

        // Collect dependencies from all AsyncFunctions
        collectDependencies(from: namespace, into: &allDependencies)

        if let swiftCode = namespace.swiftDispatch(indent: 8, context: nil) {
            allDispatchCode += swiftCode + "\n"
        }
    }
    
    // Generate weak property declarations for dependencies
    let dependencyProperties = allDependencies.map { (name, type) in
        "    weak var \(name): \(type)?"
    }.joined(separator: "\n")
    
    let dependencyPropertiesSection = allDependencies.isEmpty ? "" : dependencyProperties + "\n    \n"
    
    return """
    // Generated file - do not edit
    import Foundation
    import BrowserExtensionShared

    @MainActor
    class BrowserExtensionDispatcher {
    \(dependencyPropertiesSection)    func dispatch(api: String, requestId: String, body: [String: Any], context: BrowserExtensionContext) async throws -> [String: Any] {
            let jsonData = try JSONSerialization.data(withJSONObject: body)
            switch api {
    \(allDispatchCode)
            default:
                throw BrowserExtensionError.unknownAPI(api)
            }
        }
    }
    """
}

// Helper function to collect all dependencies from a namespace
private func collectDependencies(from obj: StringConvertible,
                                 into dependencies: inout [String: String]) {
    if let asyncFunc = obj as? JavascriptDependentFunction {
        for dep in asyncFunc.dependencies {
            dependencies[dep.name] = dep.type
        }
    } else if let ns = obj as? Namespace {
        for item in ns.all {
            collectDependencies(from: item, into: &dependencies)
        }
    } else if let seq = obj as? APISequence {
        for item in seq.all {
            collectDependencies(from: item, into: &dependencies)
        }
    }
}
