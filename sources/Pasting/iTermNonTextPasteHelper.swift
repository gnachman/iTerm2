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
                RLog("hasFileURLs but no paths found")
                return false
            }
            RLog("Handling file paste with \(paths.count) paths")
            return handleFilePaste(paths)
        } else if pb.hasRawImageData() {
            guard let imageData = pb.rawImageData() else {
                RLog("hasRawImageData but rawImageData() returned nil")
                return false
            }
            // Try to determine the file extension, but proceed even if we can't
            var fileExtension: String? = nil
            if let utType = pb.rawImageDataUTType(),
               let type = UTType(utType) {
                fileExtension = type.preferredFilenameExtension
            }
            RLog("Handling image data paste: \(imageData.count) bytes, extension=\(fileExtension ?? "unknown")")
            return handleImageDataPaste(imageData: imageData, fileExtension: fileExtension)
        }
        DLog("No non-text content found on pasteboard")
        return false
    }

    @objc func showPasteOptionsForFiles(_ files: [String]) {
        _ = handleFilePaste(files)
    }

    // Raw values are stable identity (used for logging and for cancel-label matching); user-facing
    // button text comes from displayName.
    private enum FilePasteAction: String {
        case pastePath = "Paste Path"
        case pastePaths = "Paste Paths"
        case pasteBase64 = "Paste Base64-Encoded Contents"
        case pasteBase64Archive = "Paste Base64-Encoded Archive (tar.gz)"
        case pasteAsText = "Paste as Text"
        case upload = "Upload"
        case uploadAndPastePath = "Upload and Paste Path"
        case cancel = "Cancel"

        var displayName: String {
            switch self {
            case .pastePath: return String(localized: "NonTextPaste.PastePath", defaultValue: "Paste Path", comment: "Button to paste a file path")
            case .pastePaths: return String(localized: "NonTextPaste.PastePaths", defaultValue: "Paste Paths", comment: "Button to paste multiple file paths")
            case .pasteBase64: return String(localized: "NonTextPaste.PasteBase64", defaultValue: "Paste Base64-Encoded Contents", comment: "Button to paste base64-encoded file contents")
            case .pasteBase64Archive: return String(localized: "NonTextPaste.PasteBase64Archive", defaultValue: "Paste Base64-Encoded Archive (tar.gz)", comment: "Button to paste a base64-encoded tar.gz archive")
            case .pasteAsText: return String(localized: "NonTextPaste.PasteAsText", defaultValue: "Paste as Text", comment: "Button to paste a file as text")
            case .upload: return String(localized: "NonTextPaste.Upload", defaultValue: "Upload", comment: "Button to upload files")
            case .uploadAndPastePath: return String(localized: "NonTextPaste.UploadAndPastePath", defaultValue: "Upload and Paste Path", comment: "Button to upload a file and paste its path")
            case .cancel: return iTermLocalizedCancel()
            }
        }
    }

    private func handleFilePaste(_ paths: [String]) -> Bool {
        guard !paths.isEmpty else {
            return false
        }

        // Verify files exist
        let existingPaths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        if existingPaths.isEmpty {
            showError(String(localized: "NonTextPaste.CopiedFileMissing", defaultValue: "The copied file no longer exists.", comment: "Error when the file on the clipboard no longer exists"))
            return true
        }
        if existingPaths.count < paths.count {
            let missing = paths.count - existingPaths.count
            // Single-count plural so the one count drives both agreements (file/files and
            // exists/exist); a two-count "N of M" phrasing would need a two-variable substitution.
            showError(String(localized: "NonTextPaste.SomeFilesMissing", defaultValue: "\(missing) dropped files no longer exist and will be skipped.", comment: "Error when some dropped files are missing; %lld is the number of missing files"))
        }

        let singleFile = existingPaths.count == 1
        let canUpload = delegate?.nonTextPasteHelperCanUpload(self) ?? false
        let isDirectory = singleFile && isDirectoryPath(existingPaths.first!)
        let canPasteAsText = singleFile && !isDirectory && firstFileIsValidUTF8(existingPaths)

        RLog("handleFilePaste: singleFile=\(singleFile) canUpload=\(canUpload) isDirectory=\(isDirectory) canPasteAsText=\(canPasteAsText)")

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
        let warning = iTermWarning()
        warning.title = pasteFilesPrompt(existingPaths, isDirectory: isDirectory)
        warning.actionLabels = actions.map { $0.displayName }
        warning.identifier = singleFile ? "NoSyncPasteNonTextFile" : "NoSyncPasteNonTextFiles"
        warning.warningType = .kiTermWarningTypePermanentlySilenceable
        if isDirectory {
            warning.heading = String(localized: "NonTextPaste.PasteFolderHeading", defaultValue: "Paste Folder", comment: "Heading of the dialog for pasting a folder")
        } else if singleFile {
            warning.heading = String(localized: "NonTextPaste.PasteFileHeading", defaultValue: "Paste File", comment: "Heading of the dialog for pasting a single file")
        } else {
            warning.heading = String(localized: "NonTextPaste.PasteFilesHeading", defaultValue: "Paste Files", comment: "Heading of the dialog for pasting multiple files")
        }
        warning.cancelLabel = FilePasteAction.cancel.displayName
        warning.window = delegate?.nonTextPasteHelperWindow(self)

        warning.runModalAsync { [weak self] selection, _ in
            guard let self = self else {
                DLog("handleFilePaste: self was deallocated")
                return
            }
            let index = self.selectionToIndex(selection)
            RLog("handleFilePaste: user selected index \(index)")
            guard index >= 0 && index < actions.count else {
                RLog("handleFilePaste: invalid selection index")
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

    // A complete localized prompt per case rather than injecting a partly-localized description into
    // a frame. File names are self-contained values and are interpolated; the many-files case varies
    // by plural on the count (String Catalog Vary-by-Plural; see CLAUDE.md).
    private func pasteFilesPrompt(_ paths: [String], isDirectory: Bool) -> String {
        if paths.count == 1 {
            let filename = (paths.first! as NSString).lastPathComponent
            if isDirectory {
                return String(localized: "NonTextPaste.PasteOneFolderPrompt", defaultValue: "How would you like to paste the folder \u{201C}\(filename)\u{201D}?", comment: "Prompt asking how to paste a single folder; the placeholder is the folder name")
            }
            return String(localized: "NonTextPaste.PasteOneFilePrompt", defaultValue: "How would you like to paste the file \u{201C}\(filename)\u{201D}?", comment: "Prompt asking how to paste a single file; the placeholder is the file name")
        } else if paths.count <= 3 {
            let joined = paths.map { "\u{201C}\(($0 as NSString).lastPathComponent)\u{201D}" }.joined(separator: ", ")
            return String(localized: "NonTextPaste.PasteFewFilesPrompt", defaultValue: "How would you like to paste \(joined)?", comment: "Prompt asking how to paste a few files; the placeholder is a comma-separated list of file names")
        } else {
            return String(localized: "NonTextPaste.PasteManyFilesPrompt", defaultValue: "How would you like to paste these \(paths.count) files?", comment: "Prompt asking how to paste many files; the placeholder is the number of files")
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
        alert.messageText = String(localized: "NonTextPaste.PasteFailedTitle", defaultValue: "Paste Failed", comment: "Title of the dialog shown when a paste operation fails")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: iTermLocalizedOK())
        if let window = delegate?.nonTextPasteHelperWindow(self) {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    // Raw values are stable identity (logging and cancel-label matching); text comes from displayName.
    private enum ImagePasteAction: String {
        case saveTempAndPastePath = "Save to Temp File and Paste Path"
        case pasteBase64 = "Paste Base64-Encoded Contents"
        case upload = "Upload"
        case uploadAndPastePath = "Upload and Paste Path"
        case cancel = "Cancel"

        var displayName: String {
            switch self {
            case .saveTempAndPastePath: return String(localized: "NonTextPaste.SaveTempAndPastePath", defaultValue: "Save to Temp File and Paste Path", comment: "Button to save image data to a temp file and paste its path")
            case .pasteBase64: return String(localized: "NonTextPaste.PasteBase64", defaultValue: "Paste Base64-Encoded Contents", comment: "Button to paste base64-encoded file contents")
            case .upload: return String(localized: "NonTextPaste.Upload", defaultValue: "Upload", comment: "Button to upload files")
            case .uploadAndPastePath: return String(localized: "NonTextPaste.UploadAndPastePath", defaultValue: "Upload and Paste Path", comment: "Button to upload a file and paste its path")
            case .cancel: return iTermLocalizedCancel()
            }
        }
    }

    private func handleImageDataPaste(imageData: Data, fileExtension: String?) -> Bool {
        DLog("handleImageDataPaste: \(imageData.count) bytes, extension=\(fileExtension ?? "nil")")
        let canUpload = delegate?.nonTextPasteHelperCanUpload(self) ?? false
        let sizeDescription = ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .file)

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
        warning.title = imageDataPrompt(fileExtension: fileExtension, size: sizeDescription)
        warning.actionLabels = actions.map { $0.displayName }
        warning.identifier = canUpload ? "NoSyncPasteImageDataRemote" : "NoSyncPasteImageData"
        warning.warningType = .kiTermWarningTypePermanentlySilenceable
        warning.heading = String(localized: "NonTextPaste.PasteImageHeading", defaultValue: "Paste Image", comment: "Heading for the paste-image options dialog")
        warning.cancelLabel = ImagePasteAction.cancel.displayName
        warning.window = delegate?.nonTextPasteHelperWindow(self)

        warning.runModalAsync { [weak self] selection, _ in
            guard let self = self else {
                DLog("handleImageDataPaste: self was deallocated")
                return
            }
            let index = self.selectionToIndex(selection)
            RLog("handleImageDataPaste: user selected index \(index)")
            guard index >= 0 && index < actions.count else {
                RLog("handleImageDataPaste: invalid selection index")
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
            RLog("uploadImageData: failed to save temp file")
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
            RLog("saveImageToTempFile: failed to get temporary directory")
            showError(String(localized: "NonTextPaste.CouldNotCreateTempDir", defaultValue: "Could not create temporary directory.", comment: "Error when a temporary directory cannot be created"))
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
            RLog("saveImageToTempFile: failed to write: \(error)")
            showError(String(localized: "NonTextPaste.CouldNotSaveImage", defaultValue: "Could not save image to temporary file: \(error.localizedDescription)", comment: "Error when a pasted image cannot be written to a temporary file"))
            return nil
        }
    }

    // A complete localized prompt per image type rather than injecting an article+type fragment
    // ("a PNG", "an", "some") into a frame, whose grammar and word order differ by language. The
    // size is a self-contained value, so interpolating it is fine.
    private func imageDataPrompt(fileExtension: String?, size: String) -> String {
        switch fileExtension?.lowercased() {
        case "png": return String(localized: "NonTextPaste.PastePNGPrompt", defaultValue: "The clipboard contains a PNG image (\(size)). How would you like to paste it?", comment: "Prompt asking how to paste a PNG image; the placeholder is a size")
        case "jpg", "jpeg": return String(localized: "NonTextPaste.PasteJPEGPrompt", defaultValue: "The clipboard contains a JPEG image (\(size)). How would you like to paste it?", comment: "Prompt asking how to paste a JPEG image; the placeholder is a size")
        case "gif": return String(localized: "NonTextPaste.PasteGIFPrompt", defaultValue: "The clipboard contains a GIF image (\(size)). How would you like to paste it?", comment: "Prompt asking how to paste a GIF image; the placeholder is a size")
        case "tiff", "tif": return String(localized: "NonTextPaste.PasteTIFFPrompt", defaultValue: "The clipboard contains a TIFF image (\(size)). How would you like to paste it?", comment: "Prompt asking how to paste a TIFF image; the placeholder is a size")
        case "bmp": return String(localized: "NonTextPaste.PasteBMPPrompt", defaultValue: "The clipboard contains a BMP image (\(size)). How would you like to paste it?", comment: "Prompt asking how to paste a BMP image; the placeholder is a size")
        case "webp": return String(localized: "NonTextPaste.PasteWebPPrompt", defaultValue: "The clipboard contains a WebP image (\(size)). How would you like to paste it?", comment: "Prompt asking how to paste a WebP image; the placeholder is a size")
        case "heic": return String(localized: "NonTextPaste.PasteHEICPrompt", defaultValue: "The clipboard contains a HEIC image (\(size)). How would you like to paste it?", comment: "Prompt asking how to paste a HEIC image; the placeholder is a size")
        case nil: return String(localized: "NonTextPaste.PasteUnknownImagePrompt", defaultValue: "The clipboard contains image data (\(size)). How would you like to paste it?", comment: "Prompt asking how to paste image data of unknown type; the placeholder is a size")
        default: return String(localized: "NonTextPaste.PasteGenericImagePrompt", defaultValue: "The clipboard contains an image (\(size)). How would you like to paste it?", comment: "Prompt asking how to paste an image of an unrecognized type; the placeholder is a size")
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
            RLog("pasteBase64EncodedContents: failed to read file")
            let filename = (path as NSString).lastPathComponent
            showError(String(localized: "NonTextPaste.CouldNotReadFile", defaultValue: "Could not read file \u{201C}\(filename)\u{201D}.", comment: "Error when a file cannot be read"))
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
            RLog("pasteBase64EncodedArchive: failed to create archive: \(error)")
            showError(String(localized: "NonTextPaste.CouldNotCreateArchive", defaultValue: "Could not create archive of \u{201C}\(folderName)\u{201D}: \(error.localizedDescription)", comment: "Error when creating a base64 archive of a folder fails"))
        }
    }

    private func pasteBase64WithConfirmationIfNeeded(_ base64: String) {
        let threshold = 10_000
        if base64.count <= threshold {
            delegate?.nonTextPasteHelper(self, pasteString:base64)
            return
        }

        let warning = iTermWarning()
        // Varies by plural on the byte count (String Catalog Vary-by-Plural; see CLAUDE.md).
        warning.title = String(localized: "NonTextPaste.LargePasteConfirm", defaultValue: "OK to paste \(base64.count) bytes of base64-encoded data?", comment: "Confirmation prompt before pasting a large base64 blob; the number is a byte count")
        warning.actionLabels = [iTermLocalizedOK(), iTermLocalizedCancel()]
        warning.identifier = "NoSyncPasteLargeBase64"
        warning.warningType = .kiTermWarningTypePermanentlySilenceable
        warning.heading = String(localized: "NonTextPaste.LargePasteHeading", defaultValue: "Large Paste", comment: "Heading for the large-paste confirmation dialog")
        warning.cancelLabel = iTermLocalizedCancel()
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
            showError(String(localized: "NonTextPaste.CouldNotReadFile", defaultValue: "Could not read file \u{201C}\(filename)\u{201D}.", comment: "Error when a file cannot be read"))
            return
        }
        guard let text = String(data: data, encoding: .utf8) else {
            showError(String(localized: "NonTextPaste.FileNotUTF8", defaultValue: "File \u{201C}\(filename)\u{201D} is not valid UTF-8 text.", comment: "Error when a file cannot be pasted as text because it is not valid UTF-8"))
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
