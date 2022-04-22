//
//  MarkdownPorthole.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/13/22.
//

import AppKit
import Foundation
import SwiftyMarkdown

@available(macOS 12, *)
class MarkdownPorthole: NSObject {
    private let textView: ExclusiveSelectionView
    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer: NSTextContainer
    private let scrollview = NSScrollView()
    private weak var _mark: PortholeMarkReading? = nil
    private let uuid: String
    private let markdown: String
    // I have no idea why this is necessary but the NSView is invisible unless it's in a container
    // view. ILY, AppKit.
    private let containerView = MarkdownContainerView()
    private let baseDirectory: URL?
    private let colorMap: iTermColorMap
    weak var delegate: PortholeDelegate?
    var savedLines: [ScreenCharArray] = []
    let outerMargin = MarkdownContainerView.margin
    let innerMargin = CGFloat(4)

    private struct SavedColors: Equatable {
        let textColor: NSColor
        let backgroundColor: NSColor

        init(colorMap: iTermColorMap) {
            textColor = colorMap.color(forKey: kColorMapForeground) ?? NSColor.textColor
            backgroundColor = colorMap.color(forKey: kColorMapBackground) ?? NSColor.textBackgroundColor
        }
    }
    private var savedColors: SavedColors
    private static func attributedString(markdown: String, colors: SavedColors) -> NSAttributedString {
        let md = SwiftyMarkdown(string: markdown)
        if let fixedPitchFontName = NSFont.userFixedPitchFont(ofSize: 12)?.fontName {
            md.code.fontName = fixedPitchFontName
        }
        let textColor = colors.textColor
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
        return md.attributedString()
    }

    init?(_ markdown: String,
          colorMap: iTermColorMap,
          baseDirectory: URL?,
          uuid: String? = nil) {
        self.uuid = uuid ?? UUID().uuidString
        self.markdown = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseDirectory = baseDirectory
        self.colorMap = colorMap
        savedColors = SavedColors(colorMap: colorMap)
        let attributedString = Self.attributedString(markdown: self.markdown, colors: savedColors)

        var options = AttributedString.MarkdownParsingOptions()
        options.allowsExtendedAttributes = true
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible

        let textViewFrame = CGRect(x: 0, y: 0, width: 800, height: 200)
        textStorage.addLayoutManager(layoutManager)
        textContainer = TopRightAvoidingTextContainer(containerSize: textViewFrame.size,
                                                      cutOutSize: NSSize(width: 18, height: 18))
        layoutManager.addTextContainer(textContainer)
        textView = ExclusiveSelectionView(frame: textViewFrame, textContainer: textContainer)
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        if let selectionTextColor = colorMap.color(forKey: kColorMapSelectedText),
           let selectionBackgroundColor = colorMap.color(forKey: kColorMapSelection) {
            textView.selectedTextAttributes = [.foregroundColor: selectionTextColor,
                                               .backgroundColor: selectionBackgroundColor]
        }
        textStorage.setAttributedString(attributedString)
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = true

        containerView.wantsLayer = true
        textView.removeFromSuperview()
        containerView.addSubview(textView, positioned: .below, relativeTo: containerView.closeButton)
        containerView.color = savedColors.textColor
        containerView.backgroundColor = savedColors.backgroundColor

        super.init()

        textView.delegate = self
        textView.didAcquireSelection = { [weak self] in
            guard let self = self else {
                return
            }
            self.delegate?.portholeDidAcquireSelection(self)
        }
        containerView.closeCallback = { [weak self] in
            if let self = self {
                self.delegate?.portholeRemove(self)
            }
        }
    }

    func fittingSize(for width: CGFloat) -> NSSize {
        return NSSize(width: width, height: self.desiredHeight(forWidth: width))
    }

    private static let uuidDictionaryKey = "uuid"
    private static let markdownDictionaryKey = "markdown"
    private static let baseDirectoryKey = "baseDirectory"

    static func from(_ dictionary: [String: AnyObject],
                     colorMap: iTermColorMap) -> MarkdownPorthole? {
        guard let uuid = dictionary[uuidDictionaryKey] as? String,
                let markdown = dictionary[markdownDictionaryKey] as? String else {
            return nil
        }
        return MarkdownPorthole(markdown,
                                colorMap: colorMap,
                                baseDirectory: dictionary[baseDirectoryKey] as? URL,
                                uuid: uuid)
    }
}

@available(macOS 12, *)
extension MarkdownPorthole: Porthole {
    func desiredHeight(forWidth width: CGFloat) -> CGFloat {
        let textViewHeight = textStorage.boundingRect(
            with: NSSize(width: width, height: 0),
            options: [.usesLineFragmentOrigin]).height
        // The height is now frozen.
        textView.frame = NSRect(x: 0, y: 0, width: width, height: textViewHeight)
        return textViewHeight + (outerMargin + innerMargin) * 2
    }

