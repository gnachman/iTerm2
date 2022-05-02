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
    let textView: ExclusiveSelectionTextView
    let textStorage = NSTextStorage()
    private let layoutManager = TextPortholeLayoutManager()
    private let textContainer: TopRightAvoidingTextContainer
    private let popup = SanePopUpButton()
    private let uuid: String
    private let containerView: PortholeContainerView
    weak var delegate: PortholeDelegate?
    var savedLines: [ScreenCharArray] = []
    let outerMargin = PortholeContainerView.margin
    let innerMargin = CGFloat(4)
    var hasSelection: Bool {
        return textView.selectedRange().length > 0
    }
    var renderer: TextViewPortholeRenderer {
        didSet {
            textStorage.setAttributedString(renderer.render(visualAttributes: savedVisualAttributes))
            updateLanguage()
        }
    }
    var changeLanguageCallback: ((String, TextViewPorthole) -> ())? = nil

    struct VisualAttributes: Equatable {
        static func == (lhs: TextViewPorthole.VisualAttributes, rhs: TextViewPorthole.VisualAttributes) -> Bool {
            return (lhs.colorMap === rhs.colorMap &&
                    lhs.colorMapGeneration == rhs.colorMapGeneration &&
                    lhs.font == rhs.font &&
                    lhs.textColor == rhs.textColor &&
                    lhs.backgroundColor == rhs.backgroundColor)
        }

        let textColor: NSColor
        let backgroundColor: NSColor
        let font: NSFont
        let colorMap: iTermColorMapReading
        let colorMapGeneration: Int

        init(colorMap: iTermColorMapReading, font: NSFont) {
            textColor = colorMap.color(forKey: kColorMapForeground) ?? NSColor.textColor
            backgroundColor = colorMap.color(forKey: kColorMapBackground) ?? NSColor.textBackgroundColor
            self.font = font
            self.colorMap = colorMap
            colorMapGeneration = colorMap.generation
        }
    }
    private(set) var savedVisualAttributes: VisualAttributes

    static private func add(languages: Set<String>, to menu: NSMenu?) {
        guard let menu = menu else {
            return
        }

        let sortedLanguages = languages.sorted{$0.localizedCompare($1) == .orderedAscending}
        for language in sortedLanguages {
            menu.addItem(withTitle: language, action: #selector(changeLanguage(_:)), keyEquivalent: "")
        }
    }

    init(_ config: PortholeConfig,
         renderer: TextViewPortholeRenderer,
         uuid: String? = nil,
         savedLines: [ScreenCharArray]? = nil,
         wideMode: Bool = false) {
        if let savedLines = savedLines {
            self.savedLines = savedLines
        }
        popup.controlSize = .mini
        popup.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .mini))
        popup.autoenablesItems = true

        if !renderer.languages.isEmpty {
            Self.add(languages: renderer.languages, to: popup.menu)
            var secondaryLanguages = TextViewPortholeRenderer.allLanguages
            secondaryLanguages.subtract(renderer.languages)
            if !secondaryLanguages.isEmpty {
                popup.menu?.addItem(NSMenuItem.separator())
                Self.add(languages: secondaryLanguages, to: popup.menu)
            }
        } else {
            Self.add(languages: TextViewPortholeRenderer.allLanguages, to: popup.menu)
        }
        popup.sizeToFit()

        containerView = PortholeContainerView()
        containerView.frame = NSRect(x: 0, y: 0, width: 800, height: 200)
        containerView.accessory = popup
        _ = containerView.layoutSubviews()

        self.uuid = uuid ?? UUID().uuidString
        self.config = config
        savedVisualAttributes = VisualAttributes(colorMap: config.colorMap, font: config.font)

        let textViewFrame = CGRect(x: 0, y: 0, width: 800, height: 200)
        textStorage.addLayoutManager(layoutManager)
        textContainer = TopRightAvoidingTextContainer(
            containerSize: textViewFrame.size,
            cutOutSize: NSSize(width: containerView.frame.width - containerView.wideButton.frame.minX,
                               height: max(popup.frame.height + 2, 18)))
        layoutManager.addTextContainer(textContainer)
        textView = ExclusiveSelectionTextView(frame: textViewFrame, textContainer: textContainer)
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

        if wideMode {
            containerView.makeWide()
        }
        super.init()

        updateLanguage()
        updateAppearance()
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
        containerView.wideCallback = { [weak self] in
            self?.didToggleWide()
        }
        _ = containerView.layoutSubviews()

        for item in popup.menu?.items ?? [] {
            item.target = self
        }
    }

    func fittingSize(for width: CGFloat) -> NSSize {
        return NSSize(width: width, height: self.desiredHeight(forWidth: width))
    }

    @objc func changeLanguage(_ sender: Any?) {
        let language = (sender as! NSMenuItem).title
        renderer.language = FileExtensionDB.instance?.languageToShortName[language] ?? language
        textStorage.setAttributedString(renderer.render(visualAttributes: savedVisualAttributes))
        changeLanguageCallback?(language, self)
        PortholeRegistry.instance.incrementGeneration()
    }

    private func updateLanguage() {
        if let language = renderer.language,
            let title = FileExtensionDB.instance?.shortNameToLanguage[language] {
            popup.selectItem(withTitle: title)
        }
    }

    private func didToggleWide() {
        delegate?.portholeResize(self)
        PortholeRegistry.instance.incrementGeneration()
    }
}

