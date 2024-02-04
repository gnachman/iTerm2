//
//  ImportExport.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/4/23.
//

import Foundation

@objc(iTerm2ImportExport)
class ImportExport: NSObject {
    @objc
    static func exportAll() -> String? {
        DLog("Begin")
        let savePanel = NSSavePanel()
        savePanel.allowedFileTypes = ["itermexport"]
        savePanel.nameFieldStringValue = "iTerm2 State.itermexport"
        savePanel.title = "Export iTerm2 Settings and Data"

        let response = savePanel.runModal()
        guard response == NSApplication.ModalResponse.OK else {
            return nil
        }
        guard let url = savePanel.url else {
            return nil
        }
        DLog("Export to \(url.path)")
        do {
            let exporter = Exporter()
            try exporter.export(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return nil
        } catch {
            DLog("Failed: \(error)")
            switch error {
            case ImportExportError.failedToCreateTempDir(let reason):
                return "Failed to create temporary directory: \(reason)"
            case ImportExportError.failedToCreateIntermediateFolder(let reason):
                return "Failed to create folder: \(reason)"
            case ImportExportError.failedToCopyFile(let reason):
                return "Failed to copy file: \(reason)"
            case ImportExportError.failedToSaveFile(let reason):
                return "Failed to save file: \(reason)"
            case ImportExportError.bug(let reason):
                return "A bug was encountered: \(reason). Please report this at https://iterm2.com/bugs"
            case ImportExportError.failedToCreateArchive(let reason):
                return "Failed to create archive: \(reason)"
            case ImportExportError.failedToLoadFile(let reason):
                return "Failed to load file: \(reason)"
            case ImportExportError.corruptDataFound(let reason):
                return "Malformed data found: \(reason)"
            case ImportExportError.scriptExportFailed(let reason):
                return "Script could not be exported: \(reason)"
            case ImportExportError.failedToInstallPythonRuntime:
                return "Failed to install Python runtime"
            default:
                return "Unexpected error: \(error.localizedDescription)"
            }
        }
    }

    @objc
    static func importAll() -> String? {
        let openPanel = NSOpenPanel()
        openPanel.allowedFileTypes = ["itermexport"]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false

        guard openPanel.runModal() == .OK, let url = openPanel.url else {
            return nil
        }

        do {
            let selection = iTermWarning.show(
                withTitle: "Any needed Python runtimes will be installed and secure settings will be updated, which may require you to enter your password. Then iTerm2 will restart and finish importing. This can take several minutes.",
                actions: ["OK", "Cancel"],
                accessory: nil,
                identifier: nil,
                silenceable: .kiTermWarningTypePersistent,
                heading: "Importing Settings and Data",
                window: nil)
            if selection == .kiTermWarningSelection1 {
                return nil
            }
            try Importer().importEntities(from: url)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @objc
    static func finishImporting() {
        let path = iTermUserDefaults.importPath!
        let url = URL(fileURLWithPath: path)
        _ = try? Importer().importExtractedEntities(from: url, phase: .final)
        precondition(url.lastPathComponent.hasPrefix(".") && url.lastPathComponent.utf16.count > 12)
        try? FileManager.default.removeItem(at: url)
        NSApp.relaunch()
    }
}

private enum ImportExportError: Error {
    case failedToCreateTempDir(String)
    case failedToCreateIntermediateFolder(String)
    case failedToCopyFile(String)
    case failedToSaveFile(String)
    case bug(String)
    case failedToCreateArchive(String)
    case failedToLoadFile(String)
    case corruptDataFound(String)
    case scriptExportFailed(String)
    case failedToInstallPythonRuntime
}

private func iTermMakeTempDir() throws -> URL {
    let tempDirURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true, attributes: nil)
    return tempDirURL
}

private struct ImportExportConfig {
    enum BaseDirectory {
        case home
        case applicationSupport
    }
    struct Path {
        var baseDirectory: BaseDirectory
        var relativePath: String?

        var url: URL {
            let base = {
                switch baseDirectory {
                case .home:
                    return NSHomeDirectory()
                case .applicationSupport:
                    return FileManager.default.spacelessAppSupportWithoutCreatingLink()
                }
            }()
            guard let relativePath else {
                return URL(fileURLWithPath: base)
            }
            let fullPath = base.appendingPathComponent(relativePath)
            return URL(fileURLWithPath: fullPath)
        }
    }

    struct Entity {
        enum Flavor {
            case pythonRuntimes
            // Exclusions are glob paths relative to the base directory + path.
            case folder(Path, exclude: Set<String>)
            case userDefaults
            case secureUserDefaults
            // Remember that the scripts folder is customizable and you should not assume it's in
            // application support.
            case scripts
            case disableAutomationAuth  // a legacy secure settings before it was made general
        }

        var key: String
        var displayName: String
        var flavor: Flavor
    }
    var entities: [Entity] = [
        Entity(key: "python-runtimes",
               displayName: "Python Runtimes",
               flavor: .pythonRuntimes),
        Entity(key: "secure-user-defaults",
               displayName: "Secure Settings",
               flavor: .secureUserDefaults),
        Entity(key: "disable-automation-auth",
               displayName: "Python API Authorization Setting",
               flavor: .disableAutomationAuth),
        Entity(key: "user-defaults",
               displayName: "User Defaults",
               flavor: .userDefaults),
        Entity(key: "dot-iterm2",
               displayName: "~/.iterm2",
               flavor: .folder(Path(baseDirectory: .home, relativePath: ".iterm2"),
                               exclude: Set(["AppSupport", "iTermServer-*", "sockets", "Scripts"]))),
        Entity(key: "app-support",
               displayName: "Application Support",
               flavor: .folder(Path(baseDirectory: .applicationSupport, relativePath: nil),
                               exclude: Set(["????????-????-????-????-????????????",
                                             "*.secureSetting",
                                             "Scripts",
                                             "disable-automation-auth",
                                             "iTermServer-*",
                                             "iterm2-daemon-*",
                                             "iterm2env*",
                                             "parsers",
                                             "private",
                                             "servers",
                                             "version.txt"]))),
        Entity(key: "scripts",
               displayName: "Python API Scripts",
               flavor: .scripts),
    ]
}

private class Importer {
    private let config = ImportExportConfig()

    static func launchStatusApp() -> FileHandle? {
        let appPath = Bundle.main.bundlePath + "/Contents/MacOS/iTerm2ImportStatus.app/Contents/MacOS/iTerm2ImportStatus"
        let task = Process()
        task.launchPath = appPath

        // Create a pipe and assign it to the task's standard input.
        let pipe = Pipe()
        task.standardInput = pipe

        do {
            try task.run()
        } catch {
            print("Failed to launch task: \(error)")
            return nil
        }
        try? pipe.fileHandleForReading.close()
        return pipe.fileHandleForWriting
    }

    private let statusFileHandle: FileHandle?

    init() {
        statusFileHandle = Self.launchStatusApp()
    }

    private func setStatus(_ status: String) {
        guard let fileHandle = statusFileHandle else {
            print("File handle is nil")
            return
        }

        DispatchQueue.global().async {
            if let data = (status + "\n").data(using: .utf8) {
                do {
                    try ObjC.catching {
                        fileHandle.write(data)
                    }
                } catch {
                    DLog("Failed to write to file handle: \(error)")
                }
            } else {
                DLog("Failed to convert string to data")
            }
        }
    }

    func importEntities(from url: URL) throws {
        let tempDir = try makeTempDir()
        setStatus("Extracting Archive")
        if NSData.untar(fromArchive: url, to: tempDir) != 0 {
            return
        }

        try importExtractedEntities(from: tempDir, phase: .initial)
    }

    fileprivate enum Phase {
        case initial
        case final
    }

    fileprivate func importExtractedEntities(from sourceFolder: URL, phase: Phase) throws {
        for entity in config.entities {
            try importEntity(entity, from: sourceFolder, phase: phase)
        }
    }

    private func importEntity(_ entity: ImportExportConfig.Entity,
                              from baseURL: URL,
                              phase: Phase) throws {
        let url = baseURL.appendingPathComponent(entity.key)
        setStatus("Importing \(entity.displayName)")
        switch entity.flavor {
        case .pythonRuntimes:
            switch phase {
            case .initial:
                try PythonRuntimesImporterExporter().performImport(from: url)
            case .final:
                break
            }
        case .secureUserDefaults:
            switch phase {
            case .initial:
                try SecureUserDefaultsImporterExporter().performImport(from: url)
            case .final:
                break
            }
        case .disableAutomationAuth:
            switch phase {
            case .initial:
                try AutomationAuthImporterExporter().performImport(from: url)
            case .final:
                break
            }
        case .userDefaults:
            try UserDefaultsImporterExporter().performImport(from: url)
        case let .folder(path, _):
            try FolderImporterExporter().performImport(from: url, to: path)
        case .scripts:
            try ScriptsImporterExporter(setStatus: self.setStatus).performImport(from: url)
        }
    }

    private func makeTempDir() throws -> URL {
        do {
            let tempDirURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("." + UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true, attributes: nil)
            return tempDirURL
        } catch {
            throw ImportExportError.failedToCreateTempDir(error.localizedDescription)
        }
    }
}

private class Exporter {
    private let config = ImportExportConfig()

    func export(to url: URL) throws {
        let tempDir = try makeTempDir()

        for entity in config.entities {
            try export(entity: entity, to: tempDir)
        }

        return try archive(filesInFolder: tempDir, to: url)
    }

    private func makeTempDir() throws -> URL {
        do {
            return try iTermMakeTempDir()
        } catch {
            throw ImportExportError.failedToCreateTempDir(error.localizedDescription)
        }
    }

    private func export(entity: ImportExportConfig.Entity, to base: URL) throws {
        DLog("Begin \(entity.key)")
        let destination = base.appendingPathComponent(entity.key)
        do {
            try FileManager.default.createDirectory(at: destination,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
        } catch {
            DLog("\(error)")
            throw ImportExportError.failedToCreateIntermediateFolder(error.localizedDescription)
        }

        switch entity.flavor {
        case .pythonRuntimes:
            try PythonRuntimesImporterExporter().export(to: destination)
        case .folder(let path, exclude: let exclusions):
            try FolderImporterExporter().export(path: path,
                                                exclude: exclusions,
                                                destination: destination)
        case .userDefaults:
            try UserDefaultsImporterExporter().export(to: destination)
        case .secureUserDefaults:
            try SecureUserDefaultsImporterExporter().export(to: destination)
        case .scripts:
            try ScriptsImporterExporter().export(to: destination)
        case .disableAutomationAuth:
            try AutomationAuthImporterExporter().export(to: destination)
        }
    }

    func archive(filesInFolder source: URL, to destination: URL) throws {
        let sourceFiles = try FileManager.default.contentsOfDirectory(at: source,
                                                                      includingPropertiesForKeys: nil,
                                                                      options: .skipsHiddenFiles)
        let data: NSData
        do {
            data = try NSData(tgzContainingFiles: sourceFiles.map { $0.resolvingSymlinksInPath().lastPathComponent },
                              relativeToPath: source.resolvingSymlinksInPath().path,
                              includeExtendedAttrs: true)
        } catch {
            throw ImportExportError.failedToCreateArchive(error.localizedDescription)
        }
        do {
            try data.write(to: destination)
        } catch {
            throw ImportExportError.failedToSaveFile(error.localizedDescription)
        }
    }

}

private struct FolderImporterExporter {
    func export(path: ImportExportConfig.Path,
                exclude: Set<String>,
                destination: URL) throws {
        DLog("Begin")
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path.url.resolvingSymlinksInPath().path, isDirectory: &isDirectory) && isDirectory.boolValue else {
            return
        }
        do {
            try FileManager.default.deepCopyContentsOfDirectory(source: path.url,
                                                                to: destination,
                                                                excluding: exclude)
        } catch {
            throw ImportExportError.failedToCopyFile(error.localizedDescription)
        }
    }

    func performImport(from source: URL,
                       to destination: ImportExportConfig.Path) throws {
        do {
            try FileManager.default.deepCopyContentsOfDirectory(source: source,
                                                                to: destination.url,
                                                                excluding: Set())
        } catch {
            throw ImportExportError.failedToCopyFile(error.localizedDescription)
        }
    }
}

private struct PythonRuntimesImporterExporter {
    struct Info: Codable {
        var requirements: [Requirement]
        var haveAnyBasicScripts: Bool
    }
    struct Requirement: Hashable, Codable, CustomDebugStringConvertible {
        var debugDescription: String {
            return "<Requirement runtime >= \(minimumRuntime), python=\(pythonVersion)>"
        }
        var minimumRuntime: Int
        var pythonVersion: String
    }
    private let filename = "PythonRuntimes.json"
    var setStatus: ((String) -> ())?

    init(setStatus: ((String) -> ())? = nil) {
        self.setStatus = setStatus
    }

    func export(to destination: URL) throws {
        DLog("Begin")
        var requirements = Set<Requirement>()
        var haveAnyBasicScripts = false

        let scriptsPath: String = FileManager.default.scriptsPath()
        let base = URL(fileURLWithPath: scriptsPath)
        let regularItems = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        let autolaunch = base.appendingPathComponent("AutoLaunch")
        let autolaunchItems = (try? FileManager.default.contentsOfDirectory(at: autolaunch, includingPropertiesForKeys: nil)) ?? []
        for item in (regularItems + autolaunchItems) {
            DLog("item is \(item)")
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory) else {
                DLog("skip \(item.path)")
                continue
            }
            if !isDirectory.boolValue {
                if item.lastPathComponent.hasSuffix(".py") {
                    DLog("Found basic script")
                    haveAnyBasicScripts = true
                }
                continue
            }
            let setup = item.appendingPathComponent("setup.cfg")
            DLog("Parse \(setup.path)")
            if let parser = iTermSetupCfgParser(path: setup.path) {
                requirements.insert(Requirement(minimumRuntime: parser.minimumEnvironmentVersion,
                                                pythonVersion: parser.pythonVersion))
            }
        }
        DLog("Requirements are \(requirements)")
        let encoder = JSONEncoder()
        let encoded = try! encoder.encode(Info(requirements: Array(requirements),
                                               haveAnyBasicScripts: haveAnyBasicScripts))
        do {
            DLog("Write \(encoded) to \(destination.appendingPathComponent(filename))")
            try encoded.write(to: destination.appendingPathComponent(filename))
        } catch {
            DLog("\(error)")
            throw ImportExportError.failedToSaveFile(error.localizedDescription)
        }
    }

    func performImport(from source: URL) throws {
        DLog("Begin")
        let data: Data
        let url = source.appendingPathComponent(filename)
        do {
            DLog("Read \(url.path)")
            data = try Data(contentsOf: url)
        } catch {
            DLog("\(error)")
            throw ImportExportError.failedToLoadFile(error.localizedDescription)
        }

        let decoder = JSONDecoder()
        let info: Info
        do {
            info = try decoder.decode(Info.self, from: data)
        } catch {
            DLog("\(error) for \(data)")
            throw ImportExportError.corruptDataFound(error.localizedDescription)
        }

        var i = 1
        let n = (info.haveAnyBasicScripts ? 1 : 0) + info.requirements.count
        if info.haveAnyBasicScripts {
            DLog("Install most recent")
            if !install(requirement: nil) {
                throw ImportExportError.failedToInstallPythonRuntime
            }
            setStatus?("Installing Python runtime \(i) of \(n)")
            i += 1
        }
        for requirement in info.requirements {
            setStatus?("Installing Python runtime \(i) of \(n)")
            i += 1
            DLog("Install \(requirement)")
            if !install(requirement: requirement) {
                throw ImportExportError.failedToInstallPythonRuntime
            }
        }
    }


    private func install(requirement: Requirement?) -> Bool {
        var result: Bool?
        DLog("Begin \(String(describing: requirement))")
        iTermPythonRuntimeDownloader.sharedInstance().downloadOptionalComponentsIfNeeded(
            withConfirmation: false,
            pythonVersion: requirement?.pythonVersion,
            minimumEnvironmentVersion: requirement?.minimumRuntime ?? 0,
            requiredToContinue: true) { status in
                switch status {
                case .unknown, .working:
                    DLog("Unknown/working")
                    break
                case .notNeeded, .downloaded:
                    DLog("not needed/downloaded")
                    result = true
                case .canceledByUser, .requestedVersionNotFound, .error:
                    DLog("canceled/not found/error")
                    result = false
                @unknown default:
                    fatalError()
                }
                if result != nil {
                    DLog("Stop runloop")
                    CFRunLoopStop(RunLoop.current.getCFRunLoop())
                }
            }
        DLog("Begin spinning")
        let runLoop = RunLoop.current
        while result == nil && runLoop.run(mode: .default, before: .distantFuture) {
            // Do nothing
        }
        DLog("Done")
        return result ?? false
    }
}

private struct UserDefaultsImporterExporter {
    private let filename = "UserDefaults.plist"
    func export(to destination: URL) throws {
        DLog("Begin")
        let dictionary = iTermRemotePreferences.sharedInstance().userDefaultsDictionary
        try dictionary.saveAsPropertyList(to: destination.appendingPathComponent(filename))
    }

