//
//  SpecialExceptionsWindowController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/13/23.
//

import Foundation
import BetterFontPicker
import UniformTypeIdentifiers

protocol SpecialExceptionEntryEditorWindowControllerDelegate: AnyObject {
    func editorRangeIsValid(range: ClosedRange<Int>) -> Bool
}

@objc
class SpecialExceptionEntryEditorWindowController: NSWindowController, NSTextFieldDelegate, AffordanceDelegate {
    @IBOutlet weak var start: NSTextField!
    @IBOutlet weak var end: NSTextField!
    @IBOutlet weak var ok: NSButton!
    @IBOutlet weak var compositeView: BetterFontPicker.FontPickerCompositeView!
    @IBOutlet weak var preview: NSTextView!
    @IBOutlet weak var hasDestination: NSButton!
    @IBOutlet weak var destination: NSTextField!

    private var affordance: Affordance { compositeView.affordance }
    weak var delegate: SpecialExceptionEntryEditorWindowControllerDelegate?
    var disallowedIndexes = IndexSet()

    var entry: FontTable.Entry? {
        didSet {
            copyEntryToControls()
            updateEnabled()
            updatePreview()
        }
    }

    override func awakeFromNib() {
        compositeView.mode = .fixedPitch
        compositeView.removeSizePicker()
        compositeView.removeMemberPicker()
        compositeView.removeOptionsButton()
        compositeView.affordance.delegate = self
        preview.textColor = .textColor
        if let entry {
            copyEntryToControls()
            affordance.familyName = entry.fontName
        }
        updateEnabled()
    }

    private func destinationIsValid(range: ClosedRange<Int>) -> Bool {
        guard hasDestination.state == .on else {
            return true
        }
        guard let d = parseUnicode(Substring(destination.stringValue)) else {
            return false
        }
        guard d >= 0 && d + range.count < FontTable.unicodeLimit else {
            return false
        }
        return true
    }

    private var shouldEnableOK: Bool {
        guard let delegate else {
            return false
        }
        guard let range = validDestinationRange else {
            return false
        }
        if affordance.familyName == nil {
            return false
        }
        return delegate.editorRangeIsValid(range: range)
    }

    private func updateEnabled() {
        ok.isEnabled = shouldEnableOK
        destination.isEnabled = hasDestination.state == .on
    }

    private func updatePreview() {
        preview.textColor = .textColor
        switch checkedRange {
        case .ascii:
            preview.string = "Start must be at least U+80. ASCII doesn’t support special exceptions."
        case .incomplete:
            preview.string = ""
        case .inverted:
            preview.string = "Invalid range."
        case .limitTooLarge:
            preview.string = "End is higher than U+110000, the maximum Unicode code point."
        case .taken:
            preview.string = "Range includes an already-assigned code point."
        case .invalidDestination:
            preview.string = "Invalid destination"
        case let .valid(source: sourceRange, destination: _):
            guard let familyName = affordance.familyName,
                  let font = NSFont(name: familyName, size: NSFont.systemFontSize) else {
                preview.string = "No font selected."
                return
            }
            if (!destinationIsValid(range: sourceRange)) {
                preview.string = "Invalid destination."
                return
            }
            let disallowed = IndexSet([9, 10, 13, 0xad, 0x200e, 0x200f, 0x200b, 0x200c])
            let combined = NSMutableAttributedString()
            for i in sourceRange {
                if combined.length >= 1024 * 10 {
                    combined.append(NSAttributedString(string: " [truncated]",
                                                       attributes: [
                                                        .foregroundColor: NSColor.textColor,
                                                        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]))
                    break
                }
                guard let scalar = UnicodeScalar(i) else {
                    continue
                }
                if disallowed.contains(i) {
                    continue
                }
                combined.append(NSAttributedString(string: String(Character(scalar)),
                                                   attributes: [.foregroundColor: NSColor.textColor,
                                                                .font: font]))
            }
            preview.textStorage?.setAttributedString(combined)
        }
    }

    func copyEntryToControls() {
        guard let entry else {
            return
        }
        start.stringValue = Self.formatUnicode(entry.start)
        end.stringValue = Self.formatUnicode(entry.start + entry.count - 1)
        compositeView.affordance.familyName = entry.fontName
        if let d = entry.destination {
            hasDestination.state = .on
            destination.stringValue = Self.formatUnicode(d)
        } else {
            hasDestination.state = .off
            destination.stringValue = ""
        }
    }

    @discardableResult
    private func copyControlsToEntryIfValid() -> Bool {
        guard let familyName = affordance.familyName, let range = validSourceRange else {
            return false
        }
        entry = FontTable.Entry(start: range.lowerBound,
                                count: range.count,
                                destination: hasDestination.state == .on ? parseUnicode(Substring(destination.stringValue)) : nil,
                                fontName: familyName)
        return true
    }

