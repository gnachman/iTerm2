//
//  BindingCheckers.swift
//  ModernTests
//
//  The checkers of the binding tests (docs/swift-migration/phase0.md section
//  3). Each takes a parsed file and a BindingRuntime and returns the list of
//  names that do not resolve, as BindingProblems. They read nothing else, so
//  BindingCheckerFixtureTests can prove each one reports exactly the problem a
//  small fixture contains, and BindingTests runs them on the real files with
//  the real runtime.
//

import Foundation
import SQLite3

// MARK: - Xib and storyboard

// An object of a xib or storyboard: any element with an id that is not a
// connection.
struct BindingXibObject {
    enum Role {
        case regular
        // File's Owner: id -2 in a xib, placeholderIdentifier IBFilesOwner in
        // a storyboard. Not instantiated by the nib; whoever loads the nib
        // passes it. Its customClass is a hint that Interface Builder uses to
        // offer outlets and actions; the checks below hold the hint to them.
        case fileOwner
        // First Responder: id -1 in a xib, placeholderIdentifier
        // IBFirstResponder or sceneMemberID="firstResponder" in a storyboard.
        // A target of nil: AppKit sends the action up the responder chain.
        // Its customClass ("FirstResponder" or "NSResponder") names nothing.
        case firstResponder
        // Application: id -3 in a xib, an `application` element in a
        // storyboard. Always NSApp, whose class is the app's NSPrincipalClass,
        // whatever customClass says (Interface Builder writes NSObject).
        case application
    }

    let id: String
    let tag: String
    let customClass: String?
    let customModule: String?
    let label: String?
    let role: Role
}

struct BindingXibConnection {
    enum Kind: String {
        case outlet
        case outletCollection
        case action
        case binding
    }

    let kind: Kind
    let id: String
    // The object whose `connections` element holds this connection.
    let sourceID: String
    // Outlet property, action selector, or binding name.
    let name: String
    // Outlet or binding destination, or action target.
    let destinationID: String
    let keyPath: String?
}

struct BindingXibRuntimeAttribute {
    let ownerID: String
    let keyPath: String
}

struct BindingXibDocument {
    let path: String
    var objects: [String: BindingXibObject] = [:]
    var objectOrder: [String] = []
    var connections: [BindingXibConnection] = []
    var runtimeAttributes: [BindingXibRuntimeAttribute] = []

    private static let connectionTags: Set<String> = ["outlet", "outletCollection", "action", "binding", "segue"]

    static func parse(_ data: Data, path: String) throws -> BindingXibDocument {
        return BindingXibDocument(root: try BindingXMLParser.parse(data, path: path), path: path)
    }

    init(root: BindingXMLElement, path: String) {
        self.path = path
        for element in root.descendants() {
            if element.tag == "userDefinedRuntimeAttribute",
               let keyPath = element["keyPath"],
               let owner = element.parent?.parent,
               let ownerID = owner["id"] {
                runtimeAttributes.append(BindingXibRuntimeAttribute(ownerID: ownerID, keyPath: keyPath))
                continue
            }
            if Self.connectionTags.contains(element.tag) {
                guard element.parent?.tag == "connections",
                      let source = element.parent?.parent,
                      let sourceID = source["id"],
                      let kind = BindingXibConnection.Kind(rawValue: element.tag) else {
                    continue
                }
                let name: String?
                let destination: String?
                switch kind {
                case .outlet, .outletCollection:
                    name = element["property"]
                    destination = element["destination"]
                case .action:
                    name = element["selector"]
                    destination = element["target"]
                case .binding:
                    name = element["name"]
                    destination = element["destination"]
                }
                if let name, let destination {
                    connections.append(BindingXibConnection(kind: kind,
                                                            id: element["id"] ?? "",
                                                            sourceID: sourceID,
                                                            name: name,
                                                            destinationID: destination,
                                                            keyPath: element["keyPath"]))
                }
                continue
            }
            guard let id = element["id"] else {
                continue
            }
            let role: BindingXibObject.Role
            if id == "-2" || element["placeholderIdentifier"] == "IBFilesOwner" {
                role = .fileOwner
            } else if id == "-1" || element["placeholderIdentifier"] == "IBFirstResponder" || element["sceneMemberID"] == "firstResponder" {
                role = .firstResponder
            } else if id == "-3" || element.tag == "application" {
                role = .application
            } else {
                role = .regular
            }
            let label = element["userLabel"] ?? element["title"] ?? element["identifier"]
            objects[id] = BindingXibObject(id: id,
                                           tag: element.tag,
                                           customClass: element["customClass"],
                                           customModule: element["customModule"],
                                           label: label,
                                           role: role)
            objectOrder.append(id)
        }
    }
}

