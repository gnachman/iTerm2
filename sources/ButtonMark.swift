//
//  ButtonMark.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/28/23.
//

import Foundation

@objc(iTermButtonMarkReading)
protocol ButtonMarkReading: AnyObject, iTermMarkProtocol {
    @objc var copyBlockID: String? { get }
    @objc var channelUID: String? { get }
    @objc var buttonID: Int { get }
    @objc var code: Int32 { get }
    @objc var icon: String? { get }
    @objc var valid: Bool { get }
}

enum ButtonType {
    static func fromDictionary(_ dict: [AnyHashable : Any]) -> ButtonType? {
        switch dict["type"] as? String {
        case "copy":
            if let block = dict["block ID"], let blockID = block as? String {
                return .copy(block: blockID)
            }
        case "custom":
            if let code = dict["code"] as? Int32,
                let icon = dict["icon"] as? String,
            let valid = dict["valid"] as? Bool {
                return .custom(code: code, icon: icon, valid: valid)
            }
        default:
            break
        }
        return nil
    }

    var dictionary: NSDictionary {
        switch self {
        case .copy(block: let blockID):
            return ["type": "copy",
                    "block ID": blockID]
        case .channel(uid: let uid):
            return ["type": "channel",
                    "uid": uid]
        case let .custom(code: code, icon: icon, valid: valid):
            return ["type": "custom",
                    "code": code,
                    "icon": icon,
                    "valid": valid]
        }
    }
    case copy(block: String)
    case channel(uid: String)
    case custom(code: Int32, icon: String, valid: Bool)
}

@objc(iTermButtonMark)
class ButtonMark: iTermMark, ButtonMarkReading {
    var buttonType: ButtonType?
    var buttonID: Int

    var copyBlockID: String? {
        get {
            switch buttonType {
            case .copy(block: let blockID):
                return blockID
            case .none, .channel, .custom:
                break
            }
            return nil
        }
        set {
            if let newValue {
                buttonType = .copy(block: newValue)
            } else {
                buttonType = nil
            }
        }
    }

    @objc
    var channelUID: String? {
        get {
            switch buttonType {
            case .copy, .none, .custom:
                nil
            case .channel(uid: let uid):
                uid
            }
        }
        set {
            if let newValue {
                buttonType = .channel(uid: newValue)
            } else {
                buttonType = nil
            }
        }
    }

    @objc
    var code: Int32 {
        switch buttonType {
        case .copy, .channel, .none: 0
        case .custom(code: let code, icon: _, valid: _): code
        }
    }


    @objc
    var valid: Bool {
        switch buttonType {
        case .copy, .channel, .none: true
        case .custom(code: _, icon: _, valid: let valid): valid
        }
    }

    @objc
    var icon: String? {
        switch buttonType {
        case .copy, .channel, .none: nil
        case .custom(code: _, icon: let icon, valid: _): icon
        }
    }

    @objc static func generateID() -> Int {
        defer {
            nextId += 1
        }
        return nextId
    }
    private static var nextId = 0

    @objc
    override init() {
        buttonID = Self.generateID()
        super.init()
    }

    required init!(dictionary dict: [AnyHashable : Any]!) {
        buttonType = .fromDictionary(dict)
        buttonID = dict["id"] as? Int ?? Self.generateID()
        super.init(dictionary: dict)
    }

    override func dictionaryValue() -> [AnyHashable : Any]! {
        var dict = super.dictionaryValue()!
        if let local = buttonType?.dictionary as? [AnyHashable: Any] {
            dict.merge(local) { _, _ in
                it_fatalError()
            }
        }
        dict["id"] = buttonID
        return dict
    }

    @objc
    func makeCustom(code: Int32, icon: String) {
        buttonType = .custom(code: code, icon: icon, valid: true)
    }

    @objc
    func invalidate() {
        guard code != 0, let icon else {
            return
        }
        buttonType = .custom(code: code, icon: icon, valid: false)
    }
}

@objc(iTermTerminalButtonPlace)
class TerminalButtonPlace: NSObject {
    @objc var id: Int { mark.buttonID }
    @objc var mark: ButtonMarkReading
    @objc var coord: VT100GridAbsCoord

    @objc
    init(mark: ButtonMarkReading, coord: VT100GridAbsCoord) {
        self.mark = mark
        self.coord = coord
    }
}