    static func formatUnicode(_ value: Int) -> String {
        return "U+" + String(format: "%x", value)
    }

    private struct CodePointPrefix {
        var string: String
        var radix: Int
    }
    private let prefixes = [CodePointPrefix(string: "U+", radix: 16),
                            CodePointPrefix(string: "u+", radix: 16),
                            CodePointPrefix(string: "0x", radix: 16) ]

    private func parseUnicode(_ value: Substring, radix: Int? = nil) -> Int? {
        if radix == nil {
            for entry in prefixes {
                if value.hasPrefix(entry.string) {
                    return parseUnicode(value.dropFirst(entry.string.count), radix: entry.radix)
                }
            }
        }
        return Int(value, radix: radix ?? 10)
    }

    private enum CheckedRange {
        case incomplete
        case ascii
        case inverted
        case limitTooLarge
        case taken
        case invalidDestination
        case valid(source: ClosedRange<Int>, destination: ClosedRange<Int>)
    }

    // Start of range we remap *to*
    private var beginning: Int? {
        if hasDestination.state == .on {
            return parseUnicode(Substring(destination.stringValue))
        }
        return parseUnicode(Substring(start.stringValue))
    }

    private var count: Int? {
        if let start = parseUnicode(Substring(start.stringValue)),
           let end = parseUnicode(Substring(end.stringValue)) {
            return end - start + 1
        }
        return nil
    }

    private var checkedRange: CheckedRange {
        if hasDestination.state == .on &&
            parseUnicode(Substring(destination.stringValue)) == nil {
            return .invalidDestination
        }
        guard let sourceStart = parseUnicode(Substring(start.stringValue)),
              let destStart = beginning,
              let count else {
            return .incomplete
        }
        let destEnd = destStart + count - 1
        guard destStart >= 128 else {
            return .ascii
        }
        guard count > 0 else {
            return .inverted
        }
        guard destStart + count <= FontTable.unicodeLimit else {
            return .limitTooLarge
        }
        if disallowedIndexes.intersects(integersIn: destStart...destEnd) {
            return .taken
        }
        return .valid(source: sourceStart...(sourceStart + count - 1),
                      destination: destStart...destEnd)
    }

    private var validSourceRange: ClosedRange<Int>? {
        switch checkedRange {
        case .valid(source: let value, _):
            return value
        default:
            return nil
        }
    }

    private var validDestinationRange: ClosedRange<Int>? {
        switch checkedRange {
        case .valid(_, destination: let value):
            return value
        default:
            return nil
        }
    }

    // MARK: - Actions

    @IBAction
    func haveDestinationDidChange(_ sender: AnyObject) {
        updateEnabled()
        updatePreview()
    }

    @IBAction
    func ok(_ sender: AnyObject) {
        copyControlsToEntryIfValid()
        window?.sheetParent?.endSheet(window!, returnCode: .OK)
    }

    @IBAction
    func cancel(_ sender: AnyObject) {
        window?.sheetParent?.endSheet(window!, returnCode: .cancel)
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else {
            return
        }
        if let parsed = parseUnicode(Substring(textField.stringValue)) {
            textField.stringValue = Self.formatUnicode(parsed)
        } else if let entry {
            let originalValue = textField.tag == 0 ? entry.start : entry.start + entry.count - 1
            textField.stringValue = Self.formatUnicode(originalValue)
        } else {
            textField.stringValue = ""
        }
        if copyControlsToEntryIfValid() {
            copyEntryToControls()
        }
        updatePreview()
    }

    func controlTextDidChange(_ obj: Notification) {
        updateEnabled()
    }

    // MARK: - AffordanceDelegate

    func affordance(_ affordance: Affordance, didSelectFontFamily fontFamily: String) {
        updatePreview()
        compositeView.affordance(affordance, didSelectFontFamily: fontFamily)
        updateEnabled()
    }
}

class SpecialExceptionsWindow: NSPanel {
    override var acceptsFirstResponder: Bool {
        true
    }
    override var canBecomeKey: Bool {
        true
    }
    override var canBecomeMain: Bool {
        true
    }
}

@objc
final class SpecialExceptionsWindowController: NSWindowController {
    @IBOutlet weak var tableView: CompetentTableView!
    @IBOutlet weak var addRemove: NSSegmentedControl!
    @IBOutlet weak var editorWindowController: SpecialExceptionEntryEditorWindowController!
    @IBOutlet weak var installNerdBundleButton: NSButton!
    @IBOutlet weak var progressIndicator: NSProgressIndicator!

