//
//  MarkdownPorthole.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/13/22.
//

import Foundation
import SwiftyMarkdown

@objc(iTermPortholeFactory)
class PortholeFactory: NSObject {
    @objc
    static func markdownPorthole(markdown: String,
                                 textColor: NSColor) -> ObjCPorthole {
        return MarkdownPorthole(markdown, textColor: textColor)
    }

    @objc
    static func porthole(_ dictionary: [String: AnyObject],
                         textColor: NSColor) -> ObjCPorthole? {
        guard let (type, info) = PortholeType.unwrap(dictionary: dictionary) else {
            return nil
        }
        switch type {
        case .markdown:
            return MarkdownPorthole.from(info, textColor: textColor)
        }
    }
}

class MarkdownPorthole {
    private let textView: MetalDisablingTextView
    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer: NSTextContainer
    private let scrollview = NSScrollView()
    private weak var _mark: PortholeMark? = nil
    private let uuid: String
    private let markdown: String
    private let embedInScrollView = true

    init(_ markdown: String, textColor: NSColor, uuid: String? = nil) {
        self.uuid = uuid ?? UUID().uuidString
        self.markdown = markdown

        let md = SwiftyMarkdown(string: markdown)
        md.h1.color = textColor
        md.h2.color = textColor
        md.h3.color = textColor
        md.h4.color = textColor
        md.h5.color = textColor
        md.h6.color = textColor
        md.body.color = textColor
        md.blockquotes.color = textColor
        md.link.color = textColor
        md.bold.color = textColor
        md.italic.color = textColor
        md.code.color = textColor

        let attributedString = md.attributedString()

        if embedInScrollView {
            scrollview.hasVerticalScroller = true
            scrollview.hasHorizontalScroller = false
            scrollview.borderType = .lineBorder
        }

        let textViewFrame = CGRect(x: 0, y: 0, width: 800, height: 200)
        textStorage.addLayoutManager(layoutManager)
        textContainer = NSTextContainer(containerSize: textViewFrame.size)
        layoutManager.addTextContainer(textContainer)
        textView = MetalDisablingTextView(frame: textViewFrame, textContainer: textContainer)
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textStorage.setAttributedString(attributedString)
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = true

        if embedInScrollView {
            scrollview.frame = NSRect(x: 0, y: 0, width: 800, height: 200)
            scrollview.documentView = textView
            scrollview.drawsBackground = false
            scrollview.verticalScrollElasticity = .none
        }
    }

    private func height(for width: CGFloat) -> CGFloat {
        return textStorage.boundingRect(with: NSSize(width: width, height: 0),
                                        options: [.usesLineFragmentOrigin]).height
    }

    func sizeToFit(width: CGFloat) {
        if embedInScrollView {
            let contentWidth = NSScrollView.contentSize(forFrameSize: NSSize(width: width, height: 100),
                                                        horizontalScrollerClass: nil,
                                                        verticalScrollerClass: NSScroller.self,
                                                        borderType: scrollview.borderType,
                                                        controlSize: .regular,
                                                        scrollerStyle: .legacy).width
            let contentSize = NSSize(width: contentWidth, height: self.height(for: contentWidth))
            let scrollViewSize = NSScrollView.frameSize(forContentSize: contentSize,
                                                        horizontalScrollerClass: nil,
                                                        verticalScrollerClass: NSScroller.self,
                                                        borderType: scrollview.borderType,
                                                        controlSize: .regular,
                                                        scrollerStyle: .legacy)
            scrollview.frame = NSRect(x: 0, y: 0, width: scrollViewSize.width, height: scrollViewSize.height)
            textView.frame = CGRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height)
        } else {
            let contentSize = NSSize(width: width, height: self.height(for: width))
            textView.frame = CGRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height)
        }
    }

    private static let uuidDictionaryKey = "uuid"
    private static let markdownDictionaryKey = "markdown"

    static func from(_ dictionary: [String: AnyObject],
                     textColor: NSColor) -> MarkdownPorthole? {
        guard let uuid = dictionary[uuidDictionaryKey] as? String,
                let markdown = dictionary[markdownDictionaryKey] as? String else {
            return nil
        }
        return MarkdownPorthole(markdown, textColor: textColor, uuid: uuid)
    }
}

extension MarkdownPorthole: Porthole {
    static var type: PortholeType {
        .markdown
    }
    var uniqueIdentifier: String {
        return uuid
    }
    var view: NSView {
        return embedInScrollView ? scrollview : textView
    }
    var mark: PortholeMark? {
        get {
            return _mark
        }
        set {
            _mark = newValue
        }
    }
    var dictionaryValue: [String: AnyObject] {
        return wrap(dictionary: [Self.uuidDictionaryKey: uuid as NSString,
                                 Self.markdownDictionaryKey: markdown as NSString])
    }

    func set(size: NSSize) {
        var frame = view.frame
        frame.size = size
        view.frame = frame
    }
}

@objc class MetalDisablingTextView: NSTextView {

}
