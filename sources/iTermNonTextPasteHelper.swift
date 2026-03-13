//
//  iTermNonTextPasteHelper.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/9/26.
//

import AppKit
import UniformTypeIdentifiers

@objc(iTermNonTextPasteHelperDelegate)
protocol iTermNonTextPasteHelperDelegate: AnyObject {
    func nonTextPasteHelper(_ sender: iTermNonTextPasteHelper, pasteString string: String)
    func nonTextPasteHelperWindow(_ sender: iTermNonTextPasteHelper) -> NSWindow?
    func nonTextPasteHelperCanUpload(_ sender: iTermNonTextPasteHelper) -> Bool
    func nonTextPasteHelper(_ sender: iTermNonTextPasteHelper, uploadFiles paths: [String])
    func nonTextPasteHelper(_ sender: iTermNonTextPasteHelper, uploadFileAndPastePath path: String)
}

@objc(iTermNonTextPasteHelper)
class iTermNonTextPasteHelper: NSObject {
    @objc weak var delegate: iTermNonTextPasteHelperDelegate?

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    @objc static func pasteboardHasNonTextContent() -> Bool {
        let pb = NSPasteboard.general
        return pb.hasFileURLs() || pb.hasRawImageData()
    }

    @objc func pasteNonTextContent() -> Bool {
        DLog("pasteNonTextContent called")
        let pb = NSPasteboard.general
        if pb.hasFileURLs() {
            guard let paths = pb.filePaths(), !paths.isEmpty else {
                DLog("hasFileURLs but no paths found")
                return false
            }
            DLog("Handling file paste with \(paths.count) paths")
            return handleFilePaste(paths)
        } else if pb.hasRawImageData() {
            guard let imageData = pb.rawImageData() else {
                DLog("hasRawImageData but rawImageData() returned nil")
                return false
            }
            // Try to determine the file extension, but proceed even if we can't
            var fileExtension: String? = nil
            if let utType = pb.rawImageDataUTType(),
               let type = UTType(utType) {
                fileExtension = type.preferredFilenameExtension
            }
            DLog("Handling image data paste: \(imageData.count) bytes, extension=\(fileExtension ?? "unknown")")
            return handleImageDataPaste(imageData: imageData, fileExtension: fileExtension)
        }
        DLog("No non-text content found on pasteboard")
        return false
    }

    @objc func showPasteOptionsForFiles(_ files: [String]) {
        _ = handleFilePaste(files)
    }

    private enum FilePasteAction: String {
        case pastePath = "Paste Path"
        case pastePaths = "Paste Paths"
        case pasteBase64 = "Paste Base64-Encoded Contents"
        case pasteBase64Archive = "Paste Base64-Encoded Archive (tar.gz)"
        case pasteAsText = "Paste as Text"
        case upload = "Upload"
        case uploadAndPastePath = "Upload and Paste Path"
        case cancel = "Cancel"
    }

