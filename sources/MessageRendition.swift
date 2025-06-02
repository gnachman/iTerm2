//
//  MessageRendition.swift
//  iTerm2
//
//  Created by George Nachman on 2/25/25.
//

struct MessageRendition {
    struct SubpartContainer {
        enum Kind {
            case regular
            case codeAttachment
            case statusUpdate
        }
        var kind: Kind
        var attributedString: NSAttributedString
    }
    enum Flavor {
        case regular(Regular)
        case command(Command)
        case multipart([SubpartContainer])
    }
    struct Regular {
        struct Button {
            var title: String
            var destructive: Bool
            var color: NSColor {
                destructive ? .red : .textColor
            }
            var identifier: String
        }
        var attributedString: NSAttributedString
        var buttons: [Button]
        var enableButtons: Bool
    }
    struct Command {
        var command: String
        var url: URL
    }

    var isUser: Bool
    var messageUniqueID: UUID
    var flavor: Flavor
    var timestamp: String
    var isEditable: Bool
    var linkColor: NSColor
}