    private(set) var config: FontTable.Config!
    private(set) var crud: CRUDTableViewController<SpecialExceptionsWindowController>!
    @objc var configString: String { config.stringValue }
    private var rowBeingEdited = -1

    @objc
    static func create(configString: String?) -> SpecialExceptionsWindowController {
        let instance = SpecialExceptionsWindowController(windowNibName: "SpecialExceptionsWindowController")
        instance.config = FontTable.Config(string: configString ?? "") ?? FontTable.Config(entries: [])
        return instance
    }

    override func windowDidLoad() {
        crud = CRUDTableViewController(tableView: tableView,
                                       addRemove: addRemove,
                                       schema: CRUDSchema(columns: [CRUDColumn(type: .string),
                                                                    CRUDColumn(type: .string),
                                                                    CRUDColumn(type: .string)],
                                                          dataProvider: self))
        crud.delegate = self
        updateEnabled()
    }

    private var nerdBundleInstalled: Bool {
        return config == NerdFontInstaller.config
    }

    private func updateEnabled() {
        installNerdBundleButton.isEnabled = !nerdBundleInstalled
    }

    // MARK: - Actions

    @IBAction func ok(_ sender: AnyObject) {
        window?.sheetParent?.endSheet(window!, returnCode: .OK)
    }

    @IBAction func cancel(_ sender: AnyObject) {
        window?.sheetParent?.endSheet(window!, returnCode: .cancel)
    }

    private let ext = "itse"

    @IBAction func share(_ sender: AnyObject) {
        let panel = NSSavePanel()

        if #available(macOS 11, *) {
            if let uttype = UTType.init(filenameExtension: ext) {
                panel.allowedContentTypes = [uttype]
            }
        } else {
            panel.allowedFileTypes = [ext]
        }
        panel.title = "Export Special Exceptions"
        panel.canCreateDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.showsHiddenFiles = true
        panel.allowsOtherFileTypes = false

        if panel.runModal() == .OK, let url = panel.url {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(config) {
                try? data.write(to: url)
            }
        }
    }

    @IBAction func importExceptions(_ sender: AnyObject) {
        let panel = NSOpenPanel()

        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = [ ext ]
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            let content = try String(contentsOf: url)
            importString(content)
            updateEnabled()
        } catch {
            showError(error.localizedDescription)
            return
        }
    }

    private func importString(_ content: String) {
        guard let newConfig = FontTable.Config(string: content) else {
            showError("This file is not well formed. Is it from a newer version of iTerm2?")
            return
        }
        guard newConfig.version <= FontTable.Config.latestKnownVersion else {
            showError("This file is from a newer version of iTerm2 and cannot be loaded.")
            return
        }
        let missing = missingFonts(newConfig)
        guard missing.isEmpty else {
            showError("You must install the following fonts to use the exceptions in this file:\n\n\(missing.joined(separator: "\n"))")
            return
        }
        crud.undoable {
            config = newConfig
        }
        crud.reload()
    }

    private func showError(_ message: String) {
        iTermWarning.show(withTitle: message,
                          actions: ["OK"],
                          accessory: nil,
                          identifier: "SpecialExceptionsImportError",
                          silenceable: .kiTermWarningTypePersistent,
                          heading: "Problem Importing Special Exceptions",
                          window: window)
    }

    private func missingFonts(_ config: FontTable.Config) -> [String] {
        return config.entries.compactMap { entry in
            if NSFont(name: entry.fontName, size: 12) == nil {
                return entry.fontName
            }
            return nil
        }
    }

    @IBAction func installNerdFontBundle(_ sender: Any) {
        if !config.entries.isEmpty {
            let selection = iTermWarning.show(withTitle: "This will replace existing special exceptions. Continue?",
                                              actions: ["OK", "Cancel"],
                                              accessory: nil,
                                              identifier: "SpecialExceptionsInstallNerdBundleConfirmation",
                                              silenceable: .kiTermWarningTypePersistent,
                                              heading: "Confirm",
                                              window: window)
            if selection == .kiTermWarningSelection1 {
                return
            }
        }
        installNerdBundleButton.isHidden = true
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        NerdFontInstaller.start(window: window) { [weak self] error in
            defer {
                self?.updateEnabled()
            }
            if let error {
                switch error {
                case .saveDownloadFailed, .downloadFailed, .fontInstallationFailed,
                        .missingRequiredFonts, .unzipFailed:
                    self?.showError(error.localizedDescription)

                case .userDeniedPermission:
                    break
                }
            } else {
                self?.importString(NerdFontInstaller.configString)
            }
            self?.installNerdBundleButton.isHidden = false
            self?.progressIndicator.stopAnimation(nil)
            self?.progressIndicator.isHidden = true
        }
    }
}

