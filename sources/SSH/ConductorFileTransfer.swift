//
//  ConductorFileTransfer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/2/23.
//

import Foundation

@MainActor
protocol ConductorFileTransferDelegate: AnyObject {
    func beginDownload(fileTransfer: ConductorFileTransfer)
    func beginUpload(fileTransfer: ConductorFileTransfer)
}

@MainActor
@objc
class ConductorFileTransfer: TransferrableFile {
    @objc var path: SCPPath
    weak var delegate: ConductorFileTransferDelegate?
    private var _error = ""
    private var _localPath: String?
    // Whether this is a download, which stays true once it ends. The Downloads menu and Clear
    // All go by this (F-714).
    private var isDownload = false
    let data: Data?

    private enum State {
        case idle
        case downloading
        case uploading
        case downloadComplete
        case uploadComplete
        case failed
    }
    private var state = State.idle

    init(path: SCPPath,
         localPath: String?,
         data: Data?,
         delegate: ConductorFileTransferDelegate) {
        self.path = path
        self.data = data
        self._localPath = localPath
        self.delegate = delegate
    }

    override func displayName() -> String? {
        let username = path.username ?? String(localized: "ConductorFileTransfer.UnknownUserName",
                                                defaultValue: "(unknown)",
                                                comment: "Shown in place of the user name in an SSH Integration file transfer description when the user name is not known")
        return String(localized: "ConductorFileTransfer.DisplayName", defaultValue: """
        iTerm2 SSH Integration Protocol
        User name: \(username)
        Host: \(path.hostname!)
        File: \(path.path!)
        """, comment: "Multi-line description of an SSH Integration file transfer")
    }

    override func shortName() -> String? {
        return path.path.lastPathComponent
    }

    override func subheading() -> String? {
        String(localized: "ConductorFileTransfer.ViaSSHIntegration", defaultValue: "\(path.hostname!) via SSH Integration", comment: "Label indicating a transfer uses SSH Integration. %@ is the host name.")
    }

    override func authRequestor() -> String? {
        if let username = path.username {
            return username + "@" + path.hostname!
        }
        return path.hostname!
    }

    override func protocolName() -> String? {
        return String(localized: "ConductorFileTransfer.ProtocolName", defaultValue: "SSH Integration", comment: "Name of the SSH Integration file transfer protocol")
    }

    private var chunked = false

    // The hidden file in the Downloads folder that a download() saves to until it finishes
    // and is renamed. It is removed if the download fails or is stopped first (F-724).
    private var temporaryDownloadPath: String?

    // Tests save downloads somewhere other than the Downloads folder.
    static var temporaryDirectoryForTesting: String?

    func downloadChunked() -> Bool {
        chunked = true
        download()
        return status == .transferring
    }

    override func download() {
        isDownload = true
        state = .downloading
        status = .starting
        do {
            let temporaryPath = try temporaryFilePath()
            _localPath = temporaryPath
            if !chunked {
                // The delegate creates it. A chunked download's caller saves the file itself.
                temporaryDownloadPath = temporaryPath
            }
            FileTransferManager.sharedInstance().files.add(self)
            FileTransferManager.sharedInstance().transferrableFileDidStartTransfer(self)
            status = .transferring
            if !chunked {
                delegate?.beginDownload(fileTransfer: self)
            }
        } catch {
            state = .failed
        }
    }

    private func temporaryFilePath() throws -> String {
        guard let downloads = Self.temporaryDirectoryForTesting ?? FileManager.default.downloadsDirectory() else {
            throw ConductorFileTransferError("Unable to find Downloads folder")
        }
        let tempFileName = ".iTerm2.\(UUID().uuidString)"
        return downloads.appendingPathComponent(tempFileName)
    }

    final class ConductorFileTransferError: NSObject, LocalizedError {
        private let reason: String
        init(_ reason: String) {
            self.reason = reason
        }
        override var description: String {
            get {
                return reason
            }
        }
        var errorDescription: String? {
            get {
                return reason
            }
        }
    }

    private func removeTemporaryDownload() {
        guard let temporaryDownloadPath else {
            return
        }
        self.temporaryDownloadPath = nil
        try? FileManager.default.removeItem(atPath: temporaryDownloadPath)
    }

    func fail(reason: String) {
        removeTemporaryDownload()
        _error = reason
        FileTransferManager.sharedInstance().transferrableFile(self, didFinishTransmissionWithError: ConductorFileTransferError(reason))
        state = .failed
    }

    private var url: URL {
        let components = NSURLComponents()
        components.host = path.hostname
        components.user = path.username
        components.path = path.path
        components.scheme = "ssh"
        return components.url!
    }

    @MainActor
    func didTransferBytes(_ count: UInt) {
        self.bytesTransferred = self.bytesTransferred + count
        if status == .transferring {
            FileTransferManager.sharedInstance().transferrableFileProgressDidChange(self)
        }
    }

    @MainActor
    func abort() {
        removeTemporaryDownload()
        FileTransferManager.sharedInstance().transferrableFileDidStopTransfer(self)
    }