struct BindingXibCounts {
    var customClasses = 0
    var outlets = 0
    var actionsToObjects = 0
    var actionsToFileOwner = 0
    var actionsToApplication = 0
    var actionsToFirstResponder = 0
    var bindings = 0
    var runtimeAttributes = 0
    var uncheckedDeeperKeys = 0

    static func + (lhs: BindingXibCounts, rhs: BindingXibCounts) -> BindingXibCounts {
        var r = lhs
        r.customClasses += rhs.customClasses
        r.outlets += rhs.outlets
        r.actionsToObjects += rhs.actionsToObjects
        r.actionsToFileOwner += rhs.actionsToFileOwner
        r.actionsToApplication += rhs.actionsToApplication
        r.actionsToFirstResponder += rhs.actionsToFirstResponder
        r.bindings += rhs.bindings
        r.runtimeAttributes += rhs.runtimeAttributes
        r.uncheckedDeeperKeys += rhs.uncheckedDeeperKeys
        return r
    }
}

struct BindingFirstResponderAction: Hashable {
    let file: String
    let elementID: String
    let label: String?
    let selector: String
}

struct BindingXibResult {
    var problems = [BindingProblem]()
    var firstResponderActions = [BindingFirstResponderAction]()
    var counts = BindingXibCounts()
}

enum BindingXibChecker {
    // The class AppKit instantiates for an element with no customClass. Most
    // element names are the class name without NS and with a lowercase first
    // letter; these are the exceptions.
    static let elementClassExceptions: [String: String] = [
        "customObject": "NSObject",
        "customView": "NSView",
        "pagecontroller": "NSPageController",
        "constraint": "NSLayoutConstraint",
    ]

    static func defaultClassName(forTag tag: String) -> String {
        if let name = elementClassExceptions[tag] {
            return name
        }
        return "NS" + BindingRuntimeQueries.capitalized(tag)
    }

    // The class name a nib records for a custom class. With a customModule,
    // ibtool writes the Swift mangled name of a top-level class
    // (_TtC<length><module><length><name>; checked against the compiled nibs
    // in the app bundle), and NIB loading looks that up with
    // NSClassFromString. Without one it writes the name as given.
    static func recordedClassName(_ customClass: String, module: String?) -> String {
        guard let module, !module.isEmpty else {
            return customClass
        }
        return "_TtC\(module.utf8.count)\(module)\(customClass.utf8.count)\(customClass)"
    }

    static func displayName(_ customClass: String, module: String?) -> String {
        guard let module, !module.isEmpty else {
            return customClass
        }
        return "\(module).\(customClass)"
    }