extension SpecialExceptionsWindowController: SpecialExceptionEntryEditorWindowControllerDelegate {
    func editorRangeIsValid(range: ClosedRange<Int>) -> Bool {
        var entries = config.entries
        if rowBeingEdited >= 0 {
            entries.remove(at: rowBeingEdited)
        }
        return !entries.anySatisfies {
            $0.closedRange.overlaps(range)
        }
    }
}

extension FontTable.Entry {
    var closedRange: ClosedRange<Int> {
        let beginning = destination ?? start
        return beginning...(beginning + count - 1)
    }
}

extension SpecialExceptionsWindowController: CRUDTableViewControllerDelegate {
    var crudState: FontTable.Config {
        get {
            return config
        }
        set {
            config = newValue
        }
    }

    func crudTableSelectionDidChange(_ sender: CRUDTableViewController<SpecialExceptionsWindowController>, selectedRows: IndexSet) {
    }

    func crudTextFieldDidChange(_ sender: CRUDTableViewController<SpecialExceptionsWindowController>,
                                row: Int,
                                column: Int,
                                newValue: String) {
        defer {
            updateEnabled()
        }
        switch column {
        case 0:
            if let i = Int(newValue) {
                config.entries[row].start = i
            }
        case 1:
            let start = config.entries[row].start
            if let i = Int(newValue), i > start {
                config.entries[row].count = start - i
            }
        case 2:
            config.entries[row].fontName = newValue
        default:
            fatalError()
        }
    }

    private var assignedIndexes: IndexSet {
        var result = IndexSet()
        for entry in config.entries {
            result.insert(integersIn: entry.closedRange)
        }
        return result
    }

    func crudDoubleClick(_ sender: CRUDTableViewController<SpecialExceptionsWindowController>, row: Int, column: Int) {
        rowBeingEdited = row
        editorWindowController.delegate = self
        var disallowedIndexes = assignedIndexes
        if row == -1 {
            editorWindowController.disallowedIndexes = disallowedIndexes
            editorWindowController.entry = FontTable.Entry(start: 0, count: 0, fontName: "")
        } else {
            disallowedIndexes.remove(integersIn: config.entries[row].closedRange)
            editorWindowController.disallowedIndexes = disallowedIndexes
            editorWindowController.entry = config.entries[row]
        }

        window?.beginSheet(editorWindowController.window!) { [weak self] status in
            if status == .OK {
                self?.acceptEdit(row: row)
            }
        }
    }

    private func acceptEdit(row: Int) {
        rowBeingEdited = -1
        config.entries[row] = editorWindowController!.entry!
        crud.reload(row: row)
        updateEnabled()
    }
}

extension SpecialExceptionsWindowController: CRUDDataProvider {
    private struct Row: CRUDRow {
        var entry: FontTable.Entry

        func format(column: Int) -> CRUDFormatted {
            switch column {
            case 0:
                return .string(SpecialExceptionEntryEditorWindowController.formatUnicode(entry.closedRange.lowerBound))
            case 1:
                return .string(SpecialExceptionEntryEditorWindowController.formatUnicode(entry.closedRange.upperBound))
            case 2:
                return .string(entry.fontName)
            default:
                fatalError()
            }
        }
    }

    var count: Int {
        config.entries.count
    }

    subscript(index: Int) -> CRUDRow {
        get {
            let entry = config.entries[index]
            return Row(entry: entry)
        }
    }

    func delete(_ indexes: IndexSet) {
        config.entries.remove(at: indexes)
        updateEnabled()
    }

    func makeNew(completion: @escaping (Int) -> ()) {
        editorWindowController.entry = nil
        editorWindowController.delegate = self
        editorWindowController.disallowedIndexes = assignedIndexes
        editorWindowController.copyEntryToControls()
        window?.beginSheet(editorWindowController.window!) { [weak self] status in
            if status == .OK {
                self?.acceptAdd(completion: completion)
            }
        }
    }

    private func acceptAdd(completion: (Int) -> ()) {
        let entry = editorWindowController!.entry!
        let row = config.entries.insertionIndex { $0.start < entry.start }
        crud.undoable {
            config.entries.insert(entry, at: row)
        }
        completion(row)
        updateEnabled()
    }
}

extension RandomAccessCollection {
    func insertionIndex(by comparison: (Element) -> Bool) -> Index {
        var currentSlice = self[...]

        while !currentSlice.isEmpty {
            let middle = currentSlice.index(currentSlice.startIndex,
                                            offsetBy: currentSlice.count / 2)
            if comparison(currentSlice[middle]) {
                currentSlice = currentSlice[index(after: middle)...]
            } else {
                currentSlice = currentSlice[..<middle]
            }
        }
        return currentSlice.startIndex
    }
}

