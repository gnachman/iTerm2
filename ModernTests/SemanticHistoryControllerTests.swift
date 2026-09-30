//
//  SemanticHistoryControllerTests.swift
//  iTerm2
//
//  Ported from the legacy iTermSemanticHistoryTest.m. Exercises
//  iTermSemanticHistoryController against a fake file system and with every
//  side effect (launching tasks, opening files and URLs, launching apps)
//  recorded instead of performed.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

// A file manager whose file system consists solely of the paths added to
// `files`, `directories` and `networkMountPoints`. It overrides every
// NSFileManager entry point that iTermPathCleaner and iTermPathFinder use so
// no test ever touches the real disk or the automounter configuration.
private final class FakeFileManager: FileManager {
    var files = Set<String>()
    var directories = Set<String>()
    var networkMountPoints = Set<String>()

    override func fileExists(atPath path: String) -> Bool {
        return fileExists(atPath: path, isDirectory: nil)
    }

    override func fileExists(atPath path: String,
                             isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        if files.contains(path) {
            isDirectory?.pointee = false
            return true
        }
        if directories.contains(path) {
            isDirectory?.pointee = true
            return true
        }
        return false
    }

    private func isOnNetwork(_ filename: String, additionalNetworkPaths: [String]) -> Bool {
        let networkPaths = networkMountPoints.union(additionalNetworkPaths)
        return networkPaths.contains { !$0.isEmpty && filename.hasPrefix($0) }
    }

    override func fileHasForbiddenPrefix(_ filename: String,
                                         additionalNetworkPaths: [String]) -> Bool {
        return isOnNetwork(filename, additionalNetworkPaths: additionalNetworkPaths)
    }

    override func fileIsLocal(_ filename: String,
                              additionalNetworkPaths: [String],
                              allowNetworkMounts: Bool) -> Bool {
        if allowNetworkMounts {
            return true
        }
        return !isOnNetwork(filename, additionalNetworkPaths: additionalNetworkPaths)
    }

    override func fileExists(atPathLocally filename: String,
                                          additionalNetworkPaths: [String],
                                          allowNetworkMounts: Bool) -> Bool {
        if !fileIsLocal(filename,
                        additionalNetworkPaths: additionalNetworkPaths,
                        allowNetworkMounts: allowNetworkMounts) {
            return false
        }
        return fileExists(atPath: filename)
    }
}

// Records every side effect the controller would otherwise perform.
private final class RecordingSemanticHistoryController: iTermSemanticHistoryController {
    let fakeFileManager = FakeFileManager()
    var scriptArguments: [String]?
    var openedFile: String?
    var openedURL: URL?
    var openedEditor: String?
    var launchedApp: String?
    var launchedAppArg: String?
    var defaultAppIsEditor = false
    var bundleIdForDefaultApp: String?

    override var fileManager: FileManager! {
        return fakeFileManager
    }

    override func launchTask(withPath path: String!,
                             arguments: [Any]!,
                             completion: (() -> Void)!) {
        scriptArguments = arguments as? [String]
        completion?()
    }

    override func openFile(_ fullPath: String!,
                           fragment: String!,
                           target: String!,
                           window: NSWindow!) {
        if let fragment = fragment {
            openedFile = "\(fullPath ?? "")#\(fragment)"
        } else {
            openedFile = fullPath
        }
    }

    override func open(_ url: URL!, editorIdentifier: String!) {
        openedURL = url
        openedEditor = editorIdentifier
    }

    override func defaultApp(forFileIsEditor file: String!) -> Bool {
        return defaultAppIsEditor
    }

    override func launchApp(withBundleIdentifier bundleIdentifier: String!, path: String!) {
        launchedApp = bundleIdentifier
        launchedAppArg = path
    }

    override func absolutePathForAppBundle(withIdentifier bundleId: String!) -> String! {
        return "/Applications/" + (bundleId ?? "")
    }

    // Never consults NSWorkspace, so the result does not depend on which apps
    // are installed on the machine running the tests.
    override func bundleIdForDefaultApp(forFile file: String!) -> String! {
        return bundleIdForDefaultApp
    }
}

final class SemanticHistoryControllerTests: XCTestCase, iTermObject, iTermSemanticHistoryControllerDelegate {
    private var controller: RecordingSemanticHistoryController!
    private var scope: iTermVariableScope!
    private var coprocessCommand: String?
    private var sentText: String?

    private let actionKey: String = kSemanticHistoryActionKey
    private let editorKey: String = kSemanticHistoryEditorKey
    private let textKey: String = kSemanticHistoryTextKey
    private let pathSubstitutionKey: String = kSemanticHistoryPathSubstitutionKey
    private let prefixSubstitutionKey: String = kSemanticHistoryPrefixSubstitutionKey
    private let suffixSubstitutionKey: String = kSemanticHistorySuffixSubstitutionKey
    private let workingDirectorySubstitutionKey: String = kSemanticHistoryWorkingDirectorySubstitutionKey
    private let lineNumberKey: String = kSemanticHistoryLineNumberKey
    private let columnNumberKey: String = kSemanticHistoryColumnNumberKey

    private let rawCommandAction: String = kSemanticHistoryRawCommandAction
    private let bestEditorAction: String = kSemanticHistoryBestEditorAction
    private let commandAction: String = kSemanticHistoryCommandAction
    private let coprocessAction: String = kSemanticHistoryCoprocessAction
    private let sendTextAction: String = kSemanticHistorySendTextAction
    private let urlAction: String = kSemanticHistoryUrlAction
    private let editorAction: String = kSemanticHistoryEditorAction

    private let macVimIdentifier: String = kMacVimIdentifier
    private let atomIdentifier: String = kAtomIdentifier
    private let vsCodeIdentifier: String = kVSCodeIdentifier
    private let sublimeText2Identifier: String = kSublimeText2Identifier
    private let sublimeText3Identifier: String = kSublimeText3Identifier
    private let sublimeText4Identifier: String = kSublimeText4Identifier
    private let textmateIdentifier: String = kTextmateIdentifier
    private let bbEditIdentifier: String = kBBEditIdentifier