    static func check(_ document: BindingXibDocument,
                      queries: BindingRuntimeQueries,
                      applicationClass: String) -> BindingXibResult {
        let runtime = queries.runtime
        var result = BindingXibResult()
        let file = document.path

        func problem(_ kind: String, _ object: BindingXibObject?, id: String, _ name: String, _ detail: String) {
            result.problems.append(BindingProblem(file: file,
                                                  kind: kind,
                                                  elementID: id,
                                                  label: object?.label,
                                                  name: name,
                                                  detail: detail))
        }

        // 1. Custom classes.
        var resolvedCustom = [String: String]()
        for id in document.objectOrder {
            guard let object = document.objects[id],
                  let customClass = object.customClass,
                  object.role != .firstResponder,
                  object.role != .application else {
                continue
            }
            result.counts.customClasses += 1
            let recorded = recordedClassName(customClass, module: object.customModule)
            if let runtimeName = runtime.resolveClass(recorded) {
                resolvedCustom[id] = runtimeName
            } else {
                let detail = recorded == customClass
                    ? "does not resolve with NSClassFromString"
                    : "does not resolve with NSClassFromString(\"\(recorded)\"), the name the compiled nib records"
                problem("customClass", object, id: id, displayName(customClass, module: object.customModule), detail)
            }
        }

        // The runtime class of an object, or nil when it is unknown (an
        // unresolved custom class, already reported) or not a class at all
        // (First Responder).
        var reportedElementClasses = Set<String>()
        func runtimeClass(of id: String) -> String? {
            guard let object = document.objects[id] else {
                return nil
            }
            switch object.role {
            case .firstResponder:
                return nil
            case .application:
                return applicationClass
            case .fileOwner, .regular:
                if object.customClass != nil {
                    return resolvedCustom[id]
                }
                if object.role == .fileOwner {
                    return "NSObject"
                }
                let name = defaultClassName(forTag: object.tag)
                if let runtimeName = runtime.resolveClass(name) {
                    return runtimeName
                }
                if !reportedElementClasses.contains(id) {
                    reportedElementClasses.insert(id)
                    problem("elementClass", object, id: id, name, "is the class assumed for element <\(object.tag)> and does not resolve; add the element to BindingXibChecker.elementClassExceptions")
                }
                return nil
            }
        }

        func missingObject(_ connection: BindingXibConnection, _ role: String) {
            let source = document.objects[connection.sourceID]
            problem("\(connection.kind.rawValue)\(role)", source, id: connection.sourceID, connection.name, "names \(role.lowercased()) id \(connection.destinationID), which is not an object in the file")
        }

        // 2. Connections.
        for connection in document.connections {
            let source = document.objects[connection.sourceID]
            switch connection.kind {
            case .outlet, .outletCollection:
                result.counts.outlets += 1
                if document.objects[connection.destinationID] == nil {
                    missingObject(connection, "Destination")
                }
                guard let cls = runtimeClass(of: connection.sourceID) else {
                    continue
                }
                if queries.kvcSetter(cls, key: connection.name) == nil {
                    problem(connection.kind.rawValue, source, id: connection.sourceID, connection.name,
                            "is not settable by key-value coding on \(cls) (no set\(BindingRuntimeQueries.capitalized(connection.name)): or _set...: method, no matching instance variable)")
                }
            case .action:
                guard let target = document.objects[connection.destinationID] else {
                    missingObject(connection, "Target")
                    continue
                }
                switch target.role {
                case .firstResponder:
                    result.counts.actionsToFirstResponder += 1
                    result.firstResponderActions.append(BindingFirstResponderAction(file: file,
                                                                                    elementID: connection.sourceID,
                                                                                    label: source?.label,
                                                                                    selector: connection.name))
                    continue
                case .fileOwner:
                    result.counts.actionsToFileOwner += 1
                case .application:
                    result.counts.actionsToApplication += 1
                case .regular:
                    result.counts.actionsToObjects += 1
                }
                guard let cls = runtimeClass(of: target.id) else {
                    continue
                }
                if !queries.instancesRespond(cls, to: connection.name) {
                    problem("action", source, id: connection.sourceID, connection.name,
                            "is not implemented by \(cls), the class of its target id \(target.id)\(target.label.map { " (\($0))" } ?? "")")
                }
            case .binding:
                result.counts.bindings += 1
                guard document.objects[connection.destinationID] != nil else {
                    missingObject(connection, "Destination")
                    continue
                }
                guard let keyPath = connection.keyPath, let cls = runtimeClass(of: connection.destinationID) else {
                    continue
                }
                switch queries.checkKeyPath(keyPath, on: cls, settingLast: false) {
                case let .resolved(_, unchecked):
                    result.counts.uncheckedDeeperKeys += unchecked
                case let .failed(key, onClass):
                    problem("binding", source, id: connection.sourceID, keyPath,
                            "key “\(key)” of the \(connection.name) binding does not resolve with valueForKey: on \(onClass) (destination id \(connection.destinationID))")
                }
            }
        }

        // 3. User-defined runtime attributes: set with setValue:forKeyPath:
        // on the object when the nib loads.
        for attribute in document.runtimeAttributes {
            result.counts.runtimeAttributes += 1
            let owner = document.objects[attribute.ownerID]
            guard let cls = runtimeClass(of: attribute.ownerID) else {
                continue
            }
            switch queries.checkKeyPath(attribute.keyPath, on: cls, settingLast: true) {
            case let .resolved(_, unchecked):
                result.counts.uncheckedDeeperKeys += unchecked
            case let .failed(key, onClass):
                problem("runtimeAttribute", owner, id: attribute.ownerID, attribute.keyPath,
                        "key “\(key)” does not resolve with setValue:forKeyPath: on \(onClass)")
            }
        }
        return result
    }
}

