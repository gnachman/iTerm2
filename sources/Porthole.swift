//
//  Porthole.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/13/22.
//

import Foundation

@objc
protocol PortholeMarkReading: iTermMarkProtocol {
    var porthole: ObjCPorthole { get }
}

@objc
class PortholeMark: iTermMark, PortholeMarkReading {
    private static let mutex = Mutex()

    private let uniqueIdentifierKey = "PortholeUniqueIdentifier"
    private let portholeDictKey = "State"

    override var description: String {
        return "<PortholeMark: \(it_addressString) porthole=\(porthole) \(isDoppelganger ? "IsDop" : "NotDop")>"
    }

    let porthole: ObjCPorthole

    @objc
    init(_ porthole: ObjCPorthole) {
        self.porthole = porthole
        PortholeRegistry.instance.add(porthole)

        super.init()

        porthole.mark = (doppelganger()! as! PortholeMarkReading)
    }

    required init?(dictionary dict: [AnyHashable : Any]) {
        guard let uniqueIdentifier = dict[uniqueIdentifierKey] as? String,
              let porthole = PortholeRegistry.instance[uniqueIdentifier] else {
            return nil
        }
        self.porthole = porthole

        super.init()
    }

    deinit {
        PortholeRegistry.instance.remove(porthole)
    }

    override func dictionaryValue() -> [AnyHashable : Any]! {
        return [uniqueIdentifierKey: porthole.uniqueIdentifier,
                    portholeDictKey: porthole.dictionaryValue]
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

struct PortholeConfig {
    var text: String
    var colorMap: iTermColorMapReading
    var baseDirectory: URL?
    var font: NSFont
}

protocol PortholeDelegate: AnyObject {
    func portholeDidAcquireSelection(_ porthole: Porthole)
    func portholeRemove(_ porthole: Porthole)
}

@objc(Porthole)
protocol ObjCPorthole: AnyObject {
    @objc var view: NSView { get }
    @objc var mark: PortholeMarkReading? { get set }
    @objc var uniqueIdentifier: String { get }
    @objc var dictionaryValue: [String: AnyObject] { get }
    @objc func desiredHeight(forWidth width: CGFloat) -> CGFloat  // includes top and bottom margin
    @objc func removeSelection()
    @objc func updateColors()
    @objc var savedLines: [ScreenCharArray] { get set }
    // Inset the view by this amount top and bottom.
    @objc var outerMargin: CGFloat { get }
}

protocol Porthole: ObjCPorthole {
    static var type: PortholeType { get }
    var delegate: PortholeDelegate? { get set }
    var config: PortholeConfig { get }
}

fileprivate let portholeType = "Type"
fileprivate let portholeInfo = "Info"

extension Porthole {
    func wrap(dictionary: [String: AnyObject]) -> [String: AnyObject] {
        return [portholeType: Self.type.rawValue as NSString,
                portholeInfo: dictionary as NSDictionary]
    }
}

@objc
class PortholeRegistry: NSObject {
    @objc static var instance = PortholeRegistry()
    private var portholes = [String: ObjCPorthole]()
    private var pending = [String: NSDictionary]()
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
        mutex.sync {
            portholes[porthole.uniqueIdentifier] = porthole
            _generation += 1
        }
    }

    func remove(_ porthole: ObjCPorthole) {
        mutex.sync {
            _ = portholes.removeValue(forKey: porthole.uniqueIdentifier)
            _generation += 1
        }
    }

    subscript(_ key: String) -> ObjCPorthole? {
        return mutex.sync {
            return portholes[key]
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

    @objc func encodeAsChild(with encoder: iTermGraphEncoder, key: String) {
        mutex.sync {
            _ = encoder.encodeChild(withKey: key,
                                    identifier: "",
                                    generation: _generation) { subencoder in
                self.encodeGraph(with: subencoder)
            }
        }
    }
}

extension PortholeRegistry: iTermGraphCodable {
    @objc func encodeGraph(with encoder: iTermGraphEncoder) -> Bool {
        let portholeDicts: [String: [String: AnyObject]] = portholes.mapValues { porthole in
            porthole.dictionaryValue
        }
        encoder.encodePropertyList(portholeDicts,
                                   withKey: portholesKey)
        encoder.encodePropertyList(pending,
                                   withKey: pendingKey)
        encoder.encode(NSNumber(value: _generation),
                       forKey: generationKey)
        return true
    }
}
