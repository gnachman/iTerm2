//
//  Porthole.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/13/22.
//

import Foundation

@objc
protocol PortholeMarkReading: iTermMarkProtocol {
    var uniqueIdentifier: String { get }
}

@objc
class PortholeMark: iTermMark, PortholeMarkReading {
    private static let mutex = Mutex()
    let uniqueIdentifier: String

    private let uniqueIdentifierKey = "PortholeUniqueIdentifier"

    override var shortDebugDescription: String {
        return "[Porthole]"
    }

    override var description: String {
        return "<PortholeMark: \(it_addressString) id=\(uniqueIdentifier) \(isDoppelganger ? "IsDop" : "NotDop")>"
    }

    @objc
    init(_ uniqueIdentifier: String) {
        self.uniqueIdentifier = uniqueIdentifier

        super.init()

        PortholeRegistry.instance.set(uniqueIdentifier, mark: doppelganger() as! PortholeMarkReading)
    }

    required init?(dictionary dict: [AnyHashable : Any]) {
        guard let uniqueIdentifier = dict[uniqueIdentifierKey] as? String else {
            return nil
        }
        self.uniqueIdentifier = uniqueIdentifier

        super.init()
    }

    deinit {
        if !isDoppelganger {
            PortholeRegistry.instance.remove(uniqueIdentifier)
        }
    }

    override func dictionaryValue() -> [AnyHashable : Any]! {
        return [uniqueIdentifierKey: uniqueIdentifier].compactMapValues { $0 }
    }
}

enum PortholeType: String {
    case text = "Text"

    static func unwrap(dictionary: [String: AnyObject]) -> (type: PortholeType, info: [String: AnyObject])? {
        guard let typeString = dictionary[portholeType] as? String,
              let type = PortholeType(rawValue: typeString),
              let info = dictionary[portholeInfo] as? [String: AnyObject] else {
            return nil
        }
        return (type: type, info: info)
    }
}

struct PortholeConfig: CustomDebugStringConvertible {
    var text: String
    var colorMap: iTermColorMapReading
    var baseDirectory: URL?
    var font: NSFont
    var type: String?
    var filename: String?
    var useSelectedTextColor: Bool
    var forceWide: Bool

    var debugDescription: String {
        "PortholeConfig(text=\(text) baseDirectory=\(String(describing: baseDirectory)) font=\(font) type=\(String(describing: type)) filename=\(String(describing: filename)) useSelectedTextColor=\(useSelectedTextColor) forceWide=\(forceWide)"
    }
}

protocol PortholeDelegate: AnyObject {
    func portholeDidAcquireSelection(_ porthole: Porthole)
    func portholeRemove(_ porthole: Porthole)
    func portholeResize(_ porthole: Porthole)
    func portholeAbsLine(_ porthole: Porthole) -> Int64
    func portholeHeight(_ porthole: Porthole) -> Int32
}

@objc(Porthole)
protocol ObjCPorthole: AnyObject {
    @objc var view: NSView { get }
    @objc var uniqueIdentifier: String { get }
    @objc var dictionaryValue: [String: AnyObject] { get }
    @objc func fit(toWidth width: CGFloat) -> CGFloat
    @objc func removeSelection()
    @objc func updateColors(useSelectedTextColor: Bool)
    @objc var savedLines: [ScreenCharArray] { get set }
    // Inset the view by this amount top and bottom.
    @objc var outerMargin: CGFloat { get }
}

enum PortholeCopyMode {
    case plainText
    case attributedString
    case controlSequences
}

protocol Porthole: ObjCPorthole {
    static var type: PortholeType { get }
    var delegate: PortholeDelegate? { get set }
    var config: PortholeConfig { get }
    var hasSelection: Bool { get }
    func copy(as: PortholeCopyMode)
    var mark: PortholeMarkReading? { get }
    func set(frame: NSRect)
    func find(_ query: String, mode: iTermFindMode) -> [ExternalSearchResult]
    func select(searchResult: ExternalSearchResult,
                multiple: Bool,
                returningRectRelativeTo view: NSView,
                scroll: Bool) -> NSRect?
    func snippet(for result: ExternalSearchResult,
                 matchAttributes: [NSAttributedString.Key: Any],
                 regularAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString?
    func removeHighlights()
}

fileprivate let portholeType = "Type"
fileprivate let portholeInfo = "Info"

extension Porthole {
    func wrap(dictionary: [String: Any]) -> [String: AnyObject] {
        return [portholeType: Self.type.rawValue as NSString,
                portholeInfo: dictionary as NSDictionary]
    }
}

@objc
class PortholeRegistry: NSObject {
    @objc static var instance = PortholeRegistry()
    private var portholes = [String: ObjCPorthole]()
    private var pending = [String: NSDictionary]()
    private var marks = [String: PortholeMarkReading]()
    private var _generation: Int = 0
    @objc var generation: Int {
        get {
            return mutex.sync { _generation }
        }
        set {
            return mutex.sync { self._generation = newValue }
        }
    }
    private let mutex = Mutex()