// MARK: - First Responder actions

enum BindingFirstResponderChecker {
    struct Result {
        var problems = [BindingProblem]()
        // Lines describing each difference between the recorded table and
        // the runtime, and the replacement table entries to paste.
        var tableDifferences = [String]()
        var pasteLines = [String]()
        var implementers = [String: BindingImplementers]()
    }

    static func tableLine(_ selector: String, _ classes: [String]) -> String {
        let list = classes.map { "\"\($0)\"" }.joined(separator: ", ")
        return "        \"\(selector)\": [\(list)],"
    }

    // Every First Responder action must be implemented somewhere in the app
    // or AppKit, and the app classes implementing each selector must equal
    // the recorded table, so that a port that drops or adds an implementer
    // fails until the table is updated deliberately.
    static func check(_ actions: [BindingFirstResponderAction],
                      runtime: BindingRuntime,
                      recorded: [String: [String]]) -> Result {
        var result = Result()
        let selectors = Set(actions.map(\.selector))
        let implementers = runtime.implementers(of: selectors)
        result.implementers = implementers
        for action in actions {
            let found = implementers[action.selector] ?? BindingImplementers(app: [], system: [])
            if found.app.isEmpty && found.system.isEmpty {
                result.problems.append(BindingProblem(file: action.file,
                                                      kind: "firstResponderAction",
                                                      elementID: action.elementID,
                                                      label: action.label,
                                                      name: action.selector,
                                                      detail: "is implemented by no class in the app, AppKit or Foundation, so the menu item or control is always disabled"))
            }
        }
        for selector in selectors.union(recorded.keys).sorted() {
            let actual = selectors.contains(selector) ? (implementers[selector]?.app ?? []) : nil
            let expected = recorded[selector]
            if actual == expected {
                continue
            }
            switch (expected, actual) {
            case let (nil, actual?):
                result.tableDifferences.append("\(selector): not in the recorded table; app implementers now \(actual)")
                result.pasteLines.append("add:     " + tableLine(selector, actual))
            case (_?, nil):
                result.tableDifferences.append("\(selector): recorded, but no First Responder action uses it any more")
                result.pasteLines.append("remove:  " + tableLine(selector, expected ?? []))
            case let (expected?, actual?):
                let added = Set(actual).subtracting(expected).sorted()
                let removed = Set(expected).subtracting(actual).sorted()
                result.tableDifferences.append("\(selector): implementers added \(added), removed \(removed)")
                result.pasteLines.append("replace: " + tableLine(selector, actual))
            case (nil, nil):
                break
            }
        }
        return result
    }
}

// MARK: - Scripting definition (sdef)

struct BindingSdefCounts {
    var classes = 0
    var properties = 0
    var elements = 0
    var respondsTo = 0
    var commands = 0
    var commandClasses = 0
    var valueTypes = 0
}

enum BindingSdefChecker {
    // Cocoa scripting's default key for a property with no cocoa key: the
    // name with spaces removed and every word but the first capitalized.
    static func camelCase(_ name: String) -> String {
        let words = name.split(separator: " ").map(String.init)
        guard let first = words.first else {
            return name
        }
        return ([first.lowercased()] + words.dropFirst().map { BindingRuntimeQueries.capitalized($0) }).joined()
    }