    private func handleFilePaste(_ paths: [String]) -> Bool {
        guard !paths.isEmpty else {
            return false
        }

        // Verify files exist
        let existingPaths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        if existingPaths.isEmpty {
            showError("The copied file no longer exists.")
            return true
        }
        if existingPaths.count < paths.count {
            let missing = paths.count - existingPaths.count
            showError("\(missing) of \(paths.count) files no longer exist. Proceeding with remaining files.")
        }

        let singleFile = existingPaths.count == 1
        let canUpload = delegate?.nonTextPasteHelperCanUpload(self) ?? false
        let isDirectory = singleFile && isDirectoryPath(existingPaths.first!)
        let canPasteAsText = singleFile && !isDirectory && firstFileIsValidUTF8(existingPaths)

        DLog("handleFilePaste: singleFile=\(singleFile) canUpload=\(canUpload) isDirectory=\(isDirectory) canPasteAsText=\(canPasteAsText)")

        // Build actions list and track what each index means
        var actions = [FilePasteAction]()
        if singleFile {
            if canUpload {
                // Remote host: offer upload options and base64
                if !isDirectory {
                    actions.append(.uploadAndPastePath)
                }
                actions.append(.upload)
                if isDirectory {
                    actions.append(.pasteBase64Archive)
                } else {
                    actions.append(.pasteBase64)
                }
            } else {
                // Local host: offer path and base64 options
                actions.append(.pastePath)
                if isDirectory {
                    actions.append(.pasteBase64Archive)
                } else {
                    actions.append(.pasteBase64)
                    if canPasteAsText {
                        actions.append(.pasteAsText)
                    }
                }
            }
        } else {
            // Multiple files
            if canUpload {
                actions.append(.upload)
            }
            actions.append(.pastePaths)
        }
        actions.append(.cancel)

        DLog("handleFilePaste: actions=\(actions.map { $0.rawValue })")

        // Build description of files for the dialog
        let fileDescription = descriptionForFiles(existingPaths, isDirectory: isDirectory)

        let warning = iTermWarning()
        warning.title = "How would you like to paste \(fileDescription)?"
        warning.actionLabels = actions.map { $0.rawValue }
        warning.identifier = singleFile ? "NoSyncPasteNonTextFile" : "NoSyncPasteNonTextFiles"
        warning.warningType = .kiTermWarningTypePermanentlySilenceable
        warning.heading = isDirectory ? "Paste Folder" : (singleFile ? "Paste File" : "Paste Files")
        warning.cancelLabel = FilePasteAction.cancel.rawValue
        warning.window = delegate?.nonTextPasteHelperWindow(self)

        warning.runModalAsync { [weak self] selection, _ in
            guard let self = self else {
                DLog("handleFilePaste: self was deallocated")
                return
            }
            let index = self.selectionToIndex(selection)
            DLog("handleFilePaste: user selected index \(index)")
            guard index >= 0 && index < actions.count else {
                DLog("handleFilePaste: invalid selection index")
                return
            }

            switch actions[index] {
            case .pastePath:
                DLog("handleFilePaste: pastePath")
                self.delegate?.nonTextPasteHelper(self, pasteString: existingPaths.first!.quotedStringForPaste())
            case .pastePaths:
                DLog("handleFilePaste: pastePaths")
                let escapedPaths = existingPaths.map { $0.quotedStringForPaste() }.joined(separator: " ")
                self.delegate?.nonTextPasteHelper(self, pasteString: escapedPaths)
            case .pasteBase64:
                DLog("handleFilePaste: pasteBase64")
                self.pasteBase64EncodedContents(of: existingPaths.first!)
            case .pasteBase64Archive:
                DLog("handleFilePaste: pasteBase64Archive")
                self.pasteBase64EncodedArchive(of: existingPaths.first!)
            case .pasteAsText:
                DLog("handleFilePaste: pasteAsText")
                self.pasteFileAsText(existingPaths.first!)
            case .upload:
                DLog("handleFilePaste: upload")
                self.delegate?.nonTextPasteHelper(self, uploadFiles: existingPaths)
            case .uploadAndPastePath:
                DLog("handleFilePaste: uploadAndPastePath")
                self.delegate?.nonTextPasteHelper(self, uploadFileAndPastePath: existingPaths.first!)
            case .cancel:
                DLog("handleFilePaste: cancelled")
                break
            }
        }
        return true
    }

    private func descriptionForFiles(_ paths: [String], isDirectory: Bool = false) -> String {
        if paths.count == 1 {
            let filename = (paths.first! as NSString).lastPathComponent
            let prefix = isDirectory ? " the folder " : ""
            return "\(prefix)\u{201C}\(filename)\u{201D}"
        } else if paths.count <= 3 {
            let filenames = paths.map { "\u{201C}\(($0 as NSString).lastPathComponent)\u{201D}" }
            return filenames.joined(separator: ", ")
        } else {
            let first = (paths.first! as NSString).lastPathComponent
            return "\u{201C}\(first)\u{201D} and \(paths.count - 1) other files"
        }
    }