    private let existingFile = "/file/that/exists"
    private let filename = "/path/to/file"
    private let workingDirectory = "/working/directory"

    override func setUp() {
        super.setUp()
        scope = iTermVariableScope()
        let variables = iTermVariables(context: [], owner: self)
        scope.add(variables, toScopeNamed: nil)

        controller = RecordingSemanticHistoryController()
        controller.delegate = self
        coprocessCommand = nil
        sentText = nil
    }

    override func tearDown() {
        controller.delegate = nil
        controller = nil
        scope = nil
        super.tearDown()
    }

    // MARK: - iTermObject

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { nil }

    // MARK: - iTermSemanticHistoryControllerDelegate

    func semanticHistoryLaunchCoprocess(withCommand command: String!) {
        coprocessCommand = command
    }

    func semanticHistorySendText(_ text: String!) {
        sentText = text
    }

    // MARK: - Helpers

    private struct CleanedPath {
        let path: String?
        let lineNumber: String?
        let columnNumber: String?
    }

    private func cleanedUpPath(_ path: String?,
                               suffix: String? = nil,
                               workingDirectory: String) -> CleanedPath {
        var lineNumber: NSString?
        var columnNumber: NSString?
        let result = controller.cleanedUpPath(fromPath: path,
                                              suffix: suffix,
                                              workingDirectory: workingDirectory,
                                              extractedLineNumber: &lineNumber,
                                              columnNumber: &columnNumber)
        return CleanedPath(path: result,
                           lineNumber: lineNumber as String?,
                           columnNumber: columnNumber as String?)
    }

    private struct FoundPath {
        let path: String?
        let prefixChars: Int
        let suffixChars: Int
    }

    private func pathOfExistingFile(prefix: String,
                                    suffix: String,
                                    workingDirectory: String,
                                    trimWhitespace: Bool) -> FoundPath {
        var prefixChars: Int32 = 0
        var suffixChars: Int32 = 0
        let path = controller.pathOfExistingFileFound(withPrefix: prefix,
                                                      suffix: suffix,
                                                      workingDirectory: workingDirectory,
                                                      charsTakenFromPrefix: &prefixChars,
                                                      charsTakenFromSuffix: &suffixChars,
                                                      trimWhitespace: trimWhitespace)
        return FoundPath(path: path, prefixChars: Int(prefixChars), suffixChars: Int(suffixChars))
    }

    // Runs openPath and waits for its completion block. All the recorded side
    // effects complete synchronously or on the main queue, so the wait only
    // pumps the run loop; nothing here depends on wall-clock timing.
    private func openPath(_ path: String?,
                          rawFilename: String,
                          substitutions: [String: String],
                          lineNumber: String?,
                          columnNumber: String?) -> Bool {
        let done = expectation(description: "openPath completion")
        var result = false
        controller.openPath(path,
                            orRawFilename: rawFilename,
                            fragment: nil,
                            target: nil,
                            substitutions: substitutions,
                            scope: scope,
                            lineNumber: lineNumber,
                            columnNumber: columnNumber,
                            window: nil) { ok in
            result = ok
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
        return result
    }

    // Cleans up `rawFilename` relative to `workingDirectory` and then opens it,
    // the way PTYTextView does.
    private func cleanAndOpen(_ rawFilename: String,
                              workingDirectory: String = "/",
                              substitutions: [String: String]) -> Bool {
        let cleaned = cleanedUpPath(rawFilename, workingDirectory: workingDirectory)
        return openPath(cleaned.path,
                        rawFilename: rawFilename,
                        substitutions: substitutions,
                        lineNumber: cleaned.lineNumber,
                        columnNumber: cleaned.columnNumber)
    }

    private func standardSubstitutions(workingDirectory: String) -> [String: String] {
        return [prefixSubstitutionKey: "Prefix",
                suffixSubstitutionKey: "Suffix",
                workingDirectorySubstitutionKey: workingDirectory]
    }

    // The URL the controller composes for scheme-based editors. Without a
    // line number the slashes of the file URL are percent-encoded. Adding a
    // line number goes through NSURLComponents.queryItems, which hands back
    // the decoded value, so the file URL then appears with literal slashes.
    // Both forms are what the legacy test expected. For a path made only of
    // unreserved characters they are equivalent; see the Editor URL encoding
    // tests below for paths where the two branches disagree.
    private func editorURL(scheme: String, path: String, lineNumber: String?) -> URL? {
        if let lineNumber = lineNumber {
            return URL(string: "\(scheme)://open?url=file://\(path)&line=\(lineNumber)")
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "/")
        guard let encodedFile = "file://\(path)".addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: "\(scheme)://open?url=\(encodedFile)")
    }

    // MARK: - Get Full Path

    func testGetFullPathFailsOnNil() {
        let result = controller.cleanedUpPath(fromPath: nil,
                                              suffix: nil,
                                              workingDirectory: "/",
                                              extractedLineNumber: nil,
                                              columnNumber: nil)
        XCTAssertNil(result)
    }

    func testGetFullPathFailsOnEmpty() {
        let result = controller.cleanedUpPath(fromPath: "",
                                              suffix: nil,
                                              workingDirectory: "/",
                                              extractedLineNumber: nil,
                                              columnNumber: nil)
        XCTAssertNil(result)
    }

    func testGetFullPathFindsExistingFileAtAbsolutePath() {
        controller.fakeFileManager.files.insert(filename)
        let cleaned = cleanedUpPath(filename, workingDirectory: workingDirectory)
        XCTAssertEqual(cleaned.path, filename)
        XCTAssertNil(cleaned.lineNumber)
    }

