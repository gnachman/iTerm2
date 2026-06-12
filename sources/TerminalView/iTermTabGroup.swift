import Cocoa

@objc class iTermTabGroup: NSObject {
    @objc let identifier: String
    @objc var name: String
    @objc var color: NSColor
    @objc var memberTabIDs: [Int]
    @objc var isCollapsed: Bool
    var stashedTabViewItems: [NSTabViewItem] = []
    @objc let headerTabViewItem: NSTabViewItem

    private enum CodingKey {
        static let identifier = "identifier"
        static let name = "name"
        static let color = "color"
        static let memberTabIndices = "memberTabIndices"
        static let isCollapsed = "isCollapsed"
    }

    @objc(groupWithName:color:)
    static func group(name: String, color: NSColor) -> iTermTabGroup {
        return iTermTabGroup(name: name, color: color)
    }

    private static func makeHeaderItem(label: String) -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = label
        item.view = NSView(frame: .zero)
        return item
    }

    @objc init(name: String, color: NSColor) {
        self.identifier = UUID().uuidString
        self.name = name
        self.color = color
        self.memberTabIDs = []
        self.isCollapsed = false
        let item = iTermTabGroup.makeHeaderItem(label: name)
        self.headerTabViewItem = item
        super.init()
        item.identifier = self
    }

    @objc func toDictionary(allTabs: [PTYTab]) -> [String: Any] {
        let indices = memberTabIDs.compactMap { id -> NSNumber? in
            guard let index = allTabs.firstIndex(where: { Int($0.uniqueId) == id }) else { return nil }
            return NSNumber(value: index)
        }
        var dict: [String: Any] = [
            CodingKey.identifier: identifier,
            CodingKey.name: name,
            CodingKey.memberTabIndices: indices,
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
              let rawIndices = dictionary[CodingKey.memberTabIndices] as? [NSNumber] else {
            return nil
        }
        self.identifier = identifier
        self.name = name
        self.color = color
        self.memberTabIDs = rawIndices.map { $0.intValue }
        self.isCollapsed = (dictionary[CodingKey.isCollapsed] as? Bool) ?? false
        let item = iTermTabGroup.makeHeaderItem(label: name)
        self.headerTabViewItem = item
        super.init()
        item.identifier = self
    }
}
