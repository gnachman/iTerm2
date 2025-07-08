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
                 s2 + "@MainActor func handle(request: \(capitalizedName)Request, context: BrowserExtensionContext) async throws -> \(returnType)",
                 s + "}"
                ]).joined(separator: "\n")
    }
    func swiftDispatch(indent: Int) -> String? {
        let s = String(repeating: " ", count: indent)
        return [s + "case \"\(name)\":",
                s + "    let decoder = JSONDecoder()",
                s + "    let request = try decoder.decode(\(capitalizedName)RequestImpl.self, from: jsonData)",
                s + "    let handler = \(capitalizedName)Handler()",
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
            func handle(request: \(capitalizedName)Request, context: BrowserExtensionContext) async throws -> \(returnType)
        }
        """.indentingLines(by: indent)
    }

    func swiftDispatch(indent: Int) -> String? {
        return """
        case "\(name)":
            let decoder = JSONDecoder()
            let request = try decoder.decode(\(capitalizedName)RequestImpl.self, from: jsonData)
            let handler = \(capitalizedName)Handler()
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
    let preamble = """
    ;(function() {
      'use strict';
      const __ext_callbackMap = new Map();
      const __ext_listeners = [];
    
      function __ext_randomString(len = 16) {
        const bytes = crypto.getRandomValues(new Uint8Array(len));
        return Array.from(bytes)
          .map(b => b.toString(36).padStart(2, '0'))
          .join('')
          .substring(0, len);
      }

      // Encode values for messaging (handles null, undefined, and everything else)
      function __ext_encodeForMessaging(value) {
        if (value === null) {
          return { value: "null" };
        }
        if (value === undefined) {
          return { value: "undefined" };
        }
        // Everything else gets JSON stringified
        // This handles Date, RegExp, objects, arrays, primitives, etc.
        return { json: JSON.stringify(value) };
      }

      // Decode values from messaging
      function __ext_decodeFromMessaging(encoded) {
        if (!encoded || typeof encoded !== 'object') {
          console.error('Invalid message encoding: expected object, got', typeof encoded, encoded);
          throw new Error('Invalid message encoding: expected object');
        }
        
        if ('value' in encoded) {
          if (encoded.value === "null") return null;
          if (encoded.value === "undefined") return undefined;
          
          console.error('Invalid message encoding: unknown value type', encoded.value);
          throw new Error(`Invalid message encoding: unknown value type "${encoded.value}"`);
        }
        
        if ('json' in encoded) {
          try {
            return JSON.parse(encoded.json);
          } catch (e) {
            console.error('Invalid message encoding: JSON parse error', e, encoded.json);
            throw new Error(`Invalid message encoding: JSON parse error - ${e.message}`);
          }
        }
        
        console.error('Invalid message encoding: missing required field (value or json)', encoded);
        throw new Error('Invalid message encoding: missing required field (value or json)');
      }

      const __ext_post = window.webkit.messageHandlers;

    """
    let body = makeChromeRuntime(inputs: inputs).js(indent: 0)
    let postamble = """
      // Function for injecting lastError in callbacks
      window.__ext_injectLastError = function(error, callback, response) {
        const injectedError = { message: error.message || error }
        let seen = false
        const originalDesc =
          Object.getOwnPropertyDescriptor(chrome.runtime, "lastError")

        // override getter in-place
        Object.defineProperty(chrome.runtime, "lastError", {
          get() {
            seen = true;
            return injectedError;
          },
          configurable: true,
          enumerable: originalDesc.enumerable
        });

        try {
          // Handle both encoded responses (from real API calls) and raw values (from direct test calls)
          let decodedResponse;
          if (typeof response === 'string') {
            // This is a JSON-encoded response from the real API system
            const parsedResponse = JSON.parse(response);
            decodedResponse = __ext_decodeFromMessaging(parsedResponse);
          } else {
            // This is a raw value (e.g., from direct test calls)
            decodedResponse = response;
          }
          callback(decodedResponse);
        } finally {
          Object.defineProperty(chrome.runtime, "lastError", originalDesc);

          // warn if nobody read it
          if (!seen) {
            console.warn('Unchecked runtime.lastError:', injectedError.message);
          }
        }
      }

      Object.defineProperty(window, '__EXT_invokeCallback__', {
        value(requestId, result, error) {
          const cb = __ext_callbackMap.get(requestId);
          if (cb) {
            try { 
              if (error) {
                window.__ext_injectLastError(error, cb, result);
              } else {
                // Result comes as a JSON string from Swift, parse it first
                const parsedResult = JSON.parse(result);
                const decoded = __ext_decodeFromMessaging(parsedResult);
                cb(decoded);
              }
            }
            finally { __ext_callbackMap.delete(requestId) }
          }
        },
        writable: false,
        configurable: false,
        enumerable: false
      });
      // Inject into *both* background & content contexts
      Object.defineProperty(window, '__EXT_invokeListener__', {
        value(requestId, message, sender, isExternal, alreadyResponded) {
          let keepAlive = false;
          let responded = alreadyResponded;
          let listenersInvoked = 0;

          function sendResponse(response) {
            if (responded) return;
            responded = true;
            const encoded = __ext_encodeForMessaging(response);
            __ext_post.listenerResponseBrowserExtension.postMessage({ requestId, response: encoded });
          }

          for (const entry of __ext_listeners) {
            if (entry.external !== isExternal) continue;
            listenersInvoked++;
      
            try {
              const result = entry.callback(message, sender, sendResponse);
              if (result === true) {
                // listener wants to respond asynchronously
                keepAlive = true;
              }
            }
            catch (err) {
              console.error('onMessage listener threw:', err);
            }
          }
          return {"keepAlive": keepAlive, "responded": responded, "listenersInvoked": listenersInvoked};
        },
        writable: false,
        configurable: false,
        enumerable: false
      });
      Object.defineProperty(window, 'chrome', {
        value: { runtime },
        writable: false,
        configurable: false,
        enumerable: false
      });

      Object.freeze(window.chrome);
      true;
    })();
    """
    return [preamble, body, postamble].joined(separator: "\n")
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
        private let context: BrowserExtensionContext

        init(context: BrowserExtensionContext) {
            self.context = context
        }
    
    \(swiftCode)
    }
    """
}