    func add(_ porthole: ObjCPorthole) {
        DLog("add \(porthole)")
        mutex.sync {
            portholes[porthole.uniqueIdentifier] = porthole
            incrementGeneration()
        }
    }

    func remove(_ key: String) {
        DLog("remove \(key)")
        mutex.sync {
            _ = portholes.removeValue(forKey: key)
            _ = marks.removeValue(forKey: key)
            incrementGeneration()
        }
    }

    @objc(registerKey:forMark:)
    func set(_ key: String, mark: PortholeMarkReading) {
        DLog("register mark \(mark) for \(key)")
        mutex.sync {
            marks[key] = mark
            incrementGeneration()
        }
    }

    @objc(markForKey:)
    func mark(for key: String) -> PortholeMarkReading? {
        return mutex.sync {
            marks[key]
        }
    }

    func get(_ key: String, colorMap: iTermColorMapReading, useSelectedTextColor: Bool, font: NSFont) -> ObjCPorthole? {
        mutex.sync {
            if let porthole = portholes[key] {
                return porthole
            }
            guard let dict = pending[key] as? [String : AnyObject] else {
                return nil
            }
            pending.removeValue(forKey: key)
            DLog("hydrating \(key)")
            guard let porthole = PortholeFactory.porthole(dict,
                                                          colorMap: colorMap,
                                                          useSelectedTextColor: useSelectedTextColor,
                                                          font: font) else {
                return nil
            }
            portholes[key] = porthole
            incrementGeneration()
            return porthole
        }
    }

    @objc subscript(_ key: String) -> ObjCPorthole? {
        return mutex.sync {
            return portholes[key]
        }
    }

    func incrementGeneration() {
        _generation += 1
        DispatchQueue.main.async {
            NSApp.invalidateRestorableState()
        }
    }

    private let portholesKey = "Portholes"
    private let pendingKey = "Pending"
    private let generationKey = "Generation"

    @objc var dictionaryValue: [String: AnyObject] {
        let dicts = portholes.mapValues { porthole in
            porthole.dictionaryValue as NSDictionary
        }
        return [portholesKey: dicts as NSDictionary,
               generationKey: NSNumber(value: _generation)]
    }

    @objc func load(_ dictionary: [String: AnyObject]) {
        mutex.sync {
            if let pending = dictionary[pendingKey] as? [String: NSDictionary],
                let generation = dictionary[generationKey] as? Int,
               let portholes = dictionary[portholesKey] as? [String: NSDictionary] {
                self.pending = pending.merging(portholes) { lhs, _ in lhs }
                self.generation = generation
            }
        }
    }

    // Note that marks are not restored. They go through the normal mark restoration process which
    // as a side-effect adds them to the porthole registry.
    @objc func encodeAsChild(with encoder: iTermGraphEncoder, key: String) {
        mutex.sync {
            _ = encoder.encodeChild(withKey: key,
                                    identifier: "",
                                    generation: _generation) { subencoder in
                let keys = portholes.keys.sorted()
                subencoder.encodeArray(withKey: "portholes",
                                       generation: iTermGenerationAlwaysEncode,
                                       identifiers: keys) { identifier, index, subencoder, stop in
                    let adapter = iTermGraphEncoderAdapter(graphEncoder: subencoder)
                    let key = keys[index]
                    adapter.merge(portholes[key]!.dictionaryValue)
                    return true
                }
                return true
            }
        }
    }

    @objc(decodeRecord:) func decode(record: iTermEncoderGraphRecord) {
        mutex.sync {
            record.enumerateArray(withKey: "portholes") { identifier, index, plist, stop in
                guard let dict = plist as? NSDictionary else {
                    return
                }
                pending[identifier] = dict
            }
        }
    }
}