    func performImport(from source: URL) throws {
        DLog("Begin")
        if iTermUserDefaults.importPath != nil {
            DLog("Have import path")
            iTermPreferences.initializeUserDefaults()
            iTermPreferences.setBool(false, forKey: kPreferenceKeyLoadPrefsFromCustomFolder)
            iTermPreferences.setString(nil, forKey: kPreferenceKeyCustomFolder)
            iTermUserDefaults.importPath = nil
            return
        }
        DLog("No import path")
        iTermPreferences.setBool(true, forKey: kPreferenceKeyLoadPrefsFromCustomFolder)
        iTermPreferences.setString(source.appendingPathComponent(filename).path,
                                   forKey: kPreferenceKeyCustomFolder)
        iTermUserDefaults.importPath = source.deletingLastPathComponent().path

        NSApp.relaunch()
    }
}

extension NSApplication {
    @objc
    func relaunch() -> Never {
        DLog("Relaunch")
        let pid = ProcessInfo().processIdentifier
        let pathToSelf = Bundle.main.bundlePath
        let quotedPathToSelf = pathToSelf.withEscapedShellCharacters(includingNewlines: true) as String
        let script = ["while /bin/kill -0 \(pid) >&/dev/null",
                      "do /bin/sleep 0.1",
                      "done",
                      "/usr/bin/open \(quotedPathToSelf)"].joined(separator: ";")
        Process.launchedProcess(launchPath: "/bin/sh", arguments: ["-c", "(" + script + ")&"])
        exit(0)
    }
}

private struct SecureUserDefaultsImporterExporter {
    private let filename = "SecureUserDefaults.plist"
    func export(to destination: URL) throws {
        DLog("Begin")
        let dictionary = SecureUserDefaults.instance.serializeAll()
        try dictionary.saveAsPropertyList(to: destination.appendingPathComponent(filename))
    }

