//
//  SSHConfigurationWindowController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/9/22.
//

import Foundation

fileprivate struct Config {
    var sshIntegration: Bool = true
    var environmentVariablesToCopy: [String] = []
    var filesToCopy: [(String, String)] = []

    private enum Keys: String {
        case sshIntegration
        case environmentVariablesToCopy
        case filesToCopy
    }

    var dictionaryValue: [String: AnyObject] {
        let filesArrays = filesToCopy.map { [$0.0, $0.1] }
        let dict: [String : AnyObject] = [
            Keys.sshIntegration.rawValue: NSNumber(value: sshIntegration) as AnyObject,
            Keys.environmentVariablesToCopy.rawValue: environmentVariablesToCopy as AnyObject,
            Keys.filesToCopy.rawValue: filesArrays as AnyObject
        ]
        return dict.mapValues { $0 as AnyObject }
    }

    init(dictionary: [String: AnyObject]) {
        sshIntegration = dictionary[Keys.sshIntegration.rawValue] as? Bool ?? true
        environmentVariablesToCopy = dictionary[Keys.environmentVariablesToCopy.rawValue] as? [String] ?? []
        filesToCopy = (dictionary[Keys.filesToCopy.rawValue] as? [[String]] ?? []).map { ($0[0], $0[1]) }
    }

    init(sshIntegration: Bool,
         environmentVariablesToCopy: [String],
         filesToCopy: [(String, String)]) {
        self.sshIntegration = sshIntegration
        self.environmentVariablesToCopy = environmentVariablesToCopy
        self.filesToCopy = filesToCopy
    }

    init() {
        self.init(dictionary: [:])
    }
}


@objc(iTermSSHConfiguration)
class SSHConfiguration: NSObject {
    private let config: Config
    @objc var sshIntegration: Bool { config.sshIntegration }
    @objc var environmentVariablesToCopy: [String] { config.environmentVariablesToCopy }
    @objc var filesToCopy: [iTermTuple<NSString, NSString>] {
        config.filesToCopy.map { tuple -> iTermTuple<NSString, NSString> in
            return iTermTuple(object: tuple.0 as NSString,
                              andObject: tuple.1 as NSString)
        }
    }
    @objc override init() {
        config = Config(sshIntegration: true, environmentVariablesToCopy: [], filesToCopy: [])
    }

    @objc init(dictionary: NSDictionary?) {
        config = Config(dictionary: (dictionary as? [String: AnyObject]) ?? [:])
    }
    @objc var dictionaryValue: [String: AnyObject] {
        return config.dictionaryValue
    }
}

@objc(iTermSSHConfigurationWindowController)
class SSHConfigurationWindowController: NSWindowController {
    @IBOutlet var sshIntegrationButton: NSButton!
    @IBOutlet var environmentVariablesToCopy: NSTokenField!
    @IBOutlet var filesToCopyTable: BackspaceDeletingTableView!
    @IBOutlet var sourceColumn: NSTableColumn!
    @IBOutlet var destinationColumn: NSTableColumn!
    @IBOutlet var segmentedControl: NSSegmentedControl!
    var ok = false

    private var config = Config()
    @objc var dictionaryValue: [String: AnyObject] {
        return config.dictionaryValue
    }

    @objc func load(_ dictionary: [String: AnyObject]) {
        _ = window
        config = Config(dictionary: dictionary)
        sshIntegrationButton.state = config.sshIntegration ? .on : .off
        environmentVariablesToCopy.stringValue = config.environmentVariablesToCopy.joined(separator: "\t")
        filesToCopyTable.reloadData()
        updateEnabled()
    }

    override func awakeFromNib() {
        environmentVariablesToCopy.tokenizingCharacterSet = CharacterSet(charactersIn: "\t")
        filesToCopyTable.backspace = { [weak self] in
            self?.removeFile()
        }
    }

    private func updateEnabled() {
        let enabled = config.sshIntegration
        for control in [environmentVariablesToCopy, filesToCopyTable] {
            control?.isEnabled = enabled
        }
        segmentedControl.setEnabled(!filesToCopyTable.selectedRowIndexes.isEmpty, forSegment: 1)
    }

    private func addFile() {
        let (sources, destination) = chooseSourceFiles()
        for source in sources {
            add(source, destination: destination)
        }
    }

    private func add(_ source: String, destination: String) {
        let home = NSHomeDirectory()
        let nonEmptyDestination: String
        if source.hasPrefix(home) {
            let url = URL(fileURLWithPath: "~" + source.dropFirst(home.count))
            if destination.isEmpty {
                nonEmptyDestination = url.deletingLastPathComponent().path
            } else {
                nonEmptyDestination = destination
            }
        } else {
            if destination.isEmpty {
                nonEmptyDestination = "~"
            } else {
                nonEmptyDestination = destination
            }
        }
        let row = config.filesToCopy.count
        config.filesToCopy.append((source, nonEmptyDestination))
        filesToCopyTable.insertRows(at: IndexSet(integer: row))
    }