    func testGetFullPathFindsExistingFileAtRelativePath() {
        let relativeFilename = "path/to/file"
        let absoluteFilename = (workingDirectory as NSString).appendingPathComponent(relativeFilename)
        controller.fakeFileManager.files.insert(absoluteFilename)
        let cleaned = cleanedUpPath(relativeFilename, workingDirectory: workingDirectory)
        XCTAssertEqual(cleaned.path, absoluteFilename)
        XCTAssertNil(cleaned.lineNumber)
    }

    private func assertStripsDelimiters(open: Character, close: Character,
                                        file: StaticString = #filePath, line: UInt = #line) {
        controller.fakeFileManager.files.insert(filename)
        let delimited = "\(open)\(filename)\(close)"
        let cleaned = cleanedUpPath(delimited, workingDirectory: workingDirectory)
        XCTAssertEqual(cleaned.path, filename, "Failed to strip \(delimited)", file: file, line: line)
        XCTAssertNil(cleaned.lineNumber, file: file, line: line)
    }

    func testGetFullPathStripsParentheses() {
        assertStripsDelimiters(open: "(", close: ")")
    }

    func testGetFullPathStripsAngleBrackets() {
        assertStripsDelimiters(open: "<", close: ">")
    }

    func testGetFullPathStripsSquareBrackets() {
        assertStripsDelimiters(open: "[", close: "]")
    }

    func testGetFullPathStripsCurlyBraces() {
        assertStripsDelimiters(open: "{", close: "}")
    }

    func testGetFullPathStripsSingleQuotes() {
        assertStripsDelimiters(open: "'", close: "'")
    }

    func testGetFullPathStripsDoubleQuotes() {
        assertStripsDelimiters(open: "\"", close: "\"")
    }

    private func assertStripsTrailingPunctuation(_ punctuation: String,
                                                 file: StaticString = #filePath, line: UInt = #line) {
        controller.fakeFileManager.files.insert(filename)
        let cleaned = cleanedUpPath(filename + punctuation, workingDirectory: workingDirectory)
        XCTAssertEqual(cleaned.path, filename, "Failed to strip trailing \(punctuation)", file: file, line: line)
        XCTAssertNil(cleaned.lineNumber, file: file, line: line)
    }

    func testGetFullPathStripsTrailingPeriod() {
        assertStripsTrailingPunctuation(".")
    }

    func testGetFullPathStripsTrailingCloseParen() {
        assertStripsTrailingPunctuation(")")
    }

    func testGetFullPathStripsTrailingComma() {
        assertStripsTrailingPunctuation(",")
    }

    func testGetFullPathStripsTrailingColon() {
        assertStripsTrailingPunctuation(":")
    }

    func testGetFullPathExtractsLineNumber() {
        controller.fakeFileManager.files.insert(filename)
        let cleaned = cleanedUpPath(filename + ":123", workingDirectory: workingDirectory)
        XCTAssertEqual(cleaned.path, filename)
        XCTAssertEqual(cleaned.lineNumber, "123")
        XCTAssertNil(cleaned.columnNumber)
    }

    func testGetFullPathExtractsLineNumberAndColumnWithColonSyntax() {
        controller.fakeFileManager.files.insert(filename)
        let cleaned = cleanedUpPath(filename + ":123:456", workingDirectory: workingDirectory)
        XCTAssertEqual(cleaned.path, filename)
        XCTAssertEqual(cleaned.lineNumber, "123")
        XCTAssertEqual(cleaned.columnNumber, "456")
    }

    func testGetFullPathExtractsAlternateLineNumberAndColumnSyntax() {
        controller.fakeFileManager.files.insert(filename)
        let cleaned = cleanedUpPath(filename + "[123, 456]", workingDirectory: workingDirectory)
        XCTAssertEqual(cleaned.path, filename)
        XCTAssertEqual(cleaned.lineNumber, "123")
        XCTAssertEqual(cleaned.columnNumber, "456")
    }

    func testGetFullPathExtractsAlternateLineNumberAndColumnSyntaxWithNoSpaceAfterComma() {
        controller.fakeFileManager.files.insert(filename)
        let cleaned = cleanedUpPath(filename + "[123,456]", workingDirectory: workingDirectory)
        XCTAssertEqual(cleaned.path, filename)
        XCTAssertEqual(cleaned.lineNumber, "123")
        XCTAssertEqual(cleaned.columnNumber, "456")
    }

    func testGetFullPathExtractsVeryVerboseLineNumberAndColumnSyntax() {
        controller.fakeFileManager.files.insert(filename)
        let cleaned = cleanedUpPath(filename,
                                    suffix: "\", line 123, column 456",
                                    workingDirectory: workingDirectory)
        XCTAssertEqual(cleaned.path, filename)
        XCTAssertEqual(cleaned.lineNumber, "123")
        XCTAssertEqual(cleaned.columnNumber, "456")
    }

    func testGetFullPathExtractsVeryVerboseLineNumberSyntax() {
        controller.fakeFileManager.files.insert(filename)
        let cleaned = cleanedUpPath(filename,
                                    suffix: "\", line 123, in",
                                    workingDirectory: workingDirectory)
        XCTAssertEqual(cleaned.path, filename)
        XCTAssertEqual(cleaned.lineNumber, "123")
        XCTAssertNil(cleaned.columnNumber)
    }

    func testGetFullPathExtractsParenthesesLineNumberAndColumnSyntax() {
        controller.fakeFileManager.files.insert(filename)
        let cleaned = cleanedUpPath(filename + "(123, 456)",
                                    suffix: "",
                                    workingDirectory: workingDirectory)
        XCTAssertEqual(cleaned.path, filename)
        XCTAssertEqual(cleaned.lineNumber, "123")
        XCTAssertEqual(cleaned.columnNumber, "456")
    }

    func testGetFullPathExtractsParenthesesLineNumberAndColumnSyntaxWithNoSpaceAfterComma() {
        controller.fakeFileManager.files.insert(filename)
        let cleaned = cleanedUpPath(filename + "(123,456)",
                                    suffix: "",
                                    workingDirectory: workingDirectory)
        XCTAssertEqual(cleaned.path, filename)
        XCTAssertEqual(cleaned.lineNumber, "123")
        XCTAssertEqual(cleaned.columnNumber, "456")
    }