    /// A chunked download (see downloadChunked()) whose caller saved the file to `destination`
    /// itself finished. Without this it would stay listed as downloading (F-714).
    @MainActor
    func didFinishChunkedDownload(to destination: URL) {
        guard state == .downloading else {
            return
        }
        if !quarantine(destination.path, sourceURL: url) {
            DLog("Failed to quarantine \(destination.path)")
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
        if let size = attributes?[FileAttributeKey.size] as? UInt {
            bytesTransferred = size
            fileSize = Int(size)
        }
        _localPath = destination.path
        state = .downloadComplete
        FileTransferManager.sharedInstance().transferrableFile(self, didFinishTransmissionWithError: nil)
    }

    @MainActor
    func didFinishSuccessfully() {
        if state == .downloading {
            if !quarantine(_localPath, sourceURL: url) {
                _error = String(localized: "ConductorFileTransfer.FailedToQuarantine", defaultValue: "Failed to quarantine", comment: "Error shown when a downloaded file cannot be quarantined")
                removeTemporaryDownload()
                FileTransferManager.sharedInstance().transferrableFile(self, didFinishTransmissionWithError: ConductorFileTransferError(_error))
                return
            }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: _localPath!) else {
                _error = String(localized: "ConductorFileTransfer.CouldNotGetAttributes", defaultValue: "Could not get attributes of \(_localPath!)", comment: "Error shown when file attributes of a downloaded file cannot be read")
                removeTemporaryDownload()
                FileTransferManager.sharedInstance().transferrableFile(self, didFinishTransmissionWithError: ConductorFileTransferError(_error))
                return
            }
            let size = attributes[FileAttributeKey.size] as? UInt ?? 0
            self.bytesTransferred = size
            self.fileSize = Int(size)

            let finalDestination = self.finalDestination(
                forPath: path.path.lastPathComponent,
                destinationDirectory: _localPath!.deletingLastPathComponent,
                prompt: true)!
            do {
                if FileManager.default.fileExists(atPath: finalDestination) {
                    try FileManager.default.replaceItem(at: URL(fileURLWithPath: finalDestination),
                                                        withItemAt: URL(fileURLWithPath: _localPath!),
                                                        backupItemName: nil,
                                                        resultingItemURL: nil)
                } else {
                    try FileManager.default.moveItem(at: URL(fileURLWithPath: _localPath!),
                                                     to: URL(fileURLWithPath: finalDestination))
                }
            } catch {
                _error = error.localizedDescription
            }
            // If it couldn't be moved into place, don't leave it behind.
            removeTemporaryDownload()
            _localPath = finalDestination
            state = .downloadComplete
            FileTransferManager.sharedInstance().transferrableFile(
                self,
                didFinishTransmissionWithError: nil)
        } else if state == .uploading {
            state = .uploadComplete
            FileTransferManager.sharedInstance().transferrableFile(
                self,
                didFinishTransmissionWithError: nil)
        }
    }

    // Name for uploads once established.
    var remoteName: String?
    override func destination() -> String? {
        switch state {
        case .downloading, .downloadComplete:
            return _localPath!
        case .uploading, .uploadComplete:
            return remoteName ?? path.path
        case .failed, .idle:
            return path.path
        }
    }

    private func sizeToUpload() -> Int? {
        if let data {
            return data.count
        }
        let path = localPath()!
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            guard let size = attrs[FileAttributeKey.size] as? Int else {
                _error = String(localized: "ConductorFileTransfer.CouldNotGetSize", defaultValue: "Could not get size of file: \(path)", comment: "Error shown when the size of a file to upload cannot be determined")
                state = .failed
                FileTransferManager.sharedInstance().transferrableFile(self, didFinishTransmissionWithError: ConductorFileTransferError(_error))
                return nil
            }
            return size
        } catch {
            _error = String(localized: "ConductorFileTransfer.NoSuchFile", defaultValue: "No such file: \(path)", comment: "Error shown when a file to upload does not exist")
            FileTransferManager.sharedInstance().transferrableFile(self, didFinishTransmissionWithError: error)
            state = .failed
            return nil
        }
    }

    override func upload() {
        state = .uploading
        status = .starting
        if let size = sizeToUpload() {
            fileSize = size
        } else {
            return
        }
        FileTransferManager.sharedInstance().files.add(self)
        FileTransferManager.sharedInstance().transferrableFileDidStartTransfer(self)
        status = .transferring
        delegate?.beginUpload(fileTransfer: self)
    }

    override func isDownloading() -> Bool {
        return isDownload
    }

    var isStopped: Bool {
        switch state {
        case .downloading, .uploading:
            return false
        default:
            return true
        }
    }

    override func stop() {
        guard !isStopped else { return }
        FileTransferManager.sharedInstance().transferrableFileWillStop(self)
        state = .failed
    }

    override func error() -> String? {
        return _error
    }

    override func localPath() -> String? {
        if data != nil {
            return String(localized: "ConductorFileTransfer.InMemory", defaultValue: "(In memory)", comment: "Placeholder shown for a file transfer whose contents are held in memory rather than on disk")
        }
        return _localPath
    }
}