    private func removeFile() {
        config.filesToCopy.remove(at: filesToCopyTable.selectedRowIndexes)
        filesToCopyTable.removeRows(at: filesToCopyTable.selectedRowIndexes, withAnimation: [])
    }

    private func chooseSourceFiles() -> ([String], String) {
        let destinationView = SSHCopyDestinationView()
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.accessoryView = destinationView
        panel.isAccessoryViewDisclosed = true
        guard panel.runModal() == .OK else {
            return ([], "")
        }
        let paths = panel.urls.map { url -> String in
            let home = NSHomeDirectory()
            if url.path.hasPrefix(home) {
                return "~" + url.path.dropFirst(home.count)
            }
            return url.path
        }
        return (paths, destinationView.stringValue)
    }

    // MARK: - Actions

    @IBAction func ok(_ sender: Any) {
        guard let window = window else {
            return
        }
        window.sheetParent?.endSheet(window, returnCode: .OK)
    }

    @IBAction func cancel(_ sender: Any) {
        guard let window = window else {
            return
        }
        window.sheetParent?.endSheet(window, returnCode: .cancel)
    }

    @IBAction func sshIntegrationEnabledDidChange(_ sender: Any) {
        config.sshIntegration = sshIntegrationButton.state == .on
        updateEnabled()
    }

    @IBAction func segmentedControl(_ sender: Any) {
        if segmentedControl.selectedSegment == 0 {
            addFile()
        } else {
            removeFile()
        }
    }
}

extension SSHConfigurationWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return config.filesToCopy.count
    }
}

extension SSHConfigurationWindowController: NSTableViewDelegate {
    func tableViewSelectionDidChange(_ notification: Notification) {
        updateEnabled()
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard let tableColumn = tableColumn else {
            return nil
        }

        let string: String
        if tableColumn == sourceColumn {
            string = config.filesToCopy[row].0
        } else {
            string = config.filesToCopy[row].1
        }

        let identifier = tableColumn.identifier
        let view: NSTableCellView
        view = NSTableCellView()
        let textField = NSTextField.it_textFieldForTableView(withIdentifier: identifier.rawValue + "TextField")
        textField.usesSingleLineMode = false
        textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textField.lineBreakMode = .byTruncatingHead
        textField.stringValue = string
        textField.toolTip = textField.stringValue
        textField.maximumNumberOfLines = 1
        textField.delegate = self
        textField.identifier = identifier
        view.textField = textField
        view.addSubview(textField)
        textField.autoresizingMask = [.width, .height]
        view.textField?.isEditable = true
        view.textField?.stringValue = string

        return view;
    }
}

extension SSHConfigurationWindowController: NSTextDelegate, NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSTokenField === environmentVariablesToCopy {
            config.environmentVariablesToCopy = environmentVariablesToCopy.stringValue.components(separatedBy: environmentVariablesToCopy.tokenizingCharacterSet)
        } else if let textField = obj.object as? NSTextField {
            if textField.identifier == sourceColumn.identifier {
                config.filesToCopy[filesToCopyTable.selectedRow].0 = textField.stringValue
            } else if textField.identifier == destinationColumn.identifier {
                config.filesToCopy[filesToCopyTable.selectedRow].1 = textField.stringValue
            }
        }
    }
}

fileprivate class SSHCopyDestinationView: NSView {
    private let textField: NSTextField
    private let label: NSTextField
    var stringValue: String {
        return textField.stringValue
    }

    init() {
        let fieldWidth = 350.0
        let margin = 10.0
        let vmargin = 8.0

        textField = NSTextField()
        textField.stringValue = "~"
        label = NSTextField(labelWithString: "Destination folder on remote host:")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.sizeToFit()

        super.init(frame: NSRect(x: 0,
                                 y: 0,
                                 width: label.frame.width + margin * 3 + fieldWidth,
                                 height: textField.frame.height + vmargin * 2))

        addSubview(label)

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.isBezeled = true
        textField.drawsBackground = true
        textField.usesSingleLineMode = true
        var frame = textField.frame
        frame.size.width = fieldWidth
        textField.frame = frame
        addSubview(textField)

        let views = ["label": label,
                     "field": textField]
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-10-[label]-10-[field]-10-|",
                                                      metrics: [:],
                                                      views: views))
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-8-[field]-8-|",
                                                      metrics: [:],
                                                      views: views))
        addConstraint(NSLayoutConstraint(item: textField,
                                         attribute: .width,
                                         relatedBy: .greaterThanOrEqual,
                                         toItem: nil,
                                         attribute: .notAnAttribute,
                                         multiplier: 1,
                                         constant: fieldWidth))
        addConstraint(NSLayoutConstraint(item: label,
                                         attribute: .firstBaseline,
                                         relatedBy: .equal,
                                         toItem: textField,
                                         attribute: .firstBaseline,
                                         multiplier: 1,
                                         constant: 0))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