    private func isDirectoryPath(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func selectionToIndex(_ selection: iTermWarningSelection) -> Int {
        switch selection {
        case .kiTermWarningSelection0: return 0
        case .kiTermWarningSelection1: return 1
        case .kiTermWarningSelection2: return 2
        case .kiTermWarningSelection3: return 3
        case .kiTermWarningSelection4: return 4
        case .kiTermWarningSelection5: return 5
        case .kiTermWarningSelection6: return 6
        default: return -1
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Paste Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window = delegate?.nonTextPasteHelperWindow(self) {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private enum ImagePasteAction: String {
        case saveTempAndPastePath = "Save to Temp File and Paste Path"
        case pasteBase64 = "Paste Base64-Encoded Contents"
        case upload = "Upload"
        case uploadAndPastePath = "Upload and Paste Path"
        case cancel = "Cancel"
    }

    private func handleImageDataPaste(imageData: Data, fileExtension: String?) -> Bool {
        DLog("handleImageDataPaste: \(imageData.count) bytes, extension=\(fileExtension ?? "nil")")
        let canUpload = delegate?.nonTextPasteHelperCanUpload(self) ?? false
        let sizeDescription = ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .file)
        let typeDescription = fileExtension.map { imageTypeDescription($0) } ?? "some"

        DLog("handleImageDataPaste: canUpload=\(canUpload)")

        // Build actions based on whether we can upload and whether we know the file type
        var actions = [ImagePasteAction]()
        if fileExtension != nil {
            if canUpload {
                actions.append(.uploadAndPastePath)
                actions.append(.upload)
            } else {
                actions.append(.saveTempAndPastePath)
            }
        }
        actions.append(.pasteBase64)
        actions.append(.cancel)

        DLog("handleImageDataPaste: actions=\(actions.map { $0.rawValue })")

        let warning = iTermWarning()
        warning.title = "The clipboard contains \(typeDescription) image data (\(sizeDescription)). How would you like to paste it?"
        warning.actionLabels = actions.map { $0.rawValue }
        warning.identifier = canUpload ? "NoSyncPasteImageDataRemote" : "NoSyncPasteImageData"
        warning.warningType = .kiTermWarningTypePermanentlySilenceable
        warning.heading = "Paste Image"
        warning.cancelLabel = ImagePasteAction.cancel.rawValue
        warning.window = delegate?.nonTextPasteHelperWindow(self)

        warning.runModalAsync { [weak self] selection, _ in
            guard let self = self else {
                DLog("handleImageDataPaste: self was deallocated")
                return
            }
            let index = self.selectionToIndex(selection)
            DLog("handleImageDataPaste: user selected index \(index)")
            guard index >= 0 && index < actions.count else {
                DLog("handleImageDataPaste: invalid selection index")
                return
            }

            switch actions[index] {
            case .saveTempAndPastePath:
                DLog("handleImageDataPaste: saveTempAndPastePath")
                self.saveTempFileAndPastePath(imageData: imageData, fileExtension: fileExtension!)
            case .pasteBase64:
                DLog("handleImageDataPaste: pasteBase64")
                let base64 = (imageData as NSData).stringWithBase64Encoding(withLineBreak: "\r")
                self.pasteBase64WithConfirmationIfNeeded(base64)
            case .upload:
                DLog("handleImageDataPaste: upload")
                self.uploadImageData(imageData, fileExtension: fileExtension!, pastePath: false)
            case .uploadAndPastePath:
                DLog("handleImageDataPaste: uploadAndPastePath")
                self.uploadImageData(imageData, fileExtension: fileExtension!, pastePath: true)
            case .cancel:
                DLog("handleImageDataPaste: cancelled")
                break
            }
        }
        return true
    }

    private func uploadImageData(_ imageData: Data, fileExtension: String, pastePath: Bool) {
        DLog("uploadImageData: \(imageData.count) bytes, extension=\(fileExtension), pastePath=\(pastePath)")
        guard let tempPath = saveImageToTempFile(imageData: imageData, fileExtension: fileExtension) else {
            DLog("uploadImageData: failed to save temp file")
            return
        }
        if pastePath {
            DLog("uploadImageData: calling delegate uploadFileAndPastePath")
            delegate?.nonTextPasteHelper(self, uploadFileAndPastePath: tempPath)
        } else {
            DLog("uploadImageData: calling delegate uploadFiles")
            delegate?.nonTextPasteHelper(self, uploadFiles: [tempPath])
        }
    }

    private func saveImageToTempFile(imageData: Data, fileExtension: String) -> String? {
        DLog("saveImageToTempFile: \(imageData.count) bytes, extension=\(fileExtension)")
        guard let tempDir = FileManager.default.it_temporaryDirectory() else {
            DLog("saveImageToTempFile: failed to get temporary directory")
            showError("Could not create temporary directory.")
            return nil
        }

        let timestamp = Self.timestampFormatter.string(from: Date())
        let filename = "pasted-image-\(timestamp).\(fileExtension)"
        let tempPath = (tempDir as NSString).appendingPathComponent(filename)

        do {
            try imageData.write(to: URL(fileURLWithPath: tempPath))
            DLog("saveImageToTempFile: saved to \(tempPath)")
            return tempPath
        } catch {
            DLog("saveImageToTempFile: failed to write: \(error)")
            showError("Could not save image to temporary file: \(error.localizedDescription)")
            return nil
        }
    }

    private func imageTypeDescription(_ fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "png": return "a PNG"
        case "jpg", "jpeg": return "a JPEG"
        case "gif": return "a GIF"
        case "tiff", "tif": return "a TIFF"
        case "bmp": return "a BMP"
        case "webp": return "a WebP"
        case "heic": return "a HEIC"
        default: return "an"
        }
    }

    private func firstFileIsValidUTF8(_ paths: [String]) -> Bool {
        guard let firstPath = paths.first,
              let data = FileManager.default.contents(atPath: firstPath) else {
            return false
        }
        return String(data: data, encoding: .utf8) != nil
    }

    private func pasteBase64EncodedContents(of path: String) {
        DLog("pasteBase64EncodedContents: \(path)")
        guard let data = FileManager.default.contents(atPath: path) else {
            DLog("pasteBase64EncodedContents: failed to read file")
            let filename = (path as NSString).lastPathComponent
            showError("Could not read file \u{201C}\(filename)\u{201D}.")
            return
        }
        DLog("pasteBase64EncodedContents: read \(data.count) bytes")
        let base64 = (data as NSData).stringWithBase64Encoding(withLineBreak: "\r")
        pasteBase64WithConfirmationIfNeeded(base64)
    }

    private func pasteBase64EncodedArchive(of folderPath: String) {
        DLog("pasteBase64EncodedArchive: \(folderPath)")
        let folderName = (folderPath as NSString).lastPathComponent
        let parentPath = (folderPath as NSString).deletingLastPathComponent

        do {
            // Create archive with just the folder name, relative to parent
            let data = try NSData(tgzContainingFiles: [folderName],
                                  relativeToPath: parentPath,
                                  includeExtendedAttrs: false)
            DLog("pasteBase64EncodedArchive: created archive of \(data.count) bytes")
            let base64 = data.stringWithBase64Encoding(withLineBreak: "\r")
            pasteBase64WithConfirmationIfNeeded(base64)
        } catch {
            DLog("pasteBase64EncodedArchive: failed to create archive: \(error)")
            showError("Could not create archive of \u{201C}\(folderName)\u{201D}: \(error.localizedDescription)")
        }
    }

    private func pasteBase64WithConfirmationIfNeeded(_ base64: String) {
        let threshold = 10_000
        if base64.count <= threshold {
            delegate?.nonTextPasteHelper(self, pasteString:base64)
            return
        }

        let warning = iTermWarning()
        warning.title = "OK to paste \(base64.count.formatted()) bytes of base64-encoded data?"
        warning.actionLabels = ["OK", "Cancel"]
        warning.identifier = "NoSyncPasteLargeBase64"
        warning.warningType = .kiTermWarningTypePermanentlySilenceable
        warning.heading = "Large Paste"
        warning.cancelLabel = "Cancel"
        warning.window = delegate?.nonTextPasteHelperWindow(self)

        warning.runModalAsync { [weak self] selection, _ in
            guard let self = self else { return }
            if selection == .kiTermWarningSelection0 {
                self.delegate?.nonTextPasteHelper(self, pasteString: base64)
            }
        }
    }

    private func pasteFileAsText(_ path: String) {
        let filename = (path as NSString).lastPathComponent
        guard let data = FileManager.default.contents(atPath: path) else {
            showError("Could not read file \u{201C}\(filename)\u{201D}.")
            return
        }
        guard let text = String(data: data, encoding: .utf8) else {
            showError("File \u{201C}\(filename)\u{201D} is not valid UTF-8 text.")
            return
        }
        delegate?.nonTextPasteHelper(self, pasteString: text)
    }

    private func saveTempFileAndPastePath(imageData: Data, fileExtension: String) {
        DLog("saveTempFileAndPastePath: \(imageData.count) bytes, extension=\(fileExtension)")
        guard let tempPath = saveImageToTempFile(imageData: imageData, fileExtension: fileExtension) else {
            DLog("saveTempFileAndPastePath: failed to save temp file")
            return
        }
        let escapedPath = tempPath.quotedStringForPaste()
        DLog("saveTempFileAndPastePath: pasting path \(escapedPath)")
        delegate?.nonTextPasteHelper(self, pasteString: escapedPath)
    }
}
