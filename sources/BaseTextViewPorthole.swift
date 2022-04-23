//
//  BaseTextViewPorthole.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/22/22.
//

import AppKit
import Foundation

@objc
class BaseTextViewPorthole: NSObject {
    let config: PortholeConfig
    let textView: ExclusiveSelectionView
    let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer: NSTextContainer
    private weak var _mark: PortholeMarkReading? = nil
    private let uuid: String
    // I have no idea why this is necessary but the NSView is invisible unless it's in a container
    // view. ILY, AppKit.
    private let containerView: BasePortholeContainerView
    weak var delegate: PortholeDelegate?
    var savedLines: [ScreenCharArray] = []
    let outerMargin = BasePortholeContainerView.margin
    let innerMargin = CGFloat(4)

    struct SavedColors: Equatable {
        let textColor: NSColor
        let backgroundColor: NSColor

        init(colorMap: iTermColorMapReading) {
            textColor = colorMap.color(forKey: kColorMapForeground) ?? NSColor.textColor
            backgroundColor = colorMap.color(forKey: kColorMapBackground) ?? NSColor.textBackgroundColor
        }
    }
    private(set) var savedColors: SavedColors

    init(_ config: PortholeConfig,
         uuid: String? = nil) {
        containerView = BasePortholeContainerView()
        self.uuid = uuid ?? UUID().uuidString
        self.config = config
        savedColors = SavedColors(colorMap: config.colorMap)

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
}

extension BaseTextViewPorthole: Porthole {
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

    static let uuidDictionaryKey = "uuid"
    static let baseDirectoryKey = "baseDirectory"

    var dictionaryValue: [String: AnyObject] {
        let dir: NSString?
        if let baseDirectory = config.baseDirectory {
            dir = baseDirectory.path as NSString
        } else {
            dir = nil
        }
        return wrap(dictionary: [Self.uuidDictionaryKey: uuid as NSString,
                                 Self.baseDirectoryKey: dir].compactMapValues { $0 })
    }

    func removeSelection() {
        textView.removeSelection()
    }
}

extension BaseTextViewPorthole: NSTextViewDelegate {
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
        let colors = SavedColors(colorMap: config.colorMap)
        guard colors != savedColors else {
            return
        }
        savedColors = colors
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