    static var type: PortholeType {
        .markdown
    }
    var uniqueIdentifier: String {
        return uuid
    }
    var view: NSView {
        return containerView
    }
    var mark: PortholeMarkReading? {
        get {
            return _mark
        }
        set {
            _mark = newValue
        }
    }
    var dictionaryValue: [String: AnyObject] {
        let dir: NSString?
        if let baseDirectory = baseDirectory {
            dir = baseDirectory.path as NSString
        } else {
            dir = nil
        }
        return wrap(dictionary: [Self.uuidDictionaryKey: uuid as NSString,
                                 Self.markdownDictionaryKey: markdown as NSString,
                                 Self.baseDirectoryKey: dir].compactMapValues { $0 })
    }

    func removeSelection() {
        textView.removeSelection()
    }
}

@available(macOS 12, *)
extension MarkdownPorthole: NSTextViewDelegate {
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = NSAttributedString.linkToURL(link) else {
            return false
        }
        if url.scheme == "file" {
            if iTermWarning.show(withTitle: "Open file at \(url.path)?",
                                 actions: ["OK", "Cancel"],
                                 accessory: nil,
                                 identifier: "NoSyncOpenFileFromMarkdownLink",
                                 silenceable: .kiTermWarningTypePermanentlySilenceable,
                                 heading: "Confirm",
                                 window: textView.window) == .kiTermWarningSelection0 {
                NSWorkspace.shared.open(url)
            }
        } else {
            if iTermWarning.show(withTitle: "Open URL \(url.absoluteString)?",
                                 actions: ["OK", "Cancel"],
                                 accessory: nil,
                                 identifier: "NoSyncOpenURLFromMarkdownLink",
                                 silenceable: .kiTermWarningTypePermanentlySilenceable,
                                 heading: "Confirm",
                                 window: textView.window) == .kiTermWarningSelection0 {
                NSWorkspace.shared.open(url)
            }
        }
        return true
    }

    func updateColors() {
        let colors = SavedColors(colorMap: colorMap)
        guard colors != savedColors else {
            return
        }
        savedColors = colors
        textView.textStorage?.setAttributedString(Self.attributedString(markdown: markdown,
                                                                        colors: savedColors))
        containerView.color = colors.textColor
        containerView.backgroundColor = colors.backgroundColor
    }
}

extension NSAttributedString {
    static func linkToURL(_ link: Any?) -> URL? {
        guard let value = link else {
            return nil
        }
        if let url = value as? URL {
            return url
        }
        if let string = value as? String {
            return URL(string: string)
        }
        return nil
    }
    func rewritingRelativeFileLinks(baseDirectory: URL) -> NSAttributedString {
        let result = mutableCopy() as! NSMutableAttributedString
        enumerateAttributes(in: NSRange(location: 0, length: length)) { attributes, range, stopPtr in
            guard let link = Self.linkToURL(attributes[.link]) else {
                return
            }
            guard link.scheme == nil || link.scheme == "file" else {
                return
            }
            if link.path.hasPrefix("/") {
                return
            }
            var replacement = attributes
            replacement[.link] = URL(fileURLWithPath: link.path, relativeTo: baseDirectory)
            result.replaceAttributes(in: range, withAttributes: replacement)
        }
        return result
    }
}

class TopRightAvoidingTextContainer: NSTextContainer {
    private let cutOutSize: NSSize
    private var cutOutRect: CGRect {
        return CGRect(x: size.width - cutOutSize.width,
                      y: 0,
                      width: cutOutSize.width,
                      height: cutOutSize.height)
    }
    init(containerSize: NSSize,
         cutOutSize: NSSize) {
        self.cutOutSize = cutOutSize
        super.init(size: containerSize)
    }

    required init(coder: NSCoder) {
        fatalError("Not supported")
    }

    override func lineFragmentRect(forProposedRect proposedRect: CGRect,
                                   at characterIndex: Int,
                                   writingDirection baseWritingDirection: NSWritingDirection,
                                   remaining remainingRect: UnsafeMutablePointer<CGRect>?) -> CGRect {
        let rect = super.lineFragmentRect(forProposedRect: proposedRect,
                                          at: characterIndex,
                                          writingDirection: baseWritingDirection,
                                          remaining: remainingRect) as CGRect
        let intersection = rect.intersection(cutOutRect)
        if !intersection.isNull {
            return CGRect(x: rect.minX,
                          y: rect.minY,
                          width: intersection.minX - rect.minX,
                          height: rect.height)
        }
        return rect
    }

}