    // `forwardingTargets` names, for a class that forwards key-value coding
    // and messages to another object (an NSProxy), the classes that receive
    // them; every key and method of that class is then checked on each of
    // them instead.
    static func check(_ root: BindingXMLElement,
                      path: String,
                      queries: BindingRuntimeQueries,
                      forwardingTargets: (String) -> [String]?) -> (problems: [BindingProblem], counts: BindingSdefCounts) {
        let runtime = queries.runtime
        var problems = [BindingProblem]()
        var counts = BindingSdefCounts()
        func problem(_ kind: String, _ element: String, _ label: String?, _ name: String, _ detail: String) {
            problems.append(BindingProblem(file: path, kind: kind, elementID: element, label: label, name: name, detail: detail))
        }

        let all = root.descendants()
        let commandNames = Set(all.filter { $0.tag == "command" }.compactMap { $0["name"] })
        var classElements = [String: BindingXMLElement]()
        for element in all where element.tag == "class" {
            if let name = element["name"] {
                classElements[name] = element
            }
        }

        // Commands: the class must exist and be an NSScriptCommand. A
        // command without a cocoa class is an NSScriptCommand. Parameter
        // cocoa keys are keys of the command's argument dictionary, not of
        // any class, so there is nothing to look up for them.
        for command in all where command.tag == "command" {
            counts.commands += 1
            let name = command["name"] ?? "?"
            guard let cocoaClass = command.firstChild(named: "cocoa")?["class"] else {
                continue
            }
            counts.commandClasses += 1
            guard let runtimeName = runtime.resolveClass(cocoaClass) else {
                problem("commandClass", "command \(name)", nil, cocoaClass, "does not resolve with NSClassFromString")
                continue
            }
            if !queries.isSubclass(runtimeName, of: "NSScriptCommand") {
                problem("commandClass", "command \(name)", nil, cocoaClass, "is not a subclass of NSScriptCommand")
            }
        }

        for valueType in all where valueType.tag == "value-type" {
            counts.valueTypes += 1
            if let cocoaClass = valueType.firstChild(named: "cocoa")?["class"], runtime.resolveClass(cocoaClass) == nil {
                problem("valueTypeClass", "value-type \(valueType["name"] ?? "?")", nil, cocoaClass, "does not resolve with NSClassFromString")
            }
        }

        for cls in all where cls.tag == "class" || cls.tag == "class-extension" {
            let sdefName = cls["name"] ?? cls["extends"] ?? "?"
            let elementName = "\(cls.tag) \(sdefName)"
            counts.classes += 1
            let classElement = cls.tag == "class" ? cls : classElements[cls["extends"] ?? ""]
            let cocoaClass = classElement?.firstChild(named: "cocoa")?["class"]
                ?? BindingRuntimeQueries.capitalized(camelCase(sdefName))
            guard let runtimeName = runtime.resolveClass(cocoaClass) else {
                problem("class", elementName, nil, cocoaClass, "does not resolve with NSClassFromString")
                continue
            }
            let targets = forwardingTargets(runtimeName) ?? [runtimeName]
            let via = targets == [runtimeName] ? "" : " (\(runtimeName) forwards to it)"

            for property in cls.children(named: "property") {
                counts.properties += 1
                let propertyName = property["name"] ?? "?"
                let key = property.firstChild(named: "cocoa")?["key"] ?? camelCase(propertyName)
                let writable = (property["access"] ?? "rw").contains("w")
                for target in targets {
                    if queries.kvcGetter(target, key: key) == nil {
                        problem("propertyKey", elementName, propertyName, key, "does not resolve with valueForKey: on \(target)\(via)")
                    } else if writable && queries.kvcSetter(target, key: key) == nil {
                        problem("propertySetter", elementName, propertyName, key, "is read-write in the sdef but not settable with setValue:forKey: on \(target)\(via)")
                    }
                }
            }

            for element in cls.children(named: "element") {
                counts.elements += 1
                let type = element["type"] ?? "?"
                let plural = classElements[type]?["plural"] ?? (type + "s")
                let key = element.firstChild(named: "cocoa")?["key"] ?? camelCase(plural)
                let writable = (element["access"] ?? "rw").contains("w")
                let cap = BindingRuntimeQueries.capitalized(key)
                for target in targets {
                    if queries.kvcGetter(target, key: key) == nil {
                        problem("elementKey", elementName, "element \(type)", key, "does not resolve with valueForKey: on \(target)\(via)")
                    } else if writable,
                              !queries.instancesRespond(target, to: "insertObject:in\(cap)AtIndex:"),
                              !queries.instancesRespond(target, to: "insert\(cap):atIndexes:") {
                        problem("elementInsert", elementName, "element \(type)", key, "is writable in the sdef but \(target) has no insertObject:in\(cap)AtIndex: or insert\(cap):atIndexes:\(via)")
                    }
                }
            }

            for respondsTo in cls.children(named: "responds-to") {
                counts.respondsTo += 1
                let command = respondsTo["command"] ?? respondsTo["name"] ?? "?"
                if !commandNames.contains(command) {
                    problem("respondsToCommand", elementName, nil, command, "names no command of the sdef")
                }
                // Without a cocoa method the command class does the work.
                guard let method = respondsTo.firstChild(named: "cocoa")?["method"] else {
                    continue
                }
                for target in targets where !queries.instancesRespond(target, to: method) {
                    problem("respondsToMethod", elementName, "responds-to \(command)", method, "is not implemented by \(target)\(via)")
                }
            }
        }
        return (problems, counts)
    }
}

