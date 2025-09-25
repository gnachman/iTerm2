//
//  iTermBrowserDownload.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import Foundation
@preconcurrency import WebKit

@available(macOS 11.3, *)
@objc(iTermBrowserDownload)
class iTermBrowserDownload: TransferrableFile {
    private let wkDownload: WKDownload
    private let sourceURL: URL
    private let suggestedFilename: String
    private var _localPath: String?
    private var _error: String = ""
    private var destinationURL: URL?
    
    private enum State {
        case idle
        case downloading
        case downloadComplete
        case failed
    }
    private var state = State.idle
    
    init(wkDownload: WKDownload, sourceURL: URL, suggestedFilename: String) {
        self.wkDownload = wkDownload
        self.sourceURL = sourceURL
        self.suggestedFilename = suggestedFilename
        super.init()
        
        wkDownload.delegate = self
        
        // Set up progress observation
        wkDownload.progress.addObserver(self, 
                                        forKeyPath: "fractionCompleted", 
                                        options: .new, 
                                        context: nil)
        wkDownload.progress.addObserver(self, 
                                        forKeyPath: "completedUnitCount", 
                                        options: .new, 
                                        context: nil)
    }
    
    deinit {
        wkDownload.progress.removeObserver(self, forKeyPath: "fractionCompleted")
        wkDownload.progress.removeObserver(self, forKeyPath: "completedUnitCount")
    }
    
    // MARK: - TransferrableFile Overrides
    
    override func displayName() -> String! {
        return """
        Browser Download
        Source: \(sourceURL.absoluteString)
        File: \(suggestedFilename)
        """
    }
    
    override func shortName() -> String! {
        return suggestedFilename
    }
    
    override func subheading() -> String! {
        return sourceURL.host ?? sourceURL.absoluteString
    }
    
    override func authRequestor() -> String! {
        return sourceURL.host ?? "Browser"
    }
    
    override func protocolName() -> String! {
        return "Browser Download"
    }
    
    override func download() {
        state = .downloading
        status = .starting
        FileTransferManager.sharedInstance().files.add(self)
        FileTransferManager.sharedInstance().transferrableFileDidStartTransfer(self)
        status = .transferring
        
        // WKDownload starts automatically, we just need to handle the delegate methods
    }
    
    override func upload() {
        // Not supported for browser downloads
    }
    
    override func stop() {
        FileTransferManager.sharedInstance().transferrableFileWillStop(self)
        wkDownload.cancel()
        state = .failed
        status = .cancelling
    }
    
    override func localPath() -> String! {
        return _localPath
    }
    
    override func error() -> String! {
        return _error
    }
    
    override func destination() -> String! {
        return destinationURL?.path ?? _localPath
    }
    
    override func isDownloading() -> Bool {
        return true
    }
    
    // MARK: - Progress Observation
    
    override func observeValue(forKeyPath keyPath: String?, 
                              of object: Any?, 
                              change: [NSKeyValueChangeKey : Any]?, 
                              context: UnsafeMutableRawPointer?) {
        if keyPath == "completedUnitCount" {
            DispatchQueue.main.async {
                self.bytesTransferred = UInt(self.wkDownload.progress.completedUnitCount)
                if self.state == .downloading {
                    FileTransferManager.sharedInstance().transferrableFileProgressDidChange(self)
                }
            }
        } else if keyPath == "fractionCompleted" {
            DispatchQueue.main.async {
                if self.wkDownload.progress.totalUnitCount > 0 {
                    self.fileSize = Int(self.wkDownload.progress.totalUnitCount)
                }
            }
        }
    }
}

// MARK: - WKDownloadDelegate

@available(macOS 11.3, *)
extension iTermBrowserDownload: WKDownloadDelegate {
    func download(_ download: WKDownload, 
                  decideDestinationUsing response: URLResponse, 
                  suggestedFilename: String, 
                  completionHandler: @escaping (URL?) -> Void) {
        
        // Use iTerm2's downloads directory
        guard let downloadsDir = FileManager.default.downloadsDirectory() else {
            _error = "Unable to find Downloads folder"
            completionHandler(nil)
            return
        }
        
        // Generate final destination path
        let finalDestination = self.finalDestination(forPath: suggestedFilename, 
                                                     destinationDirectory: downloadsDir,
                                                     prompt: false)!
        destinationURL = URL(fileURLWithPath: finalDestination)
        
        completionHandler(destinationURL)
    }
    
    func downloadDidFinish(_ download: WKDownload) {
        DispatchQueue.main.async {
            // Quarantine the downloaded file
            if let destURL = self.destinationURL {
                if !self.quarantine(destURL.path, sourceURL: self.sourceURL) {
                    self.failedToRemoveUnquarantinedFile(at: destURL.path)
                }
                self._localPath = destURL.path
            }
            
            self.state = .downloadComplete
            self.status = .finishedSuccessfully
            FileTransferManager.sharedInstance().transferrableFile(self, 
                                                                   didFinishTransmissionWithError: nil)
        }
    }
    
    func download(_ download: WKDownload, 
                  didFailWithError error: Error, 
                  resumeData: Data?) {
        DispatchQueue.main.async {
            self._error = error.localizedDescription
            self.state = .failed
            self.status = .finishedWithError
            FileTransferManager.sharedInstance().transferrableFile(self, 
                                                                   didFinishTransmissionWithError: error)
        }
    }
}