    func testGetFullPathWithParensAndTrailingPunctuationExtractsLineNumber() {
        controller.fakeFileManager.files.insert(filename)
        let cleaned = cleanedUpPath("(\(filename):123.)", workingDirectory: workingDirectory)
        XCTAssertEqual(cleaned.path, filename)
        XCTAssertEqual(cleaned.lineNumber, "123")
    }

    func testGetFullPathWithLineNumberInParensAfterFilename() {
        controller.fakeFileManager.files.insert(filename)
        let cleaned = cleanedUpPath("\(filename)(123):", workingDirectory: workingDirectory)
        XCTAssertEqual(cleaned.path, filename)
        XCTAssertEqual(cleaned.lineNumber, "123")
    }

    func testGetFullPathFailsWithJustStrippedChars() {
        let cleaned = cleanedUpPath("(:123.)", workingDirectory: workingDirectory)
        XCTAssertNil(cleaned.path)
    }

    func testGetFullPathStandardizesDot() {
        let absoluteFilename = "/working/directory/path/to/file"
        controller.fakeFileManager.files.insert(absoluteFilename)
        controller.fakeFileManager.files.insert("/working/directory/./path/to/file")
        let cleaned = cleanedUpPath("./path/to/file", workingDirectory: workingDirectory)
        XCTAssertEqual(cleaned.path, absoluteFilename)
        XCTAssertNil(cleaned.lineNumber)
    }

    func testGetFullPathStandardizesDotDot() {
        let absoluteFilename = "/working/directory/path/to/file"
        controller.fakeFileManager.files.insert(absoluteFilename)
        controller.fakeFileManager.files.insert("/working/directory/blah/../path/to/file")
        let cleaned = cleanedUpPath("../path/to/file", workingDirectory: "/working/directory/blah")
        XCTAssertEqual(cleaned.path, absoluteFilename)
        XCTAssertNil(cleaned.lineNumber)
    }

    private func assertStripsGitDiffPrefix(_ prefix: String,
                                           file: StaticString = #filePath, line: UInt = #line) {
        let relativeFilename = "path/to/file"
        let absoluteFilename = (workingDirectory as NSString).appendingPathComponent(relativeFilename)
        controller.fakeFileManager.files.insert(absoluteFilename)
        let cleaned = cleanedUpPath(prefix + relativeFilename, workingDirectory: workingDirectory)
        XCTAssertEqual(cleaned.path, absoluteFilename, "Failed to strip prefix \(prefix)", file: file, line: line)
        XCTAssertNil(cleaned.lineNumber, file: file, line: line)
    }

    func testGetFullPathStripsLeadingGitDiffPrefixA() {
        assertStripsGitDiffPrefix("a/")
    }

    func testGetFullPathStripsLeadingGitDiffPrefixB() {
        assertStripsGitDiffPrefix("b/")
    }

    func testGetFullPathStripsLeadingGitDiffPrefixI() {
        assertStripsGitDiffPrefix("i/")
    }

    func testGetFullPathStripsLeadingGitDiffPrefixW() {
        assertStripsGitDiffPrefix("w/")
    }

    func testGetFullPathStripsLeadingGitDiffPrefixC() {
        assertStripsGitDiffPrefix("c/")
    }

    func testGetFullPathStripsLeadingGitDiffPrefixO() {
        assertStripsGitDiffPrefix("o/")
    }

    func testGetFullPathRejectsNetworkPaths() {
        let relativeFilename = "path/to/file"
        let absoluteFilename = (workingDirectory as NSString).appendingPathComponent(relativeFilename)
        controller.fakeFileManager.files.insert(absoluteFilename)
        controller.fakeFileManager.networkMountPoints.insert("/working")
        let cleaned = cleanedUpPath(relativeFilename, workingDirectory: workingDirectory)
        XCTAssertNil(cleaned.path)
    }

    func testRandomStuffAfterFileNameNotIdentifiedAsPartOfFile() {
        let relativeFilename = "path/to/file"
        controller.fakeFileManager.files.insert(workingDirectory)
        let absoluteFilename = (workingDirectory as NSString).appendingPathComponent(relativeFilename)
        controller.fakeFileManager.files.insert(absoluteFilename)
        let found = pathOfExistingFile(prefix: "path/to/file:12:34: blah blah blah",
                                       suffix: "raz boom bah",
                                       workingDirectory: workingDirectory,
                                       trimWhitespace: false)
        XCTAssertNil(found.path)
    }

    // MARK: - Open Path

    func testOpenPathRawAction() {
        controller.prefs = [actionKey: rawCommandAction,
                            textKey: "\\1;\\2;\\3;\\4;\\5;\\(test)"]
        let stringThatIsNotAPath = "Prefix X Suffix:1"
        scope.setValue("User Variable", forVariableNamed: "test")
        let escapedPath = (stringThatIsNotAPath as NSString).withEscapedShellCharacters(includingNewlines: true)
        let opened = cleanAndOpen(stringThatIsNotAPath,
                                  substitutions: [pathSubstitutionKey: escapedPath,
                                                  prefixSubstitutionKey: "Prefix",
                                                  suffixSubstitutionKey: "Suffix",
                                                  workingDirectorySubstitutionKey: "/tmp",
                                                  lineNumberKey: "",
                                                  columnNumberKey: ""])
        XCTAssertTrue(opened)
        let expectedScript = "Prefix\\ X\\ Suffix:1;;Prefix;Suffix;/tmp;User Variable"
        XCTAssertEqual(controller.scriptArguments, ["-c", expectedScript])
    }

    func testOpenPathFailsIfFileDoesNotExist() {
        controller.prefs = [actionKey: bestEditorAction]
        let opened = cleanAndOpen("Prefix X Suffix:1",
                                  substitutions: standardSubstitutions(workingDirectory: "/tmp"))
        XCTAssertFalse(opened)
        XCTAssertNil(controller.openedFile)
        XCTAssertNil(controller.openedURL)
        XCTAssertNil(controller.launchedApp)
        XCTAssertNil(controller.scriptArguments)
    }

