//
//  TextViewPorthole.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/22/22.
//

import AppKit
import Foundation

@objc
class TextViewPorthole: NSObject {
    let config: PortholeConfig
    let textView: ExclusiveSelectionView
    let textStorage = NSTextStorage()
    private let layoutManager = TextPortholeLayoutManager()
    private let textContainer: TopRightAvoidingTextContainer
    private weak var _mark: PortholeMarkReading? = nil
    private let uuid: String
    // I have no idea why this is necessary but the NSView is invisible unless it's in a container
    // view. ILY, AppKit.
    private let containerView: PortholeContainerView
    weak var delegate: PortholeDelegate?
    var savedLines: [ScreenCharArray] = []
    let outerMargin = PortholeContainerView.margin
    let innerMargin = CGFloat(4)
    var renderer: TextViewPortholeRenderer {
        didSet {
            textStorage.setAttributedString(renderer.render(visualAttributes: savedVisualAttributes))
        }
    }
    var changeRendererCallback: ((String, TextViewPorthole) -> ())? = nil

    struct VisualAttributes: Equatable {
        let textColor: NSColor
        let backgroundColor: NSColor
        let font: NSFont

        init(colorMap: iTermColorMapReading, font: NSFont) {
            textColor = colorMap.color(forKey: kColorMapForeground) ?? NSColor.textColor
            backgroundColor = colorMap.color(forKey: kColorMapBackground) ?? NSColor.textBackgroundColor
            self.font = font
        }
    }
    private(set) var savedVisualAttributes: VisualAttributes

    init(_ config: PortholeConfig,
         renderer: TextViewPortholeRenderer,
         uuid: String? = nil) {
        let popup = SanePopUpButton()
        popup.controlSize = .mini
        popup.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .mini))
        popup.autoenablesItems = true
        popup.menu?.addItem(withTitle: JSONPortholeRenderer.identifier, action: #selector(changeRenderer(_:)), keyEquivalent: "")
        popup.menu?.addItem(withTitle: MarkdownPortholeRenderer.identifier, action: #selector(changeRenderer(_:)), keyEquivalent: "")
        popup.sizeToFit()
        popup.selectItem(withTitle: renderer.identifier)

        containerView = PortholeContainerView()
        self.uuid = uuid ?? UUID().uuidString
        self.config = config
        savedVisualAttributes = VisualAttributes(colorMap: config.colorMap, font: config.font)

        let textViewFrame = CGRect(x: 0, y: 0, width: 800, height: 200)
        textStorage.addLayoutManager(layoutManager)
        textContainer = TopRightAvoidingTextContainer(containerSize: textViewFrame.size,
                                                      cutOutSize: NSSize(width: 18 + popup.frame.width + 4,
                                                                         height: max(popup.frame.height + 2, 18)))
        layoutManager.addTextContainer(textContainer)
        textView = ExclusiveSelectionView(frame: textViewFrame, textContainer: textContainer)
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        if let selectionTextColor = config.colorMap.color(forKey: kColorMapSelectedText),
           let selectionBackgroundColor = config.colorMap.color(forKey: kColorMapSelection) {
            textView.selectedTextAttributes = [.foregroundColor: selectionTextColor,
                                               .backgroundColor: selectionBackgroundColor]
        }
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = true

        containerView.wantsLayer = true
        textView.removeFromSuperview()
        containerView.addSubview(textView, positioned: .below, relativeTo: containerView.closeButton)
        containerView.color = savedVisualAttributes.textColor
        containerView.backgroundColor = savedVisualAttributes.backgroundColor

        self.renderer = renderer
        textStorage.setAttributedString(renderer.render(visualAttributes: savedVisualAttributes))

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
        containerView.accessory = popup
        _ = containerView.layoutSubviews()

        for item in popup.menu?.items ?? [] {
            item.target = self
        }
    }

    func fittingSize(for width: CGFloat) -> NSSize {
        return NSSize(width: width, height: self.desiredHeight(forWidth: width))
    }

    @objc func changeRenderer(_ sender: Any?) {
        changeRendererCallback?((sender as! NSMenuItem).title, self)
    }
}

