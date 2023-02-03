//
//  ConductorFileTransfer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/2/23.
//

import Foundation

@available(macOS 11, *)
protocol ConductorFileTransferDelegate: AnyObject {
    func beginDownload(fileTransfer: ConductorFileTransfer)
    func beginUpload(fileTransfer: ConductorFileTransfer)
}

@available(macOS 11, *)
@objc
class ConductorFileTransfer: TransferrableFile {
    @objc var path: SCPPath
    weak var delegate: ConductorFileTransferDelegate?
    private var _error = ""
    private var _localPath: String?

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
         delegate: ConductorFileTransferDelegate) {
        self.path = path
        self._localPath = localPath
        self.delegate = delegate
    }

    override func displayName() -> String! {
        return """
        iTerm2 SSH Integration Protocol
        User name: \(path.username!)
        Host: \(path.hostname!)
        File: \(path.path!)"
        """
    }

    override func shortName() -> String! {
        return path.path.lastPathComponent
    }

    override func subheading() -> String! {
        return path.username! + "@" + path.hostname! + ":" + path.path!
    }

    override func authRequestor() -> String! {
        return path.username! + "@" + path.hostname!
    }

    override func protocolName() -> String! {
        return "SSH Integration"
    }

    override func download() {
        state = .downloading
        status = .starting
        do {
            _localPath = try temporaryFilePath()
            FileTransferManager.sharedInstance().files.add(self)
            FileTransferManager.sharedInstance().transferrableFileDidStartTransfer(self)
            status = .transferring
            delegate?.beginDownload(fileTransfer: self)
        } catch {
            state = .failed
        }
    }

    private func temporaryFilePath() throws -> String {
        guard let downloads = FileManager.default.downloadsDirectory() else {
            throw ConductorFileTransferError("Unable to find Downloads folder")
        }
        let tempFileName = ".iTerm2.\(UUID().uuidString)"
        return downloads.appendingPathComponent(tempFileName)
    }

    class ConductorFileTransferError: NSObject, LocalizedError {
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

    func fail(reason: String) {
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
        FileTransferManager.sharedInstance().transferrableFileDidStopTransfer(self)
    }

    @MainActor
    func didFinishSuccessfully() {
        if state == .downloading {
            if !quarantine(_localPath, sourceURL: url) {
                _error = "Failed to quarantine"
                FileTransferManager.sharedInstance().transferrableFile(self, didFinishTransmissionWithError: ConductorFileTransferError(_error))
                return
            }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: _localPath!) else {
                _error = "Could not get attributes of \(_localPath!)"
                FileTransferManager.sharedInstance().transferrableFile(self, didFinishTransmissionWithError: ConductorFileTransferError(_error))
                return
            }
            let size = attributes[FileAttributeKey.size] as? UInt ?? 0
            self.bytesTransferred = size
            self.fileSize = Int(size)

            let finalDestination = self.finalDestination(
                forPath: path.path.lastPathComponent,
                destinationDirectory: _localPath!.deletingLastPathComponent)!
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
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: _localPath!))
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
    override func destination() -> String! {
        switch state {
        case .downloading, .downloadComplete:
            return _localPath!
        case .uploading, .uploadComplete:
            return remoteName ?? path.path
        case .failed, .idle:
            return path.path
        }
    }

    override func upload() {
        state = .uploading
        status = .starting
        let path = localPath()!
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            guard let size = attrs[FileAttributeKey.size] as? Int else {
                _error = "Could not get size of file: \(path)"
                state = .failed
                FileTransferManager.sharedInstance().transferrableFile(self, didFinishTransmissionWithError: ConductorFileTransferError(_error))
                return
            }
            fileSize = size
        } catch {
            _error = "No such file: \(path)"
            FileTransferManager.sharedInstance().transferrableFile(self, didFinishTransmissionWithError: error)
            state = .failed
            return
        }
        FileTransferManager.sharedInstance().files.add(self)
        FileTransferManager.sharedInstance().transferrableFileDidStartTransfer(self)
        status = .transferring
        delegate?.beginUpload(fileTransfer: self)
    }

    override func isDownloading() -> Bool {
        return state == .downloading
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
        FileTransferManager.sharedInstance().transferrableFileWillStop(self)
        state = .failed
    }

    override func error() -> String! {
        return _error
    }

    override func localPath() -> String! {
        return _localPath
    }
}