    func testOpenPathRunsCommandActionForExistingFile() {
        controller.prefs = [actionKey: commandAction, textKey: "Command"]
        controller.fakeFileManager.files.insert(existingFile)
        let opened = cleanAndOpen(existingFile,
                                  substitutions: standardSubstitutions(workingDirectory: "/tmp"))
        XCTAssertTrue(opened)
        XCTAssertEqual(controller.scriptArguments, ["-c", "Command"])
    }

    func testOpenPathRunsCoprocessForExistingFile() {
        controller.prefs = [actionKey: coprocessAction, textKey: "Command"]
        controller.fakeFileManager.files.insert(existingFile)
        let opened = cleanAndOpen(existingFile,
                                  substitutions: standardSubstitutions(workingDirectory: "/tmp"))
        XCTAssertTrue(opened)
        XCTAssertEqual(coprocessCommand, "Command")
    }

    func testOpenPathSendsTextForSendTextAction() {
        controller.prefs = [actionKey: sendTextAction, textKey: "vim \\1"]
        controller.fakeFileManager.files.insert(existingFile)
        let opened = cleanAndOpen(existingFile,
                                  substitutions: standardSubstitutions(workingDirectory: "/tmp"))
        XCTAssertTrue(opened)
        XCTAssertEqual(sentText, "vim /file/that/exists")
        XCTAssertNil(controller.scriptArguments)
    }

    func testOpenPathOpensFileForDirectoryWithURLAction() {
        controller.prefs = [actionKey: urlAction, textKey: "Command"]
        let directory = "/directory"
        controller.fakeFileManager.directories.insert(directory)
        let opened = cleanAndOpen(directory,
                                  substitutions: standardSubstitutions(workingDirectory: "/tmp"))
        XCTAssertTrue(opened)
        XCTAssertEqual(controller.openedFile, directory)
        XCTAssertNil(controller.openedURL)
    }

    func testOpenPathOpensURLWithProperSubstitutions() {
        controller.prefs = [actionKey: urlAction,
                            textKey: "http://foo/?pwd=\\1&line=\\2&prefix=\\3&suffix=\\4&dir=\\5&uservar=\\(test)"]
        controller.fakeFileManager.files.insert("/The Path")
        scope.setValue("User Variable", forVariableNamed: "test")
        let opened = cleanAndOpen("The Path:1",
                                  substitutions: [prefixSubstitutionKey: "The Prefix",
                                                  suffixSubstitutionKey: "The Suffix",
                                                  workingDirectorySubstitutionKey: "/",
                                                  lineNumberKey: "",
                                                  columnNumberKey: ""])
        XCTAssertTrue(opened)
        let expectedURL = URL(string: "http://foo/?pwd=/The%20Path&line=1&prefix=The%20Prefix&suffix=The%20Suffix&dir=/&uservar=User%20Variable")
        XCTAssertEqual(controller.openedURL, expectedURL)
        XCTAssertNil(controller.openedEditor)
    }

    func testOpenPathOpensTextFileInEditorWhenEditorIsDefaultApp() {
        controller.prefs = [actionKey: editorAction, editorKey: macVimIdentifier]
        controller.fakeFileManager.files.insert(existingFile)
        controller.defaultAppIsEditor = true
        let opened = cleanAndOpen(existingFile,
                                  substitutions: standardSubstitutions(workingDirectory: "/"))
        XCTAssertTrue(opened)
        XCTAssertEqual(controller.openedURL,
                       editorURL(scheme: "mvim", path: existingFile, lineNumber: nil))
        XCTAssertEqual(controller.openedEditor, macVimIdentifier)
    }

    // Open a file with a line number in the default app, which happens to be MacVim.
    func testOpenPathOpensTextFileInDefaultAppWithLineNumber() {
        controller.prefs = [actionKey: bestEditorAction]
        controller.fakeFileManager.files.insert(existingFile)
        controller.defaultAppIsEditor = true
        controller.bundleIdForDefaultApp = macVimIdentifier
        let opened = cleanAndOpen(existingFile + ":12",
                                  substitutions: standardSubstitutions(workingDirectory: "/"))
        XCTAssertTrue(opened)
        XCTAssertEqual(controller.openedURL,
                       editorURL(scheme: "mvim", path: existingFile, lineNumber: "12"))
        XCTAssertEqual(controller.openedEditor, macVimIdentifier)
    }

    func testOpenPathOpensTextFileInEditorWithLineNumberWhenEditorIsDefaultApp() {
        controller.prefs = [actionKey: editorAction, editorKey: macVimIdentifier]
        controller.fakeFileManager.files.insert(existingFile)
        controller.defaultAppIsEditor = true
        let opened = cleanAndOpen(existingFile + ":12",
                                  substitutions: standardSubstitutions(workingDirectory: "/"))
        XCTAssertTrue(opened)
        XCTAssertEqual(controller.openedURL,
                       editorURL(scheme: "mvim", path: existingFile, lineNumber: "12"))
        XCTAssertEqual(controller.openedEditor, macVimIdentifier)
    }

    // Editors that are launched as an app with the path (plus line and column)
    // as their argument.
    private func assertLaunchesApp(editor: String,
                                   pathSuffix: String,
                                   defaultAppForThisFile: Bool,
                                   file: StaticString = #filePath, line: UInt = #line) {
        controller.prefs = [actionKey: editorAction, editorKey: editor]
        let pathWithLineNumber = existingFile + pathSuffix
        controller.fakeFileManager.files.insert(existingFile)
        controller.defaultAppIsEditor = false
        if defaultAppForThisFile {
            controller.bundleIdForDefaultApp = editor
        }
        let opened = cleanAndOpen(pathWithLineNumber,
                                  substitutions: standardSubstitutions(workingDirectory: "/"))
        XCTAssertTrue(opened, file: file, line: line)
        XCTAssertEqual(controller.launchedApp, editor, file: file, line: line)
        XCTAssertEqual(controller.launchedAppArg, pathWithLineNumber, file: file, line: line)
        XCTAssertNil(controller.openedURL, file: file, line: line)
    }