    func performImport(from source: URL) throws {
        DLog("Begin")
        let data: Data
        do {
            data = try Data(contentsOf: source.appendingPathComponent(filename))
        } catch {
            DLog("\(error)")
            throw ImportExportError.failedToLoadFile(error.localizedDescription)
        }
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            DLog("\(error) for \(data.stringOrHex)")
            throw ImportExportError.corruptDataFound("Invalid data found at \(source.path)")
        }
        if let stringDict = plist as? [String: String] {
            reallyPerformImport(stringDict)
        } else {
            DLog("Cast failed for \(plist)")
            throw ImportExportError.corruptDataFound("Wrong format content for \(source.path)")
        }
    }

    private func reallyPerformImport(_ dict: [String: String]) {
        SecureUserDefaults.instance.deserializeAll(dict: dict)
    }
}

func relativePath(base: URL, absolutePath: URL) -> String? {
    let baseComponents = base.pathComponents
    let absoluteComponents = absolutePath.pathComponents

    // If the absolute path is not within the base directory, return nil
    guard absoluteComponents.starts(with: baseComponents) else {
        return nil
    }

    guard absoluteComponents.count > baseComponents.count else {
        return nil
    }

    return absoluteComponents[baseComponents.count...].joined(separator: "/")
}

private struct ScriptsImporterExporter {
    private let iterm2env = "iterm2env"
    var setStatus: ((String) -> ())?

