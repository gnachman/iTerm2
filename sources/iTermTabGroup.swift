import Cocoa

@objc class iTermTabGroup: NSObject, NSCoding {
    @objc let identifier: String
    @objc var name: String
    @objc var color: NSColor
    @objc var memberTabIDs: [Int]
    @objc var isCollapsed: Bool
    var stashedTabViewItems: [NSTabViewItem] = []

    private enum CodingKey {
        static let identifier = "identifier"
        static let name = "name"
        static let color = "color"
        static let memberTabIDs = "memberTabIDs"
        static let isCollapsed = "isCollapsed"
    }

    @objc(groupWithName:color:)
    static func group(name: String, color: NSColor) -> iTermTabGroup {
        return iTermTabGroup(name: name, color: color)
    }

    @objc init(name: String, color: NSColor) {
        self.identifier = UUID().uuidString
        self.name = name
        self.color = color
        self.memberTabIDs = []
        self.isCollapsed = false
    }

    required init?(coder: NSCoder) {
        guard let identifier = coder.decodeObject(forKey: CodingKey.identifier) as? String,
              let name = coder.decodeObject(forKey: CodingKey.name) as? String,
              let colorData = coder.decodeObject(forKey: CodingKey.color) as? Data,
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData),
              let rawIDs = coder.decodeObject(forKey: CodingKey.memberTabIDs) as? [NSNumber] else {
            return nil
        }
        self.identifier = identifier
        self.name = name
        self.color = color
        self.memberTabIDs = rawIDs.map { $0.intValue }
        self.isCollapsed = coder.decodeBool(forKey: CodingKey.isCollapsed)
    }

    func encode(with coder: NSCoder) {
        coder.encode(identifier, forKey: CodingKey.identifier)
        coder.encode(name, forKey: CodingKey.name)
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            coder.encode(colorData, forKey: CodingKey.color)
        }
        coder.encode(memberTabIDs.map { NSNumber(value: $0) } as NSArray, forKey: CodingKey.memberTabIDs)
        coder.encode(isCollapsed, forKey: CodingKey.isCollapsed)
    }

    @objc func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            CodingKey.identifier: identifier,
            CodingKey.name: name,
            CodingKey.memberTabIDs: memberTabIDs.map { NSNumber(value: $0) },
            CodingKey.isCollapsed: isCollapsed
        ]
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            dict[CodingKey.color] = colorData
        }
        return dict
    }

    @objc init?(dictionary: [String: Any]) {
        guard let identifier = dictionary[CodingKey.identifier] as? String,
              let name = dictionary[CodingKey.name] as? String,
              let colorData = dictionary[CodingKey.color] as? Data,
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData),
              let rawIDs = dictionary[CodingKey.memberTabIDs] as? [NSNumber] else {
            return nil
        }
        self.identifier = identifier
        self.name = name
        self.color = color
        self.memberTabIDs = rawIDs.map { $0.intValue }
        self.isCollapsed = (dictionary[CodingKey.isCollapsed] as? Bool) ?? false
    }
}