extension TextViewPorthole: Porthole {
    func set(frame: NSRect) {
        containerView.frame = frame

        if let scrollView = containerView.scrollView {
            textView.isHorizontallyResizable = true
            textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                      height: scrollView.contentSize.height)
            textContainer.widthTracksTextView = false
            textContainer.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                 height: CGFloat.greatestFiniteMagnitude)
            textView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: scrollView.contentSize.height)
        } else {
            textView.isHorizontallyResizable = false
            textContainer.containerSize = frame.size
            textContainer.widthTracksTextView = true
        }
        containerView.frame = frame
    }

    func desiredHeight(forWidth width: CGFloat) -> CGFloat {
        if let scrollView = containerView.scrollView {
            textContainer.widthTracksTextView = false
            textContainer.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                 height: scrollView.contentSize.height)
            _ = layoutManager.glyphRange(for: textContainer)
            let textViewHeight = layoutManager.usedRect(for: textContainer).height
            return containerView.scrollViewOverhead + textViewHeight + (outerMargin + innerMargin) * 2
        }

        // Set the width so the height calculation will be based on it. The height here is = arbitrary.
        let textViewHeight = textContainer.withFakeSize(NSSize(width: width, height: .infinity)) { () -> CGFloat in 
            // forces layout
            // This is obviously indefensible but I just can't get it to work with a single call to glyphRange.
            // 😘 AppKit
            _ = layoutManager.glyphRange(for: textContainer)
            DLog("After first call to glyphRange rect would be \(layoutManager.usedRect(for: textContainer))")
            _ = layoutManager.glyphRange(for: textContainer)
            let rect = layoutManager.usedRect(for: textContainer)
            DLog("After second call to glyphRange rect is \(rect)")
            return rect.height
        }

        // The height is now frozen.
        textView.frame = NSRect(x: 0, y: 0, width: width, height: textViewHeight)
        return containerView.scrollViewOverhead + textViewHeight + (outerMargin + innerMargin) * 2
    }

    func find(_ query: String, mode: iTermFindMode) -> [ExternalSearchResult] {
        removeHighlights()
        let ranges = (textView.string as NSString).ranges(substring: query, mode: mode)
        textView.temporarilyHighlight(ranges)
        return ranges.map {
            SearchResult($0, owner: self)
        }
    }

    func removeHighlights() {
        textView.removeTemporaryHighlights()
    }

    func select(searchResult: ExternalSearchResult,
                multiple: Bool,
                returningRectRelativeTo view: NSView,
                scroll: Bool) -> NSRect? {
        guard let result = searchResult as? SearchResult else {
            return nil
        }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: result.range, actualCharacterRange: nil)
        if glyphRange.location == NSNotFound && glyphRange.length == 0 {
            return nil
        }
        if multiple {
            let ranges = textView.selectedRanges.map {
                $0.rangeValue
            }.filter {
                $0.intersection(result.range) == nil
            } + [result.range]
            textView.selectedRanges = ranges.map { NSValue(range: $0) }
        } else {
            textView.setSelectedRange(result.range)
        }
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        if scroll {
            var paddedGlyphRect = glyphRect
            let hpad = CGFloat(40)
            let minX = max(0, glyphRect.origin.x - hpad)
            let maxX = min(textView.bounds.width, glyphRect.maxX + hpad)
            paddedGlyphRect.origin.x = minX
            paddedGlyphRect.size.width = maxX - minX
            textView.scrollToVisible(paddedGlyphRect)
        }
        return textView.convert(glyphRect, to: view)
    }

    func snippet(for result: ExternalSearchResult,
                 matchAttributes: [NSAttributedString.Key: Any],
                 regularAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString? {
        guard let result = result as? SearchResult else {
            return nil
        }

        var lowerBound = result.range.location
        var upperBound = result.range.location + result.range.length
        lowerBound = max(0, lowerBound - 20)
        let prefixLength = result.range.location - lowerBound
        upperBound = min(textStorage.length, upperBound + 256)
        let expandedRange = NSRange(lowerBound..<upperBound)

        // Grab the raw text of the snippet.
        let multiLineSubstring = textStorage.attributedSubstring(from: expandedRange).mutableCopy() as! NSMutableAttributedString

        // Change style to regular and then highlight the matched range.
        multiLineSubstring.editAttributes { update in
            multiLineSubstring.enumerateAttributes(
                in: NSRange(location: 0, length: multiLineSubstring.length)) { _, range, _ in
                    update(range, regularAttributes)
                }
        }
        multiLineSubstring.editAttributes { update in
            let substringRelativeRange = NSRange(location: prefixLength, length: result.range.length)
            multiLineSubstring.enumerateAttributes(in: substringRelativeRange) { attributes, subrange, stop in
                update(subrange, matchAttributes)
            }
        }

        // Remove newlines.
        let substring = NSMutableAttributedString()
        multiLineSubstring.mutableString.enumerateSubstrings(
            in: NSRange(location: 0, length: (multiLineSubstring.string as NSString).length),
            options: [.byLines]) { _maybeLine, lineRange, _enclosingRange, _stop in
                substring.append(multiLineSubstring.attributedSubstring(from: lineRange))
            }

        return substring
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
        return PortholeRegistry.instance.mark(for: uniqueIdentifier)
    }

    static let uuidDictionaryKey = "uuid"
    static let baseDirectoryKey = "baseDirectory"
    static let textDictionaryKey = "text"
    static let typeKey = "type"
    static let filenameKey = "filename"
    static let savedLinesKey = "savedLines"
    static let languageKey = "language"
    static let languagesKey = "languages"
    static let wideKey = "wide"

    var dictionaryValue: [String: AnyObject] {
        let dir: NSString?
        if let baseDirectory = config.baseDirectory {
            dir = baseDirectory.path as NSString
        } else {
            dir = nil
        }
        let encodedSavedLines = self.savedLines.map { $0.dictionaryValue as NSDictionary }
        let dict: [String: Any?] = [Self.uuidDictionaryKey: uuid as NSString,
                                    Self.textDictionaryKey: config.text as NSString,
                                    Self.baseDirectoryKey: dir,
                                    Self.typeKey: config.type as NSString?,
                                    Self.filenameKey: config.filename as NSString?,
                                    Self.savedLinesKey: encodedSavedLines,
                                    Self.languageKey: renderer.language,
                                    Self.languagesKey: renderer.languageCandidateShortNames,
                                    Self.wideKey: containerView.wideMode]
        return wrap(dictionary: dict.compactMapValues { $0 })
    }

    static func config(fromDictionary dict: [String: AnyObject],
                       colorMap: iTermColorMapReading,
                       font: NSFont) -> (config: PortholeConfig,
                                         uuid: String,
                                         savedLines: [ScreenCharArray],
                                         language: String?,
                                         languages: [String]?,
                                         wideMode: Bool)?  {
        guard let uuid = dict[Self.uuidDictionaryKey],
              let text = dict[Self.textDictionaryKey],
              let savedLines = dict[self.savedLinesKey] as? [[AnyHashable: Any]] else {
            return nil
        }
        let baseDirectory: URL?
        if let url = dict[Self.baseDirectoryKey], let urlString = url as? String {
            baseDirectory = URL(string: urlString)
        } else {
            baseDirectory = nil
        }
        guard let uuid = uuid as? String,
              let text = text as? String else {
            return nil
        }
        let type: String? = dict.value(withKey: Self.typeKey)
        let filename: String? = dict.value(withKey: Self.filenameKey)
        return (config: PortholeConfig(text: text,
                                       colorMap: colorMap,
                                       baseDirectory: baseDirectory,
                                       font: font,
                                       type: type,
                                       filename: filename),
                uuid: uuid,
                savedLines: savedLines.compactMap { ScreenCharArray(dictionary: $0) },
                language: dict[Self.languageKey] as? String,
                languages: dict[Self.languagesKey] as? [String],
                wideMode: dict[Self.wideKey] as? Bool ?? false)

    }
    func removeSelection() {
        textView.removeSelection()
    }

    func copy(as mode: PortholeCopyMode) {
        let ranges = textView.selectedRanges.map { $0.rangeValue }
        let attributedStrings = ranges.map { textView.attributedString().attributedSubstring(from: $0) }
        let pboard = NSPasteboard.general
        pboard.clearContents()
        pboard.declareTypes([.multipleTextSelection, .rtf], owner: nil)
        let strings = attributedStrings.map { $0.string }
        let linesPerGroup = strings.map { string in
            return string.components(separatedBy: "\n").count
        }
        pboard.setPropertyList(linesPerGroup,
                               forType: .multipleTextSelection)

        switch mode {
        case .plainText:
            let string = strings.joined(separator: "\n") as NSPasteboardWriting
            pboard.writeObjects([string])

        case .attributedString:
            let combined = attributedStrings.joined(separator: NSAttributedString(string: "\n",
                                                                                  attributes: [:]))
            pboard.writeObjects([combined])

        case .controlSequences:
            let combined = attributedStrings.joined(separator: NSAttributedString(string: "\n",
                                                                                  attributes: [:]))
            let string: String = combined.asStringWithControlSequences
            pboard.writeObjects([string as NSPasteboardWriting])
        }
    }
}