    init(setStatus: ((String) -> ())? = nil) {
        self.setStatus = setStatus
    }

    func export(to destination: URL) throws {
        DLog("Begin")
        let scriptsPath: String = FileManager.default.scriptsPath()
        let base = URL(fileURLWithPath: scriptsPath)
        do {
            let items = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
            for item in (items ?? []) {
                if item.lastPathComponent == ".DS_Store" {
                    continue
                }
                if item.lastPathComponent.lowercased() == "autolaunch" {
                    continue
                }
                try export(item: item, to: destination, autolaunch: false)
            }
        }
        do {
            let autolaunch = base.appendingPathComponent("AutoLaunch")
            let items = try? FileManager.default.contentsOfDirectory(at: autolaunch, includingPropertiesForKeys: nil)
            for item in (items ?? []) {
                try export(item: item, to: destination, autolaunch: true)
            }
        }
    }

    private func export(item: URL, to destination: URL, autolaunch: Bool) throws {
        DLog("Export \(item.path) to \(destination.path), autolaunch=\(autolaunch)")
        if !iTermScriptExporter.urlIsScript(item) {
            DLog("Skip non-script \(item.path)")
            return
        }
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory) else {
            return
        }
        let group = DispatchGroup()
        group.enter()
        var error: String?
        let name: String
        if autolaunch {
            name = "autolaunch \(UUID().uuidString).zip"
        } else {
            name = "script \(UUID().uuidString).zip"
        }
        let zip = destination.appendingPathComponent(name)
        iTermScriptExporter.exportScript(at: item,
                                         signing: nil,
                                         callbackQueue: DispatchQueue.global(),
                                         destination: zip) { maybeError, maybeZip in
            error = maybeError
            group.leave()
        }
        group.wait()
        if let error {
            DLog("Failed \(error)")
            throw ImportExportError.scriptExportFailed(error)
        }
    }

    func performImport(from source: URL) throws {
        DLog("Begin")
        guard let items = try? FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else {
            return
        }
        for (i, path) in items.enumerated() {
            DLog("\(path)")
            setStatus?("Import script \(i + 1) of \(items.count)")
            importScript(from: path, autolaunch: path.lastPathComponent.hasPrefix("autolaunch"))
        }
    }


    private func importScript(from source: URL, autolaunch: Bool) {
        var error: String?

        var unblockRunloop = false
        func waitForDone() {
            let runLoop = RunLoop.current
            while !unblockRunloop && runLoop.run(mode: .default, before: .distantFuture) {
                // Do nothing
            }
        }

        DLog("Start importing")
        iTermScriptImporter.importScript(from: source,
                                         userInitiated: true,
                                         offerAutoLaunch: autolaunch,
                                         callbackQueue: DispatchQueue.main,
                                         avoidUI: true) { maybeErrorMessage, _, _ in
            DLog("Done")
            error = maybeErrorMessage
            unblockRunloop = true
            CFRunLoopStop(RunLoop.current.getCFRunLoop())
        }
        waitForDone()
        DLog("\(source.path) \(autolaunch) \(error ?? "ok")")
    }
}