    func testOpenPathOpensTextFileAtomEditor() {
        assertLaunchesApp(editor: atomIdentifier, pathSuffix: ":12", defaultAppForThisFile: false)
    }

    func testOpenPathOpensTextFileAtomEditorWhenDefaultAppForThisFile() {
        assertLaunchesApp(editor: atomIdentifier, pathSuffix: ":12", defaultAppForThisFile: true)
    }

    func testOpenPathOpensTextFileVSCodeEditor() {
        assertLaunchesApp(editor: vsCodeIdentifier, pathSuffix: ":12:11", defaultAppForThisFile: false)
    }

    func testOpenPathOpensTextFileVSCodeEditorWhenDefaultAppForThisFile() {
        assertLaunchesApp(editor: vsCodeIdentifier, pathSuffix: ":12:11", defaultAppForThisFile: true)
    }

    func testOpenPathOpensTextFileSublimeText2Editor() {
        assertLaunchesApp(editor: sublimeText2Identifier, pathSuffix: ":12", defaultAppForThisFile: false)
    }

    func testOpenPathOpensTextFileSublimeText3Editor() {
        assertLaunchesApp(editor: sublimeText3Identifier, pathSuffix: ":12", defaultAppForThisFile: false)
    }

    func testOpenPathOpensTextFileSublimeText4Editor() {
        assertLaunchesApp(editor: sublimeText4Identifier, pathSuffix: ":12", defaultAppForThisFile: false)
    }

    // Editors that are opened through a URL scheme.
    private func assertOpensTextFileInEditor(identifier: String,
                                             expectedScheme: String,
                                             file: StaticString = #filePath, line: UInt = #line) {
        controller.prefs = [actionKey: editorAction, editorKey: identifier]
        controller.fakeFileManager.files.insert(existingFile)
        controller.defaultAppIsEditor = false
        let opened = cleanAndOpen(existingFile + ":12",
                                  substitutions: standardSubstitutions(workingDirectory: "/"))
        XCTAssertTrue(opened, file: file, line: line)
        XCTAssertEqual(controller.openedURL,
                       editorURL(scheme: expectedScheme, path: existingFile, lineNumber: "12"),
                       file: file, line: line)
        XCTAssertEqual(controller.openedEditor, identifier, file: file, line: line)
    }

    func testOpenPathOpensTextFileInMacVim() {
        assertOpensTextFileInEditor(identifier: macVimIdentifier, expectedScheme: "mvim")
    }

    func testOpenPathOpensTextFileInTextMate() {
        assertOpensTextFileInEditor(identifier: textmateIdentifier, expectedScheme: "txmt")
    }

    func testOpenPathOpensTextFileInBBEdit() {
        // Sadly, BBEdit uses textmate's scheme. This is intentional.
        assertOpensTextFileInEditor(identifier: bbEditIdentifier, expectedScheme: "txmt")
    }

    // MARK: - Editor URL encoding

    // Opens `path` (with an optional line number) in a URL-scheme editor and
    // returns the components of the URL the controller opened.
    private func editorURLComponents(identifier: String,
                                     path: String,
                                     lineNumber: String?,
                                     file: StaticString = #filePath,
                                     line: UInt = #line) -> URLComponents? {
        controller.prefs = [actionKey: editorAction, editorKey: identifier]
        controller.fakeFileManager.files.insert(path)
        controller.defaultAppIsEditor = false
        let rawFilename = lineNumber.map { path + ":" + $0 } ?? path
        let opened = cleanAndOpen(rawFilename,
                                  substitutions: standardSubstitutions(workingDirectory: "/"))
        XCTAssertTrue(opened, file: file, line: line)
        guard let url = controller.openedURL else {
            XCTFail("No editor URL was opened", file: file, line: line)
            return nil
        }
        XCTAssertEqual(controller.openedEditor, identifier, file: file, line: line)
        return URLComponents(url: url, resolvingAgainstBaseURL: false)
    }

    // The query items of the editor URL, percent-decoded exactly once. That is
    // how MacVim (MMAppController.m, parseOpenURL: splits the query on & and =
    // and calls stringByRemovingPercentEncoding on each half) and TextMate
    // (AppController Documents.mm, handleTxMtURL: same split, decode::url_part
    // on each half) read them. TextMate then strips “file:///” and uses the rest
    // verbatim as the path, so the decoded url item must be the file URL with
    // the raw path, that is “file:///dir with space/x.txt”.
    private func decodedQueryItems(_ components: URLComponents?) -> [URLQueryItem]? {
        return components?.queryItems
    }

    private let fileWithSpace = "/file with space/x.txt"
    private let fileWithAmpersand = "/file&/x.txt"

    func testEditorURLWithLineNumberEncodesSpaceOnce() {
        let components = editorURLComponents(identifier: macVimIdentifier,
                                             path: fileWithSpace,
                                             lineNumber: "12")
        XCTAssertEqual(components?.scheme, "mvim")
        XCTAssertEqual(components?.host, "open")
        XCTAssertEqual(decodedQueryItems(components),
                       [URLQueryItem(name: "url", value: "file://" + fileWithSpace),
                        URLQueryItem(name: "line", value: "12")])
    }