extension Dictionary {
    func value<T>(withKey key: Key) -> T? {
        guard let unsafe = self[key] else {
            return nil
        }
        return unsafe as? T
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
        updateAppearance()
        updateLanguage()
    }

    private func updateAppearance() {
        containerView.appearance = savedVisualAttributes.backgroundColor.isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
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
        let savedContainerSize = containerSize
        let saved = size
        size = fakeSize
        containerSize = fakeSize
        defer {
            size = saved
            containerSize = savedContainerSize
        }
        return try closure()
    }
}

class TextPortholeLayoutManager: NSLayoutManager {
    override func layoutManagerOwnsFirstResponder(in window: NSWindow) -> Bool {
        true
    }
}

extension NSString {
    func ranges(substring: String, mode: iTermFindMode) -> [NSRange] {
        let regex: Bool
        let caseSensitive: Bool
        switch mode {
        case .caseInsensitiveRegex:
            regex = true
            caseSensitive = false

        case .caseInsensitiveSubstring:
            regex = false
            caseSensitive = false

        case .caseSensitiveRegex:
            regex = true
            caseSensitive = true

        case .caseSensitiveSubstring:
            regex = false
            caseSensitive = true

        case .smartCaseSensitivity:
            regex = false
            caseSensitive = substring.rangeOfCharacter(from: CharacterSet.uppercaseLetters) != nil

        @unknown default:
            fatalError()
        }

        let compiledRegex: NSRegularExpression?
        if regex {
            var options: NSRegularExpression.Options = [.anchorsMatchLines]
            if !caseSensitive {
                options.insert(.caseInsensitive)
            }
            compiledRegex = try? NSRegularExpression(pattern: substring, options: options)
        } else {
            compiledRegex = nil
        }

        var start = 0
        let length = self.length
        var result = [NSRange]()
        while true {
            let currentRange = { () -> NSRange in
                if regex {
                    guard let compiledRegex = compiledRegex else {
                        return NSRange(location: NSNotFound, length: 0)
                    }
                    return compiledRegex.rangeOfFirstMatch(in: self as String,
                                                           options: [],
                                                           range: NSRange(start..<length))
                } else {
                    return range(of: substring,
                                 options: caseSensitive ? [] : [.caseInsensitive],
                                 range: NSRange(start..<length))
                }
            }()
            if currentRange.location == NSNotFound {
                return result
            }
            result.append(currentRange)
            start = currentRange.upperBound
        }
    }
}

extension TextViewPorthole: ExternalSearchResultOwner {
    class SearchResult: ExternalSearchResult {
        let range: NSRange
        init(_ range: NSRange, owner: TextViewPorthole) {
            self.range = range

            super.init(owner)
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? SearchResult else {
                return false
            }
            return owner === other.owner && range == other.range
        }
    }

    func select(_ result: ExternalSearchResult) {
        let searchResult = result as! SearchResult
        textView.setSelectedRange(searchResult.range)
    }

    var absLine: Int64 {
        delegate?.portholeAbsLine(self) ?? -1
    }

    var numLines: Int32 {
        delegate?.portholeHeight(self) ?? 1
    }
    func searchResultIsVisible(_ result: ExternalSearchResult) -> Bool {
        let searchResult = result as! SearchResult
        let glyphRange = textContainer.layoutManager!.glyphRange(
            forCharacterRange: searchResult.range, actualCharacterRange: nil)
        let rect = textContainer.layoutManager!.boundingRect(
            forGlyphRange: glyphRange, in: textContainer)
        // If it's offscreen because the porthole is truncated then you get back a zero rect.
        return rect != NSRect.zero
    }
}