// MARK: - Info.plist

enum BindingInfoPlistChecker {
    struct Counts {
        var principalClass = 0
        var services = 0
        var documentClasses = 0
        var documentTypes = 0
    }

    // `servicesProvider` is the class of the object the app passes to
    // -[NSApplication setServicesProvider:]. URL scheme and Apple event
    // handlers are registered in code, not in Info.plist, and are out of
    // scope here.
    static func check(_ plist: [String: Any],
                      file: String,
                      queries: BindingRuntimeQueries,
                      servicesProvider: String) -> (problems: [BindingProblem], counts: Counts) {
        let runtime = queries.runtime
        var problems = [BindingProblem]()
        var counts = Counts()
        func problem(_ kind: String, _ element: String, _ name: String, _ detail: String) {
            problems.append(BindingProblem(file: file, kind: kind, elementID: element, label: nil, name: name, detail: detail))
        }
        if let principal = plist["NSPrincipalClass"] as? String {
            counts.principalClass += 1
            if let runtimeName = runtime.resolveClass(principal) {
                if !queries.isSubclass(runtimeName, of: "NSApplication") {
                    problem("principalClass", "NSPrincipalClass", principal, "is not a subclass of NSApplication")
                }
            } else {
                problem("principalClass", "NSPrincipalClass", principal, "does not resolve with NSClassFromString")
            }
        }
        if let services = plist["NSServices"] as? [[String: Any]] {
            let provider = runtime.resolveClass(servicesProvider)
            if provider == nil {
                problem("servicesProvider", "NSServices", servicesProvider, "does not resolve with NSClassFromString")
            }
            for (index, service) in services.enumerated() {
                guard let message = service["NSMessage"] as? String else {
                    continue
                }
                counts.services += 1
                let selector = "\(message):userData:error:"
                if let provider, !queries.instancesRespond(provider, to: selector) {
                    problem("serviceMessage", "NSServices[\(index)]", selector, "is not implemented by the services provider \(provider)")
                }
            }
        }
        if let types = plist["CFBundleDocumentTypes"] as? [[String: Any]] {
            for (index, type) in types.enumerated() {
                counts.documentTypes += 1
                guard let documentClass = type["NSDocumentClass"] as? String else {
                    continue
                }
                counts.documentClasses += 1
                if let runtimeName = runtime.resolveClass(documentClass) {
                    if !queries.isSubclass(runtimeName, of: "NSDocument") {
                        problem("documentClass", "CFBundleDocumentTypes[\(index)]", documentClass, "is not a subclass of NSDocument")
                    }
                } else {
                    problem("documentClass", "CFBundleDocumentTypes[\(index)]", documentClass, "does not resolve with NSClassFromString")
                }
            }
        }
        return (problems, counts)
    }
}

// MARK: - Core Data

enum BindingCoreDataChecker {
    static func check(_ root: BindingXMLElement,
                      file: String,
                      queries: BindingRuntimeQueries) -> (problems: [BindingProblem], entities: Int) {
        var problems = [BindingProblem]()
        var entities = 0
        for entity in root.descendants() where entity.tag == "entity" {
            entities += 1
            let name = entity["name"] ?? "?"
            // An entity without representedClassName is an NSManagedObject.
            guard let className = entity["representedClassName"] else {
                continue
            }
            guard let runtimeName = queries.runtime.resolveClass(className) else {
                problems.append(BindingProblem(file: file, kind: "entityClass", elementID: "entity \(name)", label: nil, name: className, detail: "does not resolve with NSClassFromString"))
                continue
            }
            if !queries.isSubclass(runtimeName, of: "NSManagedObject") {
                problems.append(BindingProblem(file: file, kind: "entityClass", elementID: "entity \(name)", label: nil, name: className, detail: "is not a subclass of NSManagedObject"))
            }
        }
        return (problems, entities)
    }
}

// MARK: - Names persisted or sent between processes

enum BindingPersistedNamesChecker {
    enum Kind: String {
        // A keyed archive, user defaults or saved state records the name.
        case persisted
        // NSXPC sends the class name; compiled into two targets.
        case xpc
        // A keyed archive on the drag pasteboard records it.
        case pasteboard
        // AppKit stores the restoration class name in saved application
        // state.
        case appkit
    }