    // Suspected bug: iTermSemanticHistoryController.m
    // -openFile:inEditorWithBundleId:lineNumber:columnNumber: (commit 8d5f938e1)
    // percent-encodes fileURL.absoluteString, which already contains %20 for
    // the space, so the space is double-encoded (%2520) when no line number is
    // present. With a line number the code round-trips through
    // NSURLComponents.queryItems, which decodes once, so that branch is
    // single-encoded. The two branches disagree, and the double-encoded form
    // makes TextMate look for “/file%20with%20space/x.txt”.
    func testEditorURLWithoutLineNumberEncodesSpaceOnce() {
        let components = editorURLComponents(identifier: macVimIdentifier,
                                             path: fileWithSpace,
                                             lineNumber: nil)
        XCTAssertEqual(components?.scheme, "mvim")
        XCTAssertEqual(components?.host, "open")
        XCTExpectFailure("iTermSemanticHistoryController.m openFile:inEditorWithBundleId: double-encodes the file URL when there is no line number (%2520 for a space)") {
            XCTAssertEqual(decodedQueryItems(components),
                           [URLQueryItem(name: "url", value: "file://" + fileWithSpace)])
        }
    }

    // Same root cause as testEditorURLWithoutLineNumberEncodesSpaceOnce, seen
    // from the editor that actually breaks: TextMate strips “file:///” and uses
    // the remainder as the path without decoding it again.
    func testTextMateURLWithoutLineNumberEncodesSpaceOnce() {
        let components = editorURLComponents(identifier: textmateIdentifier,
                                             path: fileWithSpace,
                                             lineNumber: nil)
        XCTAssertEqual(components?.scheme, "txmt")
        XCTAssertEqual(components?.host, "open")
        XCTExpectFailure("iTermSemanticHistoryController.m openFile:inEditorWithBundleId: double-encodes the file URL when there is no line number (%2520 for a space)") {
            XCTAssertEqual(decodedQueryItems(components),
                           [URLQueryItem(name: "url", value: "file://" + fileWithSpace)])
        }
    }

    // Suspected bug: iTermSemanticHistoryController.m
    // -openFile:inEditorWithBundleId:lineNumber:columnNumber: (commit 8d5f938e1)
    // builds the url query value with NSCharacterSet.URLQueryAllowedCharacterSet
    // (minus “/”), and that set allows “&” and “=”, so an ampersand in the path
    // is emitted raw and splits the query: url=file:///file&/x.txt&line=12
    // is read by every editor as url=file:///file plus a junk “/x.txt” item.
    func testEditorURLWithLineNumberEncodesAmpersand() {
        let components = editorURLComponents(identifier: macVimIdentifier,
                                             path: fileWithAmpersand,
                                             lineNumber: "12")
        XCTAssertEqual(components?.scheme, "mvim")
        XCTAssertEqual(components?.host, "open")
        XCTExpectFailure("iTermSemanticHistoryController.m openFile:inEditorWithBundleId: leaves & unencoded in the url query item, splitting the query") {
            XCTAssertEqual(decodedQueryItems(components),
                           [URLQueryItem(name: "url", value: "file://" + fileWithAmpersand),
                            URLQueryItem(name: "line", value: "12")])
        }
    }

    // Same root cause as testEditorURLWithLineNumberEncodesAmpersand; the
    // no-line-number branch uses the same character set.
    func testEditorURLWithoutLineNumberEncodesAmpersand() {
        let components = editorURLComponents(identifier: macVimIdentifier,
                                             path: fileWithAmpersand,
                                             lineNumber: nil)
        XCTAssertEqual(components?.scheme, "mvim")
        XCTAssertEqual(components?.host, "open")
        XCTExpectFailure("iTermSemanticHistoryController.m openFile:inEditorWithBundleId: leaves & unencoded in the url query item, splitting the query") {
            XCTAssertEqual(decodedQueryItems(components),
                           [URLQueryItem(name: "url", value: "file://" + fileWithAmpersand)])
        }
    }

    // Note there is no test for textmate 2 because it is not directly selectable from the menu and it
    // uses the same scheme as textmate, even though its identifier is different.

    // MARK: - Path Of Existing File

    private let searchDirectory = "/directory"

    private func addFile(_ relativeFilename: String, in directory: String) {
        controller.fakeFileManager.files.insert((directory as NSString).appendingPathComponent(relativeFilename))
        controller.fakeFileManager.directories.insert(directory)
    }

    func testPathOfExistingFileLocal() {
        let relativeFilename = "five six seven eight"
        addFile(relativeFilename, in: searchDirectory)
        let found = pathOfExistingFile(prefix: "one two three four five six ",
                                       suffix: "seven eight nine ten eleven",
                                       workingDirectory: searchDirectory,
                                       trimWhitespace: false)
        XCTAssertEqual(found.path, relativeFilename)
        XCTAssertEqual(found.prefixChars, "five six ".count)
    }

    // This test simulates what happens if you select a full line (including hard eol) and do Open Selection.
    // The prefix will end in whitespace (maybe) and a newline. This test uses whitespace trimming.
    func testPathOfExistingFileIgnoringLeadingAndTrailingWhitespaceAndNewlines() {
        let relativeFilename = "five six seven eight"
        addFile(relativeFilename, in: searchDirectory)
        let found = pathOfExistingFile(prefix: "five six seven eight \r\n",
                                       suffix: "",
                                       workingDirectory: searchDirectory,
                                       trimWhitespace: true)
        XCTAssertEqual(found.path, relativeFilename)
        XCTAssertEqual(found.prefixChars, "five six seven eight".count)
        XCTAssertEqual(found.suffixChars, 0)
    }

    func testPathOfExistingFileRemovesParens() {
        addFile("five six seven eight", in: searchDirectory)
        let found = pathOfExistingFile(prefix: "one two three four (five six ",
                                       suffix: "seven eight) nine ten eleven",
                                       workingDirectory: searchDirectory,
                                       trimWhitespace: false)
        XCTAssertEqual(found.path, "five six seven eight")
        XCTAssertEqual(found.prefixChars, "five six ".count)
        XCTAssertEqual(found.suffixChars, "seven eight".count)
    }