private struct AutomationAuthImporterExporter {
    private let filename = "exists"
    func export(to destination: URL) throws {
        DLog("Begin")
        switch iTermAPIHelper.noAuthStatus(nil) {
        case .none, .corrupt:
            return
        case .valid:
            break
        @unknown default:
            return
        }
        DLog("Write file")
        do {
            try "".write(to: destination.appendingPathComponent(filename),
                         atomically: true,
                         encoding: .utf8)
        } catch {
            throw ImportExportError.failedToSaveFile(error.localizedDescription)
        }
    }

    func performImport(from: URL) throws {
        DLog("Begin")
        // The file exists if the authorization is not required (the dangerous setting)
        let exists = FileManager.default.fileExists(atPath: from.path.appendingPathComponent(filename))
        DLog("Exists = \(exists)")
        iTermAPIHelper.setRequireApplescriptAuth(!exists,
                                                 window: nil)
    }
}

fileprivate extension Dictionary {
    func saveAsPropertyList(to destination: URL) throws {
        guard let plistData = try? PropertyListSerialization.data(fromPropertyList: self,
                                                                  format: .xml,
                                                                  options: 0) else {
            throw ImportExportError.bug("Failed to serialize user defaults")
        }

        do {
            try plistData.write(to: destination)
        } catch {
            throw ImportExportError.failedToSaveFile(error.localizedDescription)
        }
    }
}

