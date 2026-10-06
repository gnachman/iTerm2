//
//  iTermNonTextPasteHelperTests.swift
//  iTerm2 ModernTests
//
//  The paste-options dialogs are permanently silenceable, and iTermWarning remembers a silenced
//  choice as an iTermWarningSelection under the warning's identifier. Both halves of that need
//  pinning. The identifier is derived from the options offered, so two pastes share a saved answer
//  only when they present the same choices: without that, "Paste as Text" saved for a local text
//  file and "Paste Path" saved for a folder overwrite each other under one key, and only the shape
//  answered last stays silenced. The selections are stable per action, so a saved answer survives a
//  button reorder and fails to resolve rather than firing a different action.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermNonTextPasteHelperTests: XCTestCase {
    private typealias FileAction = iTermNonTextPasteHelper.FilePasteAction
    private typealias ImageAction = iTermNonTextPasteHelper.ImagePasteAction
    private typealias FileDestination = iTermNonTextPasteHelper.FilePasteDestination

    private struct Dialog<Action: Hashable> {
        var name: String
        var actions: [Action]
        var identifier: String
        // The options the identifier is meant to name, restated here so that changing the exclusion
        // rule in the helper without revisiting it fails rather than passing quietly.
        var options: Set<Action>
    }

    // Every button list the file dialog can present.
    private var fileDialogs: [Dialog<FileAction>] {
        var result = [Dialog<FileAction>]()
        for singleFile in [true, false] {
            for destination in [FileDestination.local, .verifiedRemote, .unverifiedRemote] {
                for isDirectory in [true, false] {
                    for canPasteAsText in [true, false] {
                        // handleFilePaste only reports these for a single regular file.
                        if !singleFile && (isDirectory || canPasteAsText) {
                            continue
                        }
                        if isDirectory && canPasteAsText {
                            continue
                        }
                        let actions = iTermNonTextPasteHelper.fileActions(singleFile: singleFile,
                                                                          destination: destination,
                                                                          isDirectory: isDirectory,
                                                                          canPasteAsText: canPasteAsText)
                        result.append(
                            Dialog(name: "singleFile=\(singleFile) destination=\(destination) isDirectory=\(isDirectory) canPasteAsText=\(canPasteAsText)",
                                   actions: actions,
                                   identifier: iTermNonTextPasteHelper.fileWarningIdentifier(for: actions),
                                   options: Set(actions.filter { $0 != .cancel && $0 != .pasteAsText })))
                    }
                }
            }
        }
        return result
    }

    // Every button list the image dialog can present.
    private var imageDialogs: [Dialog<ImageAction>] {
        var result = [Dialog<ImageAction>]()
        for hasFileExtension in [true, false] {
            for destination in [FileDestination.local, .verifiedRemote, .unverifiedRemote] {
                let actions = iTermNonTextPasteHelper.imageActions(hasFileExtension: hasFileExtension,
                                                                   destination: destination)
                result.append(
                    Dialog(name: "hasFileExtension=\(hasFileExtension) destination=\(destination)",
                           actions: actions,
                           identifier: iTermNonTextPasteHelper.imageWarningIdentifier(for: actions),
                           options: Set(actions.filter { $0 != .cancel })))
            }
        }
        return result
    }

    // MARK: - The identifier names the option set

    // Two dialogs share a saved answer exactly when they offer the same options: never more (which
    // would let one overwrite the other) and never less (which would ask again needlessly).
    private func checkIdentifierMatchesOptions<Action>(_ dialogs: [Dialog<Action>]) {
        for a in dialogs {
            for b in dialogs {
                XCTAssertEqual(a.identifier == b.identifier, a.options == b.options,
                               "[\(a.name)] -> \(a.identifier) and [\(b.name)] -> \(b.identifier) disagree with their option sets \(a.options) and \(b.options)")
            }
        }
    }

    func testFileIdentifierNamesTheOptionSet() {
        checkIdentifierMatchesOptions(fileDialogs)
    }

    func testImageIdentifierNamesTheOptionSet() {
        checkIdentifierMatchesOptions(imageDialogs)
    }

    // Order is a display decision. Reordering the buttons must not reset every saved answer;
    // actionToSelectionMap is what carries the choice across a reorder.
    func testFileIdentifierIgnoresOrder() {
        for dialog in fileDialogs {
            let shuffled = dialog.actions.reversed().map { $0 }
            XCTAssertEqual(iTermNonTextPasteHelper.fileWarningIdentifier(for: shuffled),
                           dialog.identifier,
                           "Reversing the buttons changed the identifier for [\(dialog.name)]")
        }
    }

    func testImageIdentifierIgnoresOrder() {
        for dialog in imageDialogs {
            let shuffled = dialog.actions.reversed().map { $0 }
            XCTAssertEqual(iTermNonTextPasteHelper.imageWarningIdentifier(for: shuffled),
                           dialog.identifier,
                           "Reversing the buttons changed the identifier for [\(dialog.name)]")
        }
    }

    // Stripping non-alphanumerics from the labels must not make two actions collapse onto one
    // token, which would make two different option sets share a key.
    func testFileActionTokensAreUnique() {
        let participating: [FileAction] = [.pastePath, .pastePaths, .pasteBase64,
                                           .pasteBase64Archive, .upload, .uploadAndPastePath,
                                           .uploadAndPastePaths]
        let identifiers = participating.map {
            iTermNonTextPasteHelper.fileWarningIdentifier(for: [$0, .cancel])
        }
        XCTAssertEqual(Set(identifiers).count, participating.count,
                       "Two file actions produce the same identifier token: \(identifiers)")
    }

    func testImageActionTokensAreUnique() {
        let participating: [ImageAction] = [.saveTempAndPastePath, .pasteBase64,
                                            .upload, .uploadAndPastePath]
        let identifiers = participating.map {
            iTermNonTextPasteHelper.imageWarningIdentifier(for: [$0, .cancel])
        }
        XCTAssertEqual(Set(identifiers).count, participating.count,
                       "Two image actions produce the same identifier token: \(identifiers)")
    }

    // The key goes in a plist, and must stay local-only (the NoSync convention) and free of the
    // punctuation and localized prose that the button labels carry.
    func testIdentifiersAreWellFormedDefaultsKeys() {
        let identifiers = fileDialogs.map { $0.identifier } + imageDialogs.map { $0.identifier }
        for identifier in identifiers {
            XCTAssertTrue(identifier.hasPrefix("NoSync"), "\(identifier) is not a NoSync key")
            XCTAssertTrue(identifier.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") },
                          "\(identifier) contains characters that do not belong in a defaults key")
        }
    }

    // MARK: - The selections are stable per action

    // Two actions offered together must never report the same selection, or the completion handler
    // would run whichever came first rather than the button the user pressed.
    func testFileActionsInOneDialogHaveDistinctSelections() {
        for dialog in fileDialogs {
            let selections = dialog.actions.map { $0.selection.rawValue }
            XCTAssertEqual(Set(selections).count, selections.count,
                           "Duplicate selection in [\(dialog.name)]: \(dialog.actions.map { $0.rawValue })")
        }
    }

    func testImageActionsInOneDialogHaveDistinctSelections() {
        for dialog in imageDialogs {
            let selections = dialog.actions.map { $0.selection.rawValue }
            XCTAssertEqual(Set(selections).count, selections.count,
                           "Duplicate selection in [\(dialog.name)]: \(dialog.actions.map { $0.rawValue })")
        }
    }

    // iTermWarning only defines selections 0 through 6; anything else is kItermWarningSelectionError.
    func testSelectionsAreRepresentable() {
        let valid = Set(0...6)
        for action in [FileAction.pastePath, .pastePaths, .pasteBase64, .pasteBase64Archive,
                       .pasteAsText, .upload, .uploadAndPastePath, .uploadAndPastePaths, .cancel] {
            XCTAssertTrue(valid.contains(action.selection.rawValue),
                          "\(action.rawValue) has out-of-range selection \(action.selection.rawValue)")
        }
        for action in [ImageAction.saveTempAndPastePath, .pasteBase64, .upload,
                       .uploadAndPastePath, .cancel] {
            XCTAssertTrue(valid.contains(action.selection.rawValue),
                          "\(action.rawValue) has out-of-range selection \(action.selection.rawValue)")
        }
    }

    // The one place a saved answer still meets a list that omits its action: pasteAsText is left out
    // of the identifier, so a text file and a binary file share a key. The saved selection must fail
    // to resolve, not land on whatever moved into position 2.
    func testRememberedPasteAsTextDoesNotResolveForABinaryFile() {
        let text = iTermNonTextPasteHelper.fileActions(singleFile: true,
                                                       destination: .local,
                                                       isDirectory: false,
                                                       canPasteAsText: true)
        let binary = iTermNonTextPasteHelper.fileActions(singleFile: true,
                                                         destination: .local,
                                                         isDirectory: false,
                                                         canPasteAsText: false)
        XCTAssertEqual(iTermNonTextPasteHelper.fileWarningIdentifier(for: text),
                       iTermNonTextPasteHelper.fileWarningIdentifier(for: binary),
                       "A text file and a binary file should share one memory")
        XCTAssertTrue(text.contains(.pasteAsText))
        XCTAssertNil(binary.first { $0.selection == FileAction.pasteAsText.selection },
                     "A remembered Paste as Text resolves to something in the binary-file dialog")
    }

    // MARK: - The original regressions

    // "Paste Path" remembered on a local file, then a paste into a session connected to a remote
    // host, where the first button is "Upload and Paste Path". Different options, so different keys.
    func testRememberedPastePathDoesNotBecomeAnUpload() {
        let local = iTermNonTextPasteHelper.fileActions(singleFile: true,
                                                        destination: .local,
                                                        isDirectory: false,
                                                        canPasteAsText: true)
        let remote = iTermNonTextPasteHelper.fileActions(singleFile: true,
                                                         destination: .verifiedRemote,
                                                         isDirectory: false,
                                                         canPasteAsText: true)
        XCTAssertEqual(local.first, .pastePath)
        XCTAssertEqual(remote.first, .uploadAndPastePath)
        XCTAssertNotEqual(iTermNonTextPasteHelper.fileWarningIdentifier(for: local),
                          iTermNonTextPasteHelper.fileWarningIdentifier(for: remote),
                          "A local file and a remote file share a saved answer")
        XCTAssertNil(remote.first { $0.selection == FileAction.pastePath.selection },
                     "A remembered Paste Path resolves to something in the remote dialog")
    }

    // Paste as Text types the local file's decoded contents into the tty, exactly as Paste
    // Base64-Encoded Contents types an encoding of them. Neither depends on where the far end of
    // the tty is, so a session connected to a remote host is offered both.
    func testPasteAsTextIsOfferedOnARemoteHost() {
        let remoteText = iTermNonTextPasteHelper.fileActions(singleFile: true,
                                                             destination: .verifiedRemote,
                                                             isDirectory: false,
                                                             canPasteAsText: true)
        XCTAssertEqual(remoteText, [.uploadAndPastePath, .upload, .pasteBase64, .pasteAsText, .cancel])

        // Still gated on the file being text, and still absent for a folder.
        let remoteBinary = iTermNonTextPasteHelper.fileActions(singleFile: true,
                                                               destination: .verifiedRemote,
                                                               isDirectory: false,
                                                               canPasteAsText: false)
        XCTAssertEqual(remoteBinary, [.uploadAndPastePath, .upload, .pasteBase64, .cancel])
        let remoteFolder = iTermNonTextPasteHelper.fileActions(singleFile: true,
                                                               destination: .verifiedRemote,
                                                               isDirectory: true,
                                                               canPasteAsText: false)
        XCTAssertFalse(remoteFolder.contains(.pasteAsText))

        // Paste Path stays local-only: the local path names nothing on the far host.
        XCTAssertFalse(remoteText.contains(.pastePath))
    }

    // One file and several follow the same rule on a remote host: the local path is not offered,
    // because it names nothing there, and an upload-and-paste replaces it.
    func testLocalPathsAreNotOfferedOnARemoteHost() {
        let remoteMany = iTermNonTextPasteHelper.fileActions(singleFile: false,
                                                             destination: .verifiedRemote,
                                                             isDirectory: false,
                                                             canPasteAsText: false)
        XCTAssertEqual(remoteMany, [.uploadAndPastePaths, .upload, .cancel])
        XCTAssertFalse(remoteMany.contains(.pastePaths))

        let remoteOne = iTermNonTextPasteHelper.fileActions(singleFile: true,
                                                            destination: .verifiedRemote,
                                                            isDirectory: false,
                                                            canPasteAsText: false)
        XCTAssertFalse(remoteOne.contains(.pastePath))
        XCTAssertTrue(remoteOne.contains(.uploadAndPastePath))

        // Locally the paths are what you want, and there is nowhere to upload to.
        let localMany = iTermNonTextPasteHelper.fileActions(singleFile: false,
                                                            destination: .local,
                                                            isDirectory: false,
                                                            canPasteAsText: false)
        XCTAssertEqual(localMany, [.pastePaths, .cancel])
    }

    // Likewise for a folder: the second button changes meaning between a file and a folder.
    func testRememberedPasteBase64DoesNotBecomeAnArchive() {
        let file = iTermNonTextPasteHelper.fileActions(singleFile: true,
                                                       destination: .local,
                                                       isDirectory: false,
                                                       canPasteAsText: false)
        let folder = iTermNonTextPasteHelper.fileActions(singleFile: true,
                                                         destination: .local,
                                                         isDirectory: true,
                                                         canPasteAsText: false)
        XCTAssertEqual(file, [.pastePath, .pasteBase64, .cancel])
        XCTAssertEqual(folder, [.pastePath, .pasteBase64Archive, .cancel])
        XCTAssertNotEqual(iTermNonTextPasteHelper.fileWarningIdentifier(for: file),
                          iTermNonTextPasteHelper.fileWarningIdentifier(for: folder),
                          "A file and a folder share a saved answer")
        XCTAssertNotEqual(FileAction.pasteBase64.selection, FileAction.pasteBase64Archive.selection)
    }
    // MARK: - Unverified remote (issue 13117)

    // A session judged remote only by hostname may really be local (a shell whose $HOST went stale
    // sends a tokenless OSC 7 naming a host we don't recognize). The upload actions stay, but the
    // local path is offered too so a wrong verdict doesn't leave the user with no way to paste it.
    func testUnverifiedRemoteOffersLocalPathAfterUploads() {
        let text = iTermNonTextPasteHelper.fileActions(singleFile: true,
                                                       destination: .unverifiedRemote,
                                                       isDirectory: false,
                                                       canPasteAsText: true)
        XCTAssertEqual(text, [.uploadAndPastePath, .upload, .pastePath, .pasteBase64, .pasteAsText, .cancel])

        let binary = iTermNonTextPasteHelper.fileActions(singleFile: true,
                                                         destination: .unverifiedRemote,
                                                         isDirectory: false,
                                                         canPasteAsText: false)
        XCTAssertEqual(binary, [.uploadAndPastePath, .upload, .pastePath, .pasteBase64, .cancel])

        let folder = iTermNonTextPasteHelper.fileActions(singleFile: true,
                                                         destination: .unverifiedRemote,
                                                         isDirectory: true,
                                                         canPasteAsText: false)
        XCTAssertEqual(folder, [.upload, .pastePath, .pasteBase64Archive, .cancel])

        let many = iTermNonTextPasteHelper.fileActions(singleFile: false,
                                                       destination: .unverifiedRemote,
                                                       isDirectory: false,
                                                       canPasteAsText: false)
        XCTAssertEqual(many, [.uploadAndPastePaths, .upload, .pastePaths, .cancel])
    }

    // The first button is the default, so Return must still upload when the guess is right and the
    // host really is remote. The escape hatch is never the default.
    func testUnverifiedRemoteDefaultIsStillAnUpload() {
        for singleFile in [true, false] {
            for isDirectory in singleFile ? [true, false] : [false] {
                let actions = iTermNonTextPasteHelper.fileActions(singleFile: singleFile,
                                                                  destination: .unverifiedRemote,
                                                                  isDirectory: isDirectory,
                                                                  canPasteAsText: false)
                XCTAssertTrue([FileAction.uploadAndPastePath, .uploadAndPastePaths, .upload].contains(actions.first!),
                              "singleFile=\(singleFile) isDirectory=\(isDirectory) defaults to \(actions.first!)")
            }
        }
    }

    // Proven remote (ssh integration, or a machineID token that doesn't match ours): the local path
    // names nothing there, so it isn't offered. Unchanged from before the escape hatch.
    func testVerifiedRemoteDoesNotOfferLocalPath() {
        let one = iTermNonTextPasteHelper.fileActions(singleFile: true,
                                                      destination: .verifiedRemote,
                                                      isDirectory: false,
                                                      canPasteAsText: true)
        XCTAssertEqual(one, [.uploadAndPastePath, .upload, .pasteBase64, .pasteAsText, .cancel])
        let many = iTermNonTextPasteHelper.fileActions(singleFile: false,
                                                       destination: .verifiedRemote,
                                                       isDirectory: false,
                                                       canPasteAsText: false)
        XCTAssertEqual(many, [.uploadAndPastePaths, .upload, .cancel])
    }

    // Someone stuck in a misdetected local tab may tell the unverified dialog to always Paste Path.
    // That answer must not carry over to an ssh integration session, where it would silently paste
    // local paths into a remote shell, nor to the local dialog, which offers different choices.
    func testRememberedPastePathInUnverifiedDialogDoesNotLeak() {
        let unverified = iTermNonTextPasteHelper.fileActions(singleFile: true,
                                                             destination: .unverifiedRemote,
                                                             isDirectory: false,
                                                             canPasteAsText: false)
        let verified = iTermNonTextPasteHelper.fileActions(singleFile: true,
                                                           destination: .verifiedRemote,
                                                           isDirectory: false,
                                                           canPasteAsText: false)
        let local = iTermNonTextPasteHelper.fileActions(singleFile: true,
                                                        destination: .local,
                                                        isDirectory: false,
                                                        canPasteAsText: false)
        let unverifiedKey = iTermNonTextPasteHelper.fileWarningIdentifier(for: unverified)
        XCTAssertNotEqual(unverifiedKey, iTermNonTextPasteHelper.fileWarningIdentifier(for: verified))
        XCTAssertNotEqual(unverifiedKey, iTermNonTextPasteHelper.fileWarningIdentifier(for: local))
        XCTAssertNil(verified.first { $0.selection == FileAction.pastePath.selection },
                     "A remembered Paste Path resolves to something in the verified-remote dialog")
    }
    // Image paste follows the same rule as a file: saving to a local temp file and pasting its
    // path is the way out when remoteness is only a guess, offered after the uploads so Return
    // still uploads.
    func testImageUnverifiedRemoteOffersLocalSaveAfterUploads() {
        XCTAssertEqual(iTermNonTextPasteHelper.imageActions(hasFileExtension: true, destination: .unverifiedRemote),
                       [.uploadAndPastePath, .upload, .saveTempAndPastePath, .pasteBase64, .cancel])
        XCTAssertEqual(iTermNonTextPasteHelper.imageActions(hasFileExtension: true, destination: .verifiedRemote),
                       [.uploadAndPastePath, .upload, .pasteBase64, .cancel])
        XCTAssertEqual(iTermNonTextPasteHelper.imageActions(hasFileExtension: true, destination: .local),
                       [.saveTempAndPastePath, .pasteBase64, .cancel])
    }

    // Without a known type there's nothing to name a file by, so only Base64 is offered wherever
    // the session is.
    func testImageWithoutExtensionIgnoresDestination() {
        for destination in [FileDestination.local, .verifiedRemote, .unverifiedRemote] {
            XCTAssertEqual(iTermNonTextPasteHelper.imageActions(hasFileExtension: false, destination: destination),
                           [.pasteBase64, .cancel])
        }
    }

    // A Save to Temp File answer remembered in the unverified dialog must not apply in a session
    // proven remote, where it would paste a path that names nothing there.
    func testRememberedSaveTempInUnverifiedImageDialogDoesNotLeak() {
        let unverified = iTermNonTextPasteHelper.imageActions(hasFileExtension: true, destination: .unverifiedRemote)
        let verified = iTermNonTextPasteHelper.imageActions(hasFileExtension: true, destination: .verifiedRemote)
        let local = iTermNonTextPasteHelper.imageActions(hasFileExtension: true, destination: .local)
        let unverifiedKey = iTermNonTextPasteHelper.imageWarningIdentifier(for: unverified)
        XCTAssertNotEqual(unverifiedKey, iTermNonTextPasteHelper.imageWarningIdentifier(for: verified))
        XCTAssertNotEqual(unverifiedKey, iTermNonTextPasteHelper.imageWarningIdentifier(for: local))
        XCTAssertNil(verified.first { $0.selection == ImageAction.saveTempAndPastePath.selection })
    }
}