    func testPathOfExistingFileSupportsLineNumberAndColumnNumber() {
        addFile("five six seven eight", in: searchDirectory)
        let found = pathOfExistingFile(prefix: "one two three four five six ",
                                       suffix: "seven eight:123:456 nine ten eleven",
                                       workingDirectory: searchDirectory,
                                       trimWhitespace: false)
        XCTAssertEqual(found.path, "five six seven eight:123:456")
        XCTAssertEqual(found.prefixChars, "five six ".count)
        XCTAssertEqual(found.suffixChars, "seven eight:123:456".count)
    }

    func testPathOfExistingFileSupportsLineNumberAndColumnNumberInParens() {
        addFile("file.txt", in: searchDirectory)
        let found = pathOfExistingFile(prefix: "file.txt(10",
                                       suffix: ", 10)",
                                       workingDirectory: searchDirectory,
                                       trimWhitespace: false)
        XCTAssertEqual(found.path, "file.txt(10, 10)")
        XCTAssertEqual(found.prefixChars, "file.txt(10".count)
        XCTAssertEqual(found.suffixChars, ", 10)".count)
    }

    func testPathOfExistingFileFindsColumnAndLineNumber() {
        addFile("file.txt", in: searchDirectory)
        let found = pathOfExistingFile(prefix: "file.txt",
                                       suffix: "(10, 10)",
                                       workingDirectory: searchDirectory,
                                       trimWhitespace: false)
        XCTAssertEqual(found.path, "file.txt(10, 10)")
        XCTAssertEqual(found.prefixChars, "file.txt".count)
        XCTAssertEqual(found.suffixChars, "(10, 10)".count)
    }

    func testPathOfExistingFileSupportsLineNumberAndColumnNumberAndParensAndNonspaceSeparators() {
        addFile("five.six\tseven eight", in: searchDirectory)
        let found = pathOfExistingFile(prefix: "one two three four (five.six\t",
                                       suffix: "seven eight:123:456). nine ten eleven",
                                       workingDirectory: searchDirectory,
                                       trimWhitespace: false)
        XCTAssertEqual(found.path, "five.six\tseven eight:123:456")
        XCTAssertEqual(found.prefixChars, "five.six\t".count)
        XCTAssertEqual(found.suffixChars, "seven eight:123:456".count)
    }

    func testPathOfExistingFileIgnoresFilesOnNetworkVolumes() {
        addFile("five six seven eight", in: searchDirectory)
        controller.fakeFileManager.networkMountPoints.insert(searchDirectory)
        let found = pathOfExistingFile(prefix: "one two three four five six ",
                                       suffix: "seven eight nine ten eleven",
                                       workingDirectory: searchDirectory,
                                       trimWhitespace: false)
        XCTAssertNil(found.path)
    }

    // Regression test for issue 3841.
    func testLeadingWhitespaceIgnoredWithoutTrimming() {
        addFile("test.txt", in: searchDirectory)
        let found = pathOfExistingFile(prefix: "     ",
                                       suffix: "  test.txt",
                                       workingDirectory: searchDirectory,
                                       trimWhitespace: false)
        XCTAssertNil(found.path)
    }

    // Regression test for issue 4927
    func testPathOfExistingFileEscapedCharacters() {
        let relativeFilename = "five six seven eight"
        addFile(relativeFilename, in: searchDirectory)
        let found = pathOfExistingFile(prefix: "one two three four five\\ six\\ ",
                                       suffix: "seven\\ eight nine ten eleven",
                                       workingDirectory: searchDirectory,
                                       trimWhitespace: false)
        XCTAssertEqual(found.path, relativeFilename)
        XCTAssertEqual(found.prefixChars, "five\\ six\\ ".count)
        XCTAssertEqual(found.suffixChars, "seven\\ eight".count)
    }

    // Regression test for issue 7635: the path finder keeps the line number
    // but drops the text after it.
    func testColonTextAfterLineNumberIsNotPartOfPath() {
        addFile("file.rb", in: searchDirectory)
        let found = pathOfExistingFile(prefix: "file",
                                       suffix: ".rb:7:in `new`",
                                       workingDirectory: searchDirectory,
                                       trimWhitespace: false)
        XCTAssertEqual(found.path, "file.rb:7")
    }

    // Regression test for issue 7635: cleaning up the found path separates the
    // line number from the filename.
    func testColonTextAfterLineNumberCleansUpToFilenameAndLine() {
        addFile("file.rb", in: searchDirectory)
        let cleaned = cleanedUpPath("file.rb:7", workingDirectory: searchDirectory)
        XCTAssertEqual(cleaned.path, "/directory/file.rb")
        XCTAssertEqual(cleaned.lineNumber, "7")
        XCTAssertNil(cleaned.columnNumber)
    }

    // Regression test for issue 7760
    func testIssue7760() {
        controller.prefs = [actionKey: commandAction,
                            textKey: "/bin/bash -l -c \"cd \\5 && env /usr/local/bin/atom \\1:2\""]
        let path = "/Users/kolbrich/Projects/quill/tmp/failure-sandbox_spec-246-screenshot.png"
        controller.fakeFileManager.files.insert(path)
        controller.fakeFileManager.directories.insert("/Users/kolbrich/Projects/quill")

        let opened = openPath(path,
                              rawFilename: path,
                              substitutions: [pathSubstitutionKey: path,
                                              prefixSubstitutionKey: "Saving\\ screenshot\\ to\\ /Users/kolbrich/Projects/quill/tmp/failure-",
                                              suffixSubstitutionKey: "sandbox_spec-246-screenshot.png\\",
                                              workingDirectorySubstitutionKey: "/Users/kolbrich/Projects/quill",
                                              lineNumberKey: "",
                                              columnNumberKey: ""],
                              lineNumber: "",
                              columnNumber: "")
        XCTAssertTrue(opened)
        let expectedScript = "/bin/bash -l -c \"cd /Users/kolbrich/Projects/quill && env /usr/local/bin/atom /Users/kolbrich/Projects/quill/tmp/failure-sandbox_spec-246-screenshot.png:2\""
        XCTAssertEqual(controller.scriptArguments, ["-c", expectedScript])
    }
}