    struct Name {
        let name: String
        let runtimeName: String
        let kind: Kind
    }

    static let file = "docs/swift-migration/reflective-sites.md"

    static func check(names: [Name],
                      protocols: [(name: String, selectors: [String])],
                      restorationClasses: [String],
                      restorationSelector: String,
                      queries: BindingRuntimeQueries) -> [BindingProblem] {
        let runtime = queries.runtime
        var problems = [BindingProblem]()
        func problem(_ kind: String, _ element: String, _ name: String, _ detail: String) {
            problems.append(BindingProblem(file: file, kind: kind, elementID: element, label: nil, name: name, detail: detail))
        }
        for entry in names {
            guard let found = runtime.resolveClass(entry.runtimeName) else {
                problem("persistedName", "names table: \(entry.name) (\(entry.kind.rawValue))", entry.runtimeName, "does not resolve with NSClassFromString")
                continue
            }
            if found != entry.runtimeName {
                problem("persistedName", "names table: \(entry.name) (\(entry.kind.rawValue))", entry.runtimeName, "resolves, but NSStringFromClass gives “\(found)”: the stored or sent name changed")
            }
        }
        for proto in protocols {
            for selector in proto.selectors {
                switch runtime.protocolHasInstanceMethod(proto.name, selector) {
                case nil:
                    problem("xpcProtocol", "protocol \(proto.name)", proto.name, "is not a protocol known to the runtime")
                case false?:
                    problem("xpcSelector", "protocol \(proto.name)", selector, "is neither a required nor an optional method of the protocol")
                case true?:
                    break
                }
            }
        }
        for name in restorationClasses {
            guard let runtimeName = runtime.resolveClass(name) else {
                problem("restorationClass", "window restoration", name, "does not resolve with NSClassFromString")
                continue
            }
            if !queries.classResponds(runtimeName, to: restorationSelector) {
                problem("restorationClass", "window restoration", name, "does not respond to +\(restorationSelector)")
            }
        }
        return problems.reduce(into: [BindingProblem]()) { result, p in
            if !result.contains(p) {
                result.append(p)
            }
        }
    }
}

// MARK: - Keyed archives in the stored-state corpus

struct BindingArchive {
    // Where the archive was found: the file, then a path inside it.
    let file: String
    let location: String
    // Every $classname and every member of every $classes chain, in order of
    // appearance, without duplicates.
    let classNames: [String]
}

enum BindingArchiveScanner {
    static func isPropertyList(_ data: Data) -> Bool {
        if data.starts(with: Array("bplist00".utf8)) {
            return true
        }
        let head = data.prefix(400)
        guard let text = String(data: head, encoding: .utf8) ?? String(data: head, encoding: .isoLatin1) else {
            return false
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<?xml") && text.contains("<plist")
    }

    // Finds keyed archives in a property list: the value itself when it is
    // an archive, and any data value anywhere inside it that is itself a
    // property list (recursively), as tools/swift_migration/
    // stored_state_digest.py does.
    static func archives(inPropertyList value: Any, file: String, location: String) -> [BindingArchive] {
        var result = [BindingArchive]()
        if let dictionary = value as? [String: Any] {
            if dictionary["$archiver"] as? String == "NSKeyedArchiver",
               let objects = dictionary["$objects"] as? [Any] {
                var names = [String]()
                var seen = Set<String>()
                func add(_ name: String) {
                    if !seen.contains(name) {
                        seen.insert(name)
                        names.append(name)
                    }
                }
                for case let object as [String: Any] in objects {
                    if let classname = object["$classname"] as? String {
                        add(classname)
                    }
                    if let chain = object["$classes"] as? [String] {
                        chain.forEach(add)
                    }
                }
                result.append(BindingArchive(file: file, location: location, classNames: names))
            }
            for key in dictionary.keys.sorted() {
                result.append(contentsOf: archives(inPropertyList: dictionary[key]!, file: file, location: location + "/" + key))
            }
        } else if let array = value as? [Any] {
            for (index, element) in array.enumerated() {
                result.append(contentsOf: archives(inPropertyList: element, file: file, location: location + "/\(index)"))
            }
        } else if let data = value as? Data {
            result.append(contentsOf: archives(inData: data, file: file, location: location + "/<data>"))
        }
        return result
    }

    static func archives(inData data: Data, file: String, location: String) -> [BindingArchive] {
        guard isPropertyList(data),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return []
        }
        return archives(inPropertyList: plist, file: file, location: location)
    }