extension TextViewPorthole: Porthole {
    func desiredHeight(forWidth width: CGFloat) -> CGFloat {
        // Set the width so the height calculation will be based on it. The height here is = arbitrary.
        let textViewHeight = textContainer.withFakeSize(NSSize(width: width, height: .infinity)) { () -> CGFloat in 
            // forces layout
            _ = layoutManager.glyphRange(for: textContainer)
            let rect = layoutManager.usedRect(for: textContainer)
            return rect.height
        }

        // The height is now frozen.
        textView.frame = NSRect(x: 0, y: 0, width: width, height: textViewHeight)
        return textViewHeight + (outerMargin + innerMargin) * 2
    }

    static var type: PortholeType {
        .text
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

    static let uuidDictionaryKey = "uuid"
    static let baseDirectoryKey = "baseDirectory"
    static let textDictionaryKey = "text"
    static let rendererDictionaryKey = "renderer"
    static let mimeTypeKey = "mimeType"

    var dictionaryValue: [String: AnyObject] {
        let dir: NSString?
        if let baseDirectory = config.baseDirectory {
            dir = baseDirectory.path as NSString
        } else {
            dir = nil
        }
        return wrap(dictionary: [Self.uuidDictionaryKey: uuid as NSString,
                                 Self.textDictionaryKey: config.text as NSString,
                                 Self.rendererDictionaryKey: renderer.identifier as NSString,
                                 Self.baseDirectoryKey: dir,
                                 Self.mimeTypeKey: config.mimeType as NSString?].compactMapValues { $0 })
    }

    static func config(fromDictionary dict: [String: AnyObject],
                       colorMap: iTermColorMapReading,
                       font: NSFont) -> (config: PortholeConfig,
                                         rendererName: String,
                                         uuid: String)?  {
        guard let uuid = dict[Self.uuidDictionaryKey],
              let text = dict[Self.textDictionaryKey],
              let renderer = dict[Self.rendererDictionaryKey] else {
            return nil
        }
        let baseDirectory: URL?
        if let url = dict[Self.baseDirectoryKey], let urlString = url as? String {
            baseDirectory = URL(string: urlString)
        } else {
            baseDirectory = nil
        }
        guard let uuid = uuid as? String,
              let text = text as? String,
              let renderer = renderer as? String else {
            return nil
        }
        let mimeType: String?
        if let unsafeMimeType = dict[Self.mimeTypeKey], let justMimeType = unsafeMimeType as? String {
            mimeType = justMimeType
        } else {
            mimeType = nil
        }
        return (config: PortholeConfig(text: text,
                                       colorMap: colorMap,
                                       baseDirectory: baseDirectory,
                                       font: font,
                                       mimeType: mimeType),
                rendererName: renderer,
                uuid: uuid)
    }
    func removeSelection() {
        textView.removeSelection()
    }
}

extension TextViewPorthole: NSTextViewDelegate {
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
        let visualAttributes = VisualAttributes(colorMap: config.colorMap,
                                                font: config.font)
        guard visualAttributes != savedVisualAttributes else {
            return
        }
        savedVisualAttributes = visualAttributes
        containerView.color = visualAttributes.textColor
        containerView.backgroundColor = visualAttributes.backgroundColor
        textView.textStorage?.setAttributedString(renderer.render(visualAttributes: visualAttributes))
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

    func withFakeSize<T>(_ fakeSize: NSSize, closure: () throws -> T) rethrows -> T {
        let saved = size
        size = fakeSize
        defer {
            size = saved
        }
        return try closure()
    }
}

protocol TextViewPortholeRenderer {
    var identifier: String { get }
    func render(visualAttributes: TextViewPorthole.VisualAttributes) -> NSAttributedString
}

class TextPortholeLayoutManager: NSLayoutManager {
    override func layoutManagerOwnsFirstResponder(in window: NSWindow) -> Bool {
        true
    }
}