extension FileManager {
    func deepCopyContentsOfDirectory(source: URL,
                                     to destination: URL,
                                     excluding exclusions: Set<String>) throws {
        let fileManager = FileManager.default

        // Create the destination directory if it does not exist
        try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true, attributes: nil)

        // Get the contents of the source directory
        let directoryContents = try fileManager.contentsOfDirectory(at: source.resolvingSymlinksInPath(),
                                                                    includingPropertiesForKeys: nil,
                                                                    options: .skipsHiddenFiles)

        // Loop through the contents of the source directory
        for url in directoryContents {
            let fileName = url.lastPathComponent

            // Check if the file should be excluded based on the glob pattern
            if exclusions.contains(where: { fileName.matchesGlob($0) }) {
                DLog("Skipping file: \(fileName)")
                continue
            }

            // Determine the destination file URL
            let destinationURL = destination.appendingPathComponent(fileName)

            // Check if the item at the URL is a directory
            var isDirectory: ObjCBool = false
            guard fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }

            // If the item is a directory, recursively copy its contents
            if isDirectory.boolValue {
                // Copy the directory recursively
                let subDestination = destination.appendingPathComponent(fileName)
                try deepCopyContentsOfDirectory(source: url, to: subDestination, excluding: Set())
            } else {
                // Copy the file to the destination directory
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: url, to: destinationURL)
            }
        }
    }

    func deepCopyDirectory(at sourceURL: URL,
                           to destinationURL: URL,
                           shouldCopySubdirectory: (URL) -> Bool) throws {
        try? createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        let contents = try contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil, options: [])
        for item in contents {
            let destinationItemURL = destinationURL.appendingPathComponent(item.lastPathComponent)
            var isDirectory: ObjCBool = false
            guard fileExists(atPath: item.path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                if shouldCopySubdirectory(item) {
                    try deepCopyDirectory(at: item,
                                          to: destinationItemURL,
                                          shouldCopySubdirectory: shouldCopySubdirectory)
                }
            } else {
                try copyItem(at: item, to: destinationItemURL)
            }
        }
    }
}

extension String {
    func matchesGlob(_ pattern: String) -> Bool {
        return self.withCString { s in
            return pattern.withCString { p in
                fnmatch(p, s, FNM_PATHNAME) == 0
            }
        }
    }
}