    enum SQLiteError: Error, CustomStringConvertible {
        case failed(String, String)
        var description: String {
            switch self {
            case let .failed(file, message):
                return "\(file): \(message)"
            }
        }
    }

    // Reads every blob of every table. The database is copied to a temporary
    // directory first: the corpus files are in WAL mode, and opening one in
    // place would create -shm and -wal files next to it. A -wal file next to
    // the source is copied too, so that writes not yet checkpointed into the
    // main file are read; the -shm file is not needed, SQLite rebuilds it
    // from the -wal file. The copy (never the source) is then switched to
    // journal_mode=DELETE, which checkpoints the -wal file into it, and
    // reopened read-only: a read-only connection cannot open a database in
    // WAL mode when it would have to create the -shm file. (immutable=1 is
    // not used: it would ignore the -wal file.)
    static func archives(inSQLiteAt url: URL, file: String) throws -> [BindingArchive] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("binding-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let copy = directory.appendingPathComponent("db.sqlite")
        try FileManager.default.copyItem(at: url, to: copy)
        let wal = URL(fileURLWithPath: url.path + "-wal")
        if FileManager.default.fileExists(atPath: wal.path) {
            try FileManager.default.copyItem(at: wal, to: URL(fileURLWithPath: copy.path + "-wal"))
        }
        do {
            var writer: OpaquePointer?
            let opened = sqlite3_open_v2(copy.path, &writer, SQLITE_OPEN_READWRITE, nil)
            defer {
                sqlite3_close(writer)
            }
            guard opened == SQLITE_OK else {
                throw SQLiteError.failed(file, "cannot open the copy to checkpoint it")
            }
            guard sqlite3_exec(writer, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else {
                throw SQLiteError.failed(file, "cannot checkpoint the copy: \(String(cString: sqlite3_errmsg(writer)))")
            }
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw SQLiteError.failed(file, "cannot open")
        }
        defer {
            sqlite3_close(db)
        }
        func rows(_ sql: String, _ body: (OpaquePointer) -> Void) throws {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw SQLiteError.failed(file, "cannot prepare \(sql): \(String(cString: sqlite3_errmsg(db)))")
            }
            defer {
                sqlite3_finalize(statement)
            }
            while sqlite3_step(statement) == SQLITE_ROW {
                body(statement)
            }
        }
        var tables = [String]()
        try rows("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name") { statement in
            tables.append(sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "")
        }
        var result = [BindingArchive]()
        for table in tables {
            let quoted = table.replacingOccurrences(of: "\"", with: "\"\"")
            try rows("SELECT rowid, * FROM \"\(quoted)\" ORDER BY rowid") { statement in
                let rowid = sqlite3_column_int64(statement, 0)
                for column in 1..<sqlite3_column_count(statement) where sqlite3_column_type(statement, column) == SQLITE_BLOB {
                    let count = Int(sqlite3_column_bytes(statement, column))
                    guard count > 0, let bytes = sqlite3_column_blob(statement, column) else {
                        continue
                    }
                    let data = Data(bytes: bytes, count: count)
                    let name = sqlite3_column_name(statement, column).map { String(cString: $0) } ?? "\(column)"
                    result.append(contentsOf: archives(inData: data, file: file, location: "table \(table) rowid \(rowid) column \(name)"))
                }
            }
        }
        return result
    }

    // One problem per file and class name, at the first archive that names
    // it.
    static func check(_ archives: [BindingArchive], runtime: BindingRuntime) -> [BindingProblem] {
        var problems = [BindingProblem]()
        var reported = Set<String>()
        for archive in archives {
            for name in archive.classNames where runtime.resolveClass(name) == nil {
                let key = archive.file + "|" + name
                if reported.contains(key) {
                    continue
                }
                reported.insert(key)
                problems.append(BindingProblem(file: archive.file,
                                               kind: "archiveClass",
                                               elementID: "archive",
                                               label: nil,
                                               name: name,
                                               detail: "is recorded in a keyed archive (first at \(archive.location)) and does not resolve with NSClassFromString"))
            }
        }
        return problems
    }
}
